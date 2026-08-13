public enum TranscriptDeliveryMode: Equatable, Sendable {
    case automaticInsert
    case clipboardOnly
}

public enum AutoPastePolicy {
    public static func deliveryMode(isEnabled: Bool) -> TranscriptDeliveryMode {
        isEnabled ? .automaticInsert : .clipboardOnly
    }
}
