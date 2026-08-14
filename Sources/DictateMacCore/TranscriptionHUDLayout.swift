import Foundation

public enum TranscriptionHUDLayout {
    public static func height(
        textHeight: CGFloat,
        hasAudio: Bool,
        hasTitle: Bool,
        screenHeight: CGFloat
    ) -> CGFloat {
        var blocks: [CGFloat] = []
        if hasAudio { blocks.append(70) }
        if hasTitle { blocks.append(21) }
        if textHeight > 0 { blocks.append(textHeight) }
        let naturalHeight = 48 + blocks.reduce(0, +) + CGFloat(max(0, blocks.count - 1)) * 18
        return min(max(128, naturalHeight), max(128, screenHeight - 36))
    }
}
