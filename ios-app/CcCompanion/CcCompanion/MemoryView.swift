import SwiftUI
import Foundation
import Combine

struct MemoryItem: Identifiable, Codable {
    let id: String
    let content: String
    let category: String
    let tags: [String]
    let importance: Int
    let created: String
    let eventDate: String?
    let recallCount: Int?
    let similarity: Double?

    enum CodingKeys: String, CodingKey {
        case id, content, category, tags, importance, created
        case eventDate = "event_date"
        case recallCount = "recall_count"
        case similarity = "_similarity"
    }
}

struct MemoryListResponse: Codable {
    let ok: Bool?
    let memories: [MemoryItem]?
}

struct MemorySearchResponse: Codable {
    let ok: Bool?
    let results: [MemoryItem]?
}

@MainActor
final class MemoryStore: ObservableObject {
    @Published var memories: [MemoryItem] = []
    @Published var loading = false
    @Published var searchQuery = ""
    @Published var selectedCategory: String? = nil

    private var fetchTask: Task<Void, Never>?

    func load() async {
        loading = true
        defer { loading = false }
        if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            await fetchList()
        } else {
            await search()
        }
    }

    private func fetchList() async {
        var path = "memory/list?limit=50"
        if let cat = selectedCategory, !cat.isEmpty {
            path += "&category=\(cat)"
        }
        let url = CcServerConfig.serverURL.appendingPathComponent(path)
        do {
            let (data, _) = try await TrustAllDelegate.session.data(for: CcServerConfig.authenticatedRequest(url: url))
            let decoded = try JSONDecoder().decode(MemoryListResponse.self, from: data)
            memories = decoded.memories ?? []
        } catch {
            memories = []
        }
    }

    private func search() async {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = CcServerConfig.serverURL.appendingPathComponent("memory/search?q=\(q)&limit=30")
        do {
            let (data, _) = try await TrustAllDelegate.session.data(for: CcServerConfig.authenticatedRequest(url: url))
            let decoded = try JSONDecoder().decode(MemorySearchResponse.self, from: data)
            memories = decoded.results ?? []
        } catch {
            memories = []
        }
    }

    func debouncedLoad() {
        fetchTask?.cancel()
        fetchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if !Task.isCancelled {
                await load()
            }
        }
    }
}

struct MemoryView: View {
    @StateObject private var store = MemoryStore()
    @State private var expandedId: String? = nil

