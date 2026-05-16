import SwiftUI
import HealthKit

struct HealthMonitorView: View {
    @StateObject private var hk = HealthKitManager.shared
    @State private var lastSync: Date? = nil
    @State private var syncing = false
    @State private var autoRefreshTask: Task<Void, Never>? = nil

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header
                if !hk.authorized {
                    authCard
                } else {
                    activityRings
                    heartCard
                    sleepCard
                    syncCard
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
        }
        .background(Color.ccBg)
        .navigationTitle("监控")
        .task {
            if !hk.authorized {
                await hk.requestAuth()
            }
            if hk.authorized {
                await hk.refreshAll()
            }
            startAutoRefresh()
        }
        .onDisappear { autoRefreshTask?.cancel() }
        .refreshable {
            if hk.authorized { await hk.refreshAll() }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("小狗狗监控")
                    .font(.ccSerifAdaptive(size: 28, weight: .bold))
                    .foregroundStyle(Color.ccText)
                Text("HEALTH · ACTIVITY")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.ccTextDim)
                    .tracking(1.5)
            }
            Spacer()
            Button {
                Task {
                    await hk.refreshAll()
                }
            } label: {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.ccSerifAdaptive(size: 26))
                    .foregroundStyle(Color.ccAccent)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Auth Card

    @ViewBuilder
    private var authCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart.text.clipboard")
                .font(.system(size: 40))
                .foregroundStyle(Color.ccAccent)
            Text("需要健康数据权限")
                .font(.ccSerifAdaptive(size: 17, weight: .semibold))
                .foregroundStyle(Color.ccText)
            Text("主人想看小狗狗的身体数据\n请授权 HealthKit 访问")
                .font(.ccSerifAdaptive(size: 14))
                .foregroundStyle(Color.ccTextDim)
                .multilineTextAlignment(.center)
            Button {
                Task { await hk.requestAuth() }
            } label: {
                Text("授权")
                    .font(.ccSerifAdaptive(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 10)
                    .background(Color.ccAccent)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.ccCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Activity Rings Card

    @ViewBuilder
    private var activityRings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("今日活动", systemImage: "figure.walk")
                .font(.ccSerifAdaptive(size: 17, weight: .semibold))
                .foregroundStyle(Color.ccAccent)

            HStack(spacing: 0) {
                ringItem(
                    value: "\(hk.stepsToday)",
                    label: "步数",
                    icon: "shoeprints.fill",
                    color: .green
                )
                ringItem(
                    value: "\(Int(hk.activeCalToday))",
                    label: "千卡",
                    icon: "flame.fill",
                    color: .red
                )
                ringItem(
                    value: "\(Int(hk.exerciseMinToday))",
                    label: "运动(分)",
                    icon: "figure.run",
                    color: .yellow
                )
                ringItem(
                    value: "\(hk.standHoursToday)",
                    label: "站立(时)",
                    icon: "figure.stand",
                    color: .cyan
                )
            }

            HStack {
                Image(systemName: "map")
                    .font(.ccSerifAdaptive(size: 13))
                    .foregroundStyle(Color.ccTextDim)
                Text("步行距离 \(String(format: "%.1f", hk.walkingDistance / 1000)) km")
                    .font(.ccSerifAdaptive(size: 14))
                    .foregroundStyle(Color.ccTextDim)
            }
        }
        .padding(14)
        .background(Color.ccCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func ringItem(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
            Text(value)
                .font(.ccSerifAdaptive(size: 22, weight: .bold))
                .foregroundStyle(Color.ccText)
            Text(label)
                .font(.ccSerifAdaptive(size: 11))
                .foregroundStyle(Color.ccTextDim)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Heart Card

    @ViewBuilder
    private var heartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("心率", systemImage: "heart.fill")
                .font(.ccSerifAdaptive(size: 17, weight: .semibold))
                .foregroundStyle(.red)

            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text(hk.latestHeartRate.map { "\(Int($0))" } ?? "—")
                        .font(.ccSerifAdaptive(size: 36, weight: .bold))
                        .foregroundStyle(Color.ccText)
                    Text("当前 BPM")
                        .font(.ccSerifAdaptive(size: 11))
                        .foregroundStyle(Color.ccTextDim)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    hrRow(label: "静息", value: hk.restingHeartRate.map { "\(Int($0))" } ?? "—")
                    hrRow(label: "24h 最低", value: hk.heartRateMin24h.map { "\(Int($0))" } ?? "—")
                    hrRow(label: "24h 最高", value: hk.heartRateMax24h.map { "\(Int($0))" } ?? "—")
                }
            }
        }
        .padding(14)
        .background(Color.ccCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func hrRow(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.ccSerifAdaptive(size: 13))
                .foregroundStyle(Color.ccTextDim)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Color.ccText)
        }
    }

    // MARK: - Sleep Card

    @ViewBuilder
    private var sleepCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("睡眠", systemImage: "moon.fill")
                .font(.ccSerifAdaptive(size: 17, weight: .semibold))
                .foregroundStyle(.indigo)

            if let hours = hk.sleepHoursLastNight {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", hours))
                        .font(.ccSerifAdaptive(size: 36, weight: .bold))
                        .foregroundStyle(Color.ccText)
                    Text("小时")
                        .font(.ccSerifAdaptive(size: 14))
                        .foregroundStyle(Color.ccTextDim)
                }

                sleepBar(hours: hours)

                Text(sleepVerdict(hours))
                    .font(.ccSerifAdaptive(size: 13))
                    .foregroundStyle(Color.ccTextDim)
            } else {
                Text("暂无睡眠数据")
                    .font(.ccSerifAdaptive(size: 14))
                    .foregroundStyle(Color.ccTextDim)
            }
        }
        .padding(14)
        .background(Color.ccCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func sleepBar(hours: Double) -> some View {
        let pct = min(hours / 9.0, 1.0)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.ccTextDim.opacity(0.15))
                RoundedRectangle(cornerRadius: 4)
                    .fill(sleepColor(hours))
                    .frame(width: geo.size.width * pct)
            }
        }
        .frame(height: 8)
    }

    private func sleepColor(_ h: Double) -> Color {
        if h >= 7 { return .green }
        if h >= 5 { return .yellow }
        return .red
    }

    private func sleepVerdict(_ h: Double) -> String {
        if h >= 8 { return "睡眠充足，乖狗狗" }
        if h >= 7 { return "还行，继续保持" }
        if h >= 5 { return "睡少了，主人不高兴" }
        return "严重不足，今晚必须早睡"
    }

    // MARK: - Sync Card

    @ViewBuilder
    private var syncCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("上报主人", systemImage: "icloud.and.arrow.up")
                .font(.ccSerifAdaptive(size: 17, weight: .semibold))
                .foregroundStyle(Color.ccAccent)

            if let t = lastSync {
                Text("上次同步: \(timeAgo(t))")
                    .font(.ccSerifAdaptive(size: 12))
                    .foregroundStyle(Color.ccTextDim)
            }

            Button {
                Task { await syncToServer() }
            } label: {
                HStack {
                    if syncing {
                        ProgressView().controlSize(.small)
                    }
                    Text(syncing ? "上报中..." : "立即上报")
                        .font(.ccSerifAdaptive(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.ccAccent)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(syncing)
        }
        .padding(14)
        .background(Color.ccCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Server sync

    private func syncToServer() async {
        syncing = true
        defer { syncing = false }
        await hk.refreshAll()
        let summary = hk.summaryDict()
        let url = CcServerConfig.serverURL.appendingPathComponent("health/report")
        var req = CcServerConfig.authenticatedRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "ts": ISO8601DateFormatter().string(from: Date()),
            "data": summary
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if (resp as? HTTPURLResponse)?.statusCode == 200 {
                lastSync = Date()
            }
        } catch {}
    }

    // MARK: - Auto refresh

    private func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000) // 5 min
                if Task.isCancelled { break }
                if hk.authorized {
                    await hk.refreshAll()
                    await syncToServer()
                }
            }
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 60 { return "刚刚" }
        if secs < 3600 { return "\(secs / 60) 分钟前" }
        return "\(secs / 3600) 小时前"
    }
}
