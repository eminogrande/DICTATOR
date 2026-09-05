import Foundation

public struct TranscriptionHUDPresentation: Equatable, Sendable {
    public let title: String
    public let confirmed: String
    public let provisional: String
    public let audio: LiveAudioProgress

    public init(
        title: String,
        confirmed: String,
        provisional: String,
        audio: LiveAudioProgress = LiveAudioProgress(
            waveform: [],
            audioDuration: 0,
            transcribedPosition: 0
        )
    ) {
        self.title = title
        self.confirmed = confirmed
        self.provisional = provisional
        self.audio = audio
    }

    public var hasTranscript: Bool {
        !confirmed.isEmpty || !provisional.isEmpty
    }

    public static func make(
        isVisible: Bool,
        isRecording: Bool = false,
        title: String,
        confirmed: String,
        provisional: String,
        audio: LiveAudioProgress = LiveAudioProgress(
            waveform: [],
            audioDuration: 0,
            transcribedPosition: 0
        )
    ) -> TranscriptionHUDPresentation? {
        guard isVisible else { return nil }
        return TranscriptionHUDPresentation(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (isRecording ? "Recording — listening…" : "Loading…") : title,
            confirmed: confirmed,
            provisional: provisional,
            audio: audio
        )
    }
}
