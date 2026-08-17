import Foundation

public struct TranscriptionHUDLayoutResult: Equatable, Sendable {
    public let panelHeight: CGFloat
    public let textViewportHeight: CGFloat
    public let textOverflows: Bool
}

public enum TranscriptionHUDLayout {
    public static let verticalPadding: CGFloat = 48
    public static let headerHeight: CGFloat = 88
    public static let footerHeight: CGFloat = 52
    public static let sectionSpacing: CGFloat = 16
    public static let minimumHeight: CGFloat = 128
    public static let screenMargin: CGFloat = 36

    public static func make(
        textHeight: CGFloat,
        hasHeader: Bool,
        hasFooter: Bool = false,
        screenHeight: CGFloat
    ) -> TranscriptionHUDLayoutResult {
        var reserved = CGFloat.zero
        if hasHeader { reserved += headerHeight }
        if hasFooter { reserved += footerHeight }
        let sections = [hasHeader, textHeight > 0, hasFooter].filter(\.self).count
        if sections > 1 { reserved += sectionSpacing * CGFloat(sections - 1) }
        let naturalHeight = verticalPadding + reserved + max(0, textHeight)
        let maximumHeight = max(minimumHeight, screenHeight - screenMargin)
        let panelHeight = min(max(minimumHeight, naturalHeight), maximumHeight)
        let textViewportHeight = max(0, panelHeight - verticalPadding - reserved)
        return TranscriptionHUDLayoutResult(
            panelHeight: panelHeight,
            textViewportHeight: textViewportHeight,
            textOverflows: textHeight > textViewportHeight + 0.5
        )
    }
}
