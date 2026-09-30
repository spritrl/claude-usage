import AppKit
import SwiftUI

/// Rend les vraies vues de l'app en PNG (clair et sombre, 2x) pour le README.
/// Lancement : `ClaudeUsage --screenshots <dossier>` (voir `make screenshots`). Données d'exemple, pas de réseau.
enum Screenshots {
    @MainActor
    static func render(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = UsageStore.sample()

        for (suffix, appearance, scheme) in [("light", NSAppearance.Name.aqua, ColorScheme.light),
                                             ("dark", NSAppearance.Name.darkAqua, ColorScheme.dark)] {
            let popup = PopoverView()
                .environment(store)
                .environment(\.colorScheme, scheme)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.22), radius: 10, y: 3)
                .padding(20)
            try snapshot(popup, appearance: appearance, transparent: true)
                .write(to: directory.appendingPathComponent("popup-\(suffix).png"))

            let bar = MenuBarStrip()
                .environment(store)
                .environment(\.colorScheme, scheme)
            try snapshot(bar, appearance: appearance, transparent: false)
                .write(to: directory.appendingPathComponent("menubar-\(suffix).png"))
        }
    }

    /// Dessine une vue SwiftUI dans une fenêtre hors écran et renvoie un PNG à 2x.
    @MainActor
    private static func snapshot<V: View>(_ view: V, appearance: NSAppearance.Name, transparent: Bool) throws -> Data {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: appearance)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.isOpaque = !transparent
        window.backgroundColor = transparent ? .clear : .windowBackgroundColor
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        defer { window.orderOut(nil) }

        let scale = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw CocoaError(.fileWriteUnknown) }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        return png
    }
}

/// Imitation d'un coin de barre de menus autour du vrai `MenuBarLabel`.
private struct MenuBarStrip: View {
    var body: some View {
        HStack(spacing: 18) {
            MenuBarLabel()
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text("Tue 30 Sep  14:32")
        }
        .font(.system(size: 13))
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(.regularMaterial)
    }
}

extension UsageStore {
    /// Store figé avec des données d'exemple, pour les captures et les previews.
    @MainActor
    static func sample() -> UsageStore {
        let store = UsageStore()
        store.credentials = OAuthCredentials(
            accessToken: "sample", refreshToken: nil, expiresAt: nil, scopes: [],
            subscriptionType: "max", email: nil, source: .claudeCode
        )
        let now = Date()
        store.snapshot = UsageSnapshot(
            fiveHour: UsageWindow(utilization: 42, resetsAt: now.addingTimeInterval(2 * 3600 + 14 * 60)),
            sevenDay: UsageWindow(utilization: 18, resetsAt: now.addingTimeInterval(3 * 86400 + 5 * 3600)),
            sevenDayOpus: nil, sevenDaySonnet: nil,
            fetchedAt: now
        )
        store.lastRefresh = now.addingTimeInterval(-120)
        store.phase = .linked
        return store
    }
}
