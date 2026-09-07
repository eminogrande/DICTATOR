import AppKit

@MainActor
enum DictatorAssets {
    static func menuTitle(phase: String, activityTitle: String) -> String {
        switch phase {
        case "recording", "transcribing", "saving", "starting": return "DICTATOR  \(activityTitle)"
        default: return "DICTATOR"
        }
    }

    static func applyMenuBranding(to button: NSButton, phase: String, activityTitle: String) {
        // Plain native title: AppKit chooses contrast for the menu-bar material.
        // App-level labelColor/black and tinted attributed strings can be wrong here.
        button.title = menuTitle(phase: phase, activityTitle: activityTitle)
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        button.contentTintColor = nil
        button.imagePosition = .imageLeading
        button.image = icons[phase] ?? icons["idle"]
    }

    private static let icons: [String: NSImage] = {
        let symbols: [(String, String, NSColor?)] = [
            ("idle", "waveform", nil),
            ("recording", "record.circle.fill", .systemRed),
            ("starting", "record.circle", .systemRed),
            ("transcribing", "text.bubble.fill", .systemOrange),
            ("saving", "arrow.down.circle.fill", .systemOrange),
            ("saved", "tray.full.fill", .systemOrange),
            ("completed", "checkmark.circle.fill", .systemGreen),
            ("failed", "exclamationmark.triangle.fill", .systemOrange)
        ]
        var result: [String: NSImage] = [:]
        for (phase, symbol, color) in symbols {
            guard var image = NSImage(systemSymbolName: symbol, accessibilityDescription: phase) else { continue }
            if let color {
                image = image.withSymbolConfiguration(.init(paletteColors: [color])) ?? image
                image.isTemplate = false
            } else {
                image.isTemplate = true
            }
            image.size = NSSize(width: 14, height: 14)
            result[phase] = image
        }
        return result
    }()
}
