public enum TranscriptInsertionAction: Equatable {
    case inserted
    case usePasteShortcut
}

public enum TranscriptInsertionDecision {
    public static func afterAccessibilityResult(_ errorCode: Int32) -> TranscriptInsertionAction {
        errorCode == 0 ? .inserted : .usePasteShortcut
    }
}
