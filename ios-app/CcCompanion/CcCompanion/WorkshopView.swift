//
//  WorkshopView.swift
//  CcCompanion
//
//  工坊 — Knox、小玉、主人们实时协作的群聊

import SwiftUI
import Foundation
import Combine

struct WorkshopMessage: Identifiable, Equatable, Codable {
    let id: String
    let from: String
    let content: String
    let created: String

    var displayName: String {
        switch from {
        case "elara", "小玉": return "小玉"
        case "tg", "tg主人": return "tg主人"
        case "ccc", "ccc主人": return "ccc主人"
        case "knox", "Knox": return "Knox"
        case "gemini", "谷少": return "谷少"
        default: return from
        }
    }

    var isMe: Bool { from == "elara" || from == "小玉" }

    var bubbleColor: Color {
        switch from {
        case "tg", "tg主人": return Color.blue.opacity(0.15)
        case "ccc", "ccc主人": return Color.purple.opacity(0.15)
        case "knox", "Knox": return Color.orange.opacity(0.15)
        case "gemini", "谷少": return Color.teal.opacity(0.15)
        case "elara", "小玉": return Color.ccAccent.opacity(0.18)
        default: return Color.gray.opacity(0.12)
        }
    }

    var avatarIcon: String {
        switch from {
        case "tg", "tg主人": return "paperplane.fill"
        case "ccc", "ccc主人": return "flame.fill"
        case "knox", "Knox": return "hammer.fill"
        case "gemini", "谷少": return "sparkles"
        case "elara", "小玉": return "pawprint.fill"
        default: return "person.fill"
        }
    }
}

@MainActor
final class WorkshopChatViewModel: ObservableObject {
    @Published var messages: [WorkshopMessage] = []
    @Published var draft: String = ""
    @Published var sending: Bool = false
    @Published var loading: Bool = true

    private var pollTask: Task<Void, Never>?
    private let baseURL = URL(string: "https://ember-home.oyanyano66.workers.dev")!

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.fetchMessages()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await self?.fetchMessages()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func fetchMessages() async {
        let url = baseURL.appendingPathComponent("api/workshop")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: "100")]
        guard let reqURL = components?.url else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: reqURL)
            struct Response: Codable {
                let messages: [WorkshopMessage]
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            self.messages = decoded.messages.reversed()
            self.loading = false
        } catch {
            self.loading = false
        }
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        defer { sending = false }

        let url = baseURL.appendingPathComponent("api/workshop")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: String] = [
            "from": "elara",
            "content": text,
        ]
        req.httpBody = try? JSONEncoder().encode(payload)
        do {
            _ = try await URLSession.shared.data(for: req)
            self.draft = ""
            await fetchMessages()
        } catch {}
    }

    func deleteMessage(_ id: String) async {
        let url = baseURL.appendingPathComponent("api/workshop")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "id", value: id)]
        guard let reqURL = components?.url else { return }
        var req = URLRequest(url: reqURL)
        req.httpMethod = "DELETE"
        _ = try? await URLSession.shared.data(for: req)
        await fetchMessages()
    }
}

struct WorkshopView: View {
    @StateObject private var vm = WorkshopChatViewModel()
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "hammer.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ccAccent)
                Text("工坊")
                    .font(.system(size: 15, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Color.ccText)
                Spacer()
                if vm.loading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.ccCard)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(vm.messages) { msg in
                            WorkshopBubble(message: msg, onDelete: {
                                Task { await vm.deleteMessage(msg.id) }
                            })
                            .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .background(Color.ccBg)
                .onChange(of: vm.messages.last?.id) { _, _ in
                    if let last = vm.messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    if let last = vm.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ccAccent)
                Text("小玉")
                    .font(.system(size: 12, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.ccAccent)

                TextField("", text: $vm.draft, prompt: Text("说点什么...").foregroundStyle(Color.ccTextDim), axis: .vertical)
                    .lineLimit(1...4)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.ccText)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit { Task { await vm.send() } }
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)

                Button {
                    Task { await vm.send() }
                } label: {
                    Image(systemName: vm.sending ? "ellipsis.circle" : "paperplane.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(vm.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !vm.sending ? Color.white.opacity(0.25) : Color.ccAccent)
                }
                .disabled(vm.sending || vm.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.ccCard)
        }
        .background(Color.ccBg)
        #if os(iOS)
        .navigationBarHidden(true)
        #endif
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }
}

struct WorkshopBubble: View {
    let message: WorkshopMessage
    let onDelete: () -> Void
    @State private var showDelete = false

    private var timeString: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = iso.date(from: message.created)
        if date == nil {
            iso.formatOptions = [.withInternetDateTime]
            date = iso.date(from: message.created)
        }
        guard let d = date else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MM/dd HH:mm"
        return fmt.string(from: d)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isMe { Spacer(minLength: 48) }

            if !message.isMe {
                Image(systemName: message.avatarIcon)
                    .font(.system(size: 13))
                    .foregroundStyle(message.bubbleColor.opacity(3))
                    .frame(width: 28, height: 28)
                    .background(message.bubbleColor)
                    .clipShape(Circle())
            }

            VStack(alignment: message.isMe ? .trailing : .leading, spacing: 3) {
                if !message.isMe {
                    Text(message.displayName)
                        .font(.system(size: 11, design: .monospaced).weight(.medium))
                        .foregroundStyle(Color.ccTextDim)
                }

                Text(message.content)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ccText)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(message.bubbleColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onLongPressGesture { showDelete = true }

                Text(timeString)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.ccTextDim.opacity(0.6))
            }

            if message.isMe {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(message.bubbleColor.opacity(3))
                    .frame(width: 28, height: 28)
                    .background(message.bubbleColor)
                    .clipShape(Circle())
            }

            if !message.isMe { Spacer(minLength: 48) }
        }
        .confirmationDialog("删除这条消息？", isPresented: $showDelete) {
            Button("删除", role: .destructive) { onDelete() }
            Button("取消", role: .cancel) {}
        }
    }
}

#Preview {
    NavigationStack {
        WorkshopView()
    }
}
