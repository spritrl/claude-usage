import AppKit
import SwiftUI

/// Couleurs partagées entre l'icône et les jauges du popup.
enum UsageColor {
    static func nsColor(for utilization: Double) -> NSColor {
        switch utilization {
        case ..<50: return .systemGreen
        case ..<80: return .systemOrange
        default: return .systemRed
        }
    }

    static func color(for utilization: Double) -> Color {
        Color(nsColor: nsColor(for: utilization))
    }
}

/// Dessine l'anneau de la barre de menus (image non-template pour conserver la couleur).
enum MenuBarIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(for state: UsageStore.IconState) -> NSImage {
        let key: String
        switch state {
        case .unlinked: key = "unlinked"
        case .error: key = "error"
        case .usage(let value): key = "u\(Int(value.rounded()))"
        }
        if let cached = cache[key] { return cached }
        let image = render(state)
        cache[key] = image
        return image
    }

    private static func render(_ state: UsageStore.IconState) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 5.5
            let lineWidth: CGFloat = 2.6

            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = lineWidth
            NSColor.labelColor.withAlphaComponent(0.22).setStroke()
            track.stroke()

            switch state {
            case .unlinked:
                let dot = NSBezierPath(ovalIn: NSRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3))
                NSColor.labelColor.withAlphaComponent(0.4).setFill()
                dot.fill()
            case .error:
                let mark = NSBezierPath()
                mark.move(to: NSPoint(x: center.x, y: center.y + 3))
                mark.line(to: NSPoint(x: center.x, y: center.y - 0.5))
                mark.lineWidth = 1.8
                mark.lineCapStyle = .round
                NSColor.systemOrange.setStroke()
                mark.stroke()
                let dot = NSBezierPath(ovalIn: NSRect(x: center.x - 0.9, y: center.y - 3.2, width: 1.8, height: 1.8))
                NSColor.systemOrange.setFill()
                dot.fill()
            case .usage(let value):
                let fraction = min(max(value / 100, 0), 1)
                guard fraction > 0 else { break }
                let arc = NSBezierPath()
                // Départ en haut (90°), sens horaire.
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
                arc.lineWidth = lineWidth
                arc.lineCapStyle = fraction >= 1 ? .butt : .round
                UsageColor.nsColor(for: value).setStroke()
                arc.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
