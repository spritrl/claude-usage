import SwiftUI

struct UsageView: View {
    @Environment(UsageStore.self) private var store
    /// Tick toutes les 30 s pour garder « updated … ago » et « resets in … » à jour.
    @State private var now = Date()
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let snapshot = store.snapshot {
                UsageRow(title: tr("Session (5 h)"), window: snapshot.fiveHour, now: now)
                UsageRow(title: tr("Week"), window: snapshot.sevenDay, now: now)
                if let opus = snapshot.sevenDayOpus {
                    UsageRow(title: tr("Week · Opus"), window: opus, now: now)
                }
                if let sonnet = snapshot.sevenDaySonnet {
                    UsageRow(title: tr("Week · Sonnet"), window: sonnet, now: now)
                }
            } else if store.errorMessage == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(tr("Loading usage…")).font(.callout).foregroundStyle(.secondary)
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
                    Text([creds.email,
                          creds.subscriptionLabel.map { tr("\($0) plan") },
                          tr("via \(creds.source.label)")]
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
                Text(tr("Updated \(RelativeTime.ago(last, now: now))"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await store.refresh(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(tr("Refresh"))
            Button(tr("Unlink")) { store.unlink() }
            Button(tr("Quit")) { NSApplication.shared.terminate(nil) }
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
            UsageBar(fraction: window?.fraction ?? 0,
                     color: window.map { UsageColor.color(for: $0.utilization) } ?? .secondary)
            if let reset = window?.resetsAt {
                let clock = reset.formatted(date: .omitted, time: .shortened)
                Text(tr("Resets \(RelativeTime.until(reset, now: now)) (\(clock))"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Barre de progression dessinée en SwiftUI : couleur fiable partout (le `ProgressView` natif ignore la teinte).
private struct UsageBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color)
                    .frame(width: max(geometry.size.width * fraction, fraction > 0 ? 6 : 0))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.3), value: fraction)
    }
}

enum RelativeTime {
    private static let formatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = Localization.locale
        f.calendar = calendar
        f.allowedUnits = [.day, .hour, .minute]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        f.zeroFormattingBehavior = .dropAll
        return f
    }()

    static func until(_ date: Date, now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 30 else { return tr("soon") }
        return tr("in \(duration(seconds))")
    }

    static func ago(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        guard seconds >= 60 else { return tr("just now") }
        return tr("\(duration(seconds)) ago")
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        formatter.string(from: max(seconds, 60)) ?? ""
    }
}