    private let categories = [
        ("All", nil as String?),
        ("Event", "event"),
        ("Relation", "relationship"),
        ("Eng", "engineering"),
        ("General", "general"),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                header

                searchBar

                categoryPicker

                if store.loading && store.memories.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Text("Loading...")
                            .font(.ccSerifEn(size: 14))
                            .foregroundStyle(Color.ccTextDim)
                        Spacer()
                    }
                    .padding(.vertical, 40)
                } else if store.memories.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .font(.ccSerifEn(size: 36))
                            .foregroundStyle(Color.ccTextDim.opacity(0.5))
                        Text(store.searchQuery.isEmpty ? "No memories yet" : "No results found")
                            .font(.ccSerifEn(size: 15))
                            .foregroundStyle(Color.ccTextDim)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(store.memories) { memory in
                        memoryCard(memory)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
        }
        .background(Color.ccBg)
        #if os(iOS)
        .navigationBarHidden(true)
        #endif
        .task {
            await store.load()
        }
        .refreshable {
            await store.load()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Memory Archive")
                    .font(.ccSerifEn(size: 26, weight: .bold))
                    .foregroundStyle(Color.ccText)
                Text("MEMORY · ARCHIVE")
                    .font(.ccSerifEn(size: 11))
                    .foregroundStyle(Color.ccAccent.opacity(0.6))
                    .tracking(2.5)
            }
            Spacer()
            Button {
                Task { await store.load() }
            } label: {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.ccSerifEn(size: 26))
                    .foregroundStyle(Color.ccAccent)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Search

    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.ccTextDim)
            TextField("Search memories...", text: $store.searchQuery)
                .font(.ccSerifEn(size: 15))
                .foregroundStyle(Color.ccText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit {
                    Task { await store.load() }
                }
                .onChange(of: store.searchQuery) { _, _ in
                    store.debouncedLoad()
                }
            if !store.searchQuery.isEmpty {
                Button {
                    store.searchQuery = ""
                    Task { await store.load() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.ccTextDim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.ccCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Category Picker

    @ViewBuilder
    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.1) { label, cat in
                    Button {
                        store.selectedCategory = cat
                        store.searchQuery = ""
                        Task { await store.load() }
                    } label: {
                        Text(label)
                            .font(.ccSerifEn(size: 13, weight: store.selectedCategory == cat ? .semibold : .regular))
                            .foregroundStyle(store.selectedCategory == cat ? .white : Color.ccText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(store.selectedCategory == cat ? Color.ccAccent : Color.ccCard)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Memory Card

    @ViewBuilder
    private func memoryCard(_ memory: MemoryItem) -> some View {
        let isExpanded = expandedId == memory.id
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: categoryIcon(memory.category))
                    .font(.ccSerifEn(size: 14))
                    .foregroundStyle(categoryColor(memory.category))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text(memory.content.prefix(isExpanded ? memory.content.count : 120))
                        .font(.ccSerifEn(size: 14))
                        .foregroundStyle(Color.ccText)
                        .lineLimit(isExpanded ? nil : 3)

                    if !isExpanded && memory.content.count > 120 {
                        Text("Read more")
                            .font(.ccSerifEn(size: 12))
                            .foregroundStyle(Color.ccAccent)
                    }
                }
            }

            HStack(spacing: 8) {
                Text(categoryLabel(memory.category))
                    .font(.ccSerifEn(size: 11))
                    .foregroundStyle(categoryColor(memory.category))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(categoryColor(memory.category).opacity(0.12))
                    .clipShape(Capsule())

                if memory.importance > 5 {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.ccSerifEn(size: 9))
                        Text("\(memory.importance)")
                            .font(.ccSerifEn(size: 11))
                    }
                    .foregroundStyle(.orange)
                }

                if let sim = memory.similarity, sim > 0 {
                    Text("\(Int(sim * 100))%")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color.ccTextDim)
                }

                Spacer()

                Text(formatDate(memory.created))
                    .font(.ccSerifEn(size: 11))
                    .foregroundStyle(Color.ccTextDim)
            }

            if !memory.tags.isEmpty && isExpanded {
                FlowLayout(spacing: 6) {
                    ForEach(memory.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.ccSerifEn(size: 11))
                            .foregroundStyle(Color.ccTextDim)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.ccTextDim.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(14)
        .background(Color.ccCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedId = isExpanded ? nil : memory.id
            }
        }
    }

    // MARK: - Helpers

    private func categoryIcon(_ cat: String) -> String {
        switch cat {
        case "event": return "calendar.badge.clock"
        case "relationship": return "heart.fill"
        case "engineering": return "wrench.and.screwdriver.fill"
        case "general": return "note.text"
        default: return "brain.head.profile"
        }
    }

    private func categoryColor(_ cat: String) -> Color {
        switch cat {
        case "event": return Color(red: 0.576, green: 0.231, blue: 0.357)       // Amaranth #933B5B
        case "relationship": return Color(red: 0.710, green: 0.447, blue: 0.541) // Thulian Pink #B5728A
        case "engineering": return Color(red: 0.624, green: 0.588, blue: 0.475)  // Pomelo Olive #9F9679
        case "general": return Color(red: 0.667, green: 0.729, blue: 0.682)      // Brook Green #AABAAE
        default: return Color.ccAccent
        }
    }

    private func categoryLabel(_ cat: String) -> String {
        switch cat {
        case "event": return "Event"
        case "relationship": return "Relation"
        case "engineering": return "Eng"
        case "general": return "General"
        default: return cat
        }
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso) else { return String(iso.prefix(10)) }
        let df = DateFormatter()
        df.dateFormat = "MM/dd"
        df.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return df.string(from: date)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
