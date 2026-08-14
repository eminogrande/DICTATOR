import Foundation

public struct TranscriptionHUDLayoutResult: Equatable, Sendable {
    public let panelHeight: CGFloat
    public let textViewportHeight: CGFloat
    public let textOverflows: Bool
}

public enum TranscriptionHUDLayout {
    public static let verticalPadding: CGFloat = 48
    public static let headerHeight: CGFloat = 88
    public static let sectionSpacing: CGFloat = 16
    public static let minimumHeight: CGFloat = 128
    public static let screenMargin: CGFloat = 36

    public static func make(
        textHeight: CGFloat,
        hasHeader: Bool,
        screenHeight: CGFloat
    ) -> TranscriptionHUDLayoutResult {
        let headerAndSpacing = hasHeader
            ? headerHeight + (textHeight > 0 ? sectionSpacing : 0)
            : 0
        let naturalHeight = verticalPadding + headerAndSpacing + max(0, textHeight)
        let maximumHeight = max(minimumHeight, screenHeight - screenMargin)
        let panelHeight = min(max(minimumHeight, naturalHeight), maximumHeight)
        let textViewportHeight = max(
            0,
            panelHeight - verticalPadding - headerAndSpacing
        )
        return TranscriptionHUDLayoutResult(
            panelHeight: panelHeight,
            textViewportHeight: textViewportHeight,
            textOverflows: textHeight > textViewportHeight + 0.5
        )
    }
}
