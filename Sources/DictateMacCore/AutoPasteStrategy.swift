public enum AutoPasteStep: Equatable, Sendable {
    case pasteShortcut
    case accessibilityFallback
}

public enum AutoPasteStrategy {
    public static func steps(for mode: TranscriptDeliveryMode) -> [AutoPasteStep] {
        switch mode {
        case .automaticInsert:
            [.pasteShortcut, .accessibilityFallback]
        case .clipboardOnly:
            []
        }
    }
}
