import SwiftUI

struct UsageView: View {
    @Environment(UsageStore.self) private var store
    /// Tick chaque 30 s pour garder « il y a X min » et « dans X h » à jour.
    @State private var now = Date()
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let snapshot = store.snapshot {
                UsageRow(title: "Session (5 h)", window: snapshot.fiveHour, now: now)
                UsageRow(title: "Semaine", window: snapshot.sevenDay, now: now)
                if let opus = snapshot.sevenDayOpus {
                    UsageRow(title: "Semaine · Opus", window: opus, now: now)
                }
                if let sonnet = snapshot.sevenDaySonnet {
                    UsageRow(title: "Semaine · Sonnet", window: sonnet, now: now)
                }
            } else if store.errorMessage == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Chargement de l'usage…").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }

            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            footer
        }
        .padding(14)
        .onReceive(clock) { now = $0 }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Usage").font(.headline)
                if let creds = store.credentials {
                    Text([creds.email, creds.subscriptionLabel.map { "Abonnement \($0)" }, "via \(creds.source.label)"]
                        .compactMap { $0 }
                        .joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let last = store.lastRefresh {
                Text("Mis à jour \(RelativeTime.ago(last, now: now))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await store.refresh(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Rafraîchir")
            Button("Délier") { store.unlink() }
            Button("Quitter") { NSApplication.shared.terminate(nil) }
        }
        .controlSize(.small)
    }
}

private struct UsageRow: View {
    let title: String
    let window: UsageWindow?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text(window?.percentText ?? "–")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(window.map { UsageColor.color(for: $0.utilization) } ?? .secondary)
            }
            ProgressView(value: window?.fraction ?? 0)
                .tint(window.map { UsageColor.color(for: $0.utilization) } ?? .secondary)
            if let reset = window?.resetsAt {
                Text("Réinitialisation \(RelativeTime.until(reset, now: now)) (\(reset.formatted(date: .omitted, time: .shortened)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

enum RelativeTime {
    static func until(_ date: Date, now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 30 else { return "imminente" }
        return "dans \(duration(seconds))"
    }

    static func ago(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        guard seconds >= 60 else { return "à l'instant" }
        return "il y a \(duration(seconds))"
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let mins = minutes % 60
        if days > 0 { return hours > 0 ? "\(days) j \(hours) h" : "\(days) j" }
        if hours > 0 { return mins > 0 ? "\(hours) h \(String(format: "%02d", mins))" : "\(hours) h" }
        return "\(max(mins, 1)) min"
    }
}
