import AppKit

enum DictatorAssets {
    static let menuIcon: NSImage = {
        let fallback = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "DICTATOR")!
        guard let url = Bundle.main.url(forResource: "DICTATOR-menu@2x", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return fallback
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()
}
