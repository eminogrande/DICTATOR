public struct TranscriptionHUDPresentation: Equatable, Sendable {
    public let title: String
    public let detail: String

    public init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    public static func make(
        isTranscribing: Bool,
        preview: String
    ) -> TranscriptionHUDPresentation? {
        guard isTranscribing else { return nil }
        return TranscriptionHUDPresentation(
            title: "Transcribing locally",
            detail: preview.isEmpty ? "..." : preview
        )
    }
}
