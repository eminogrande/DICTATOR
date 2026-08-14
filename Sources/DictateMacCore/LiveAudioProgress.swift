import Foundation

public struct LiveAudioProgress: Equatable, Sendable {
    public let waveform: [Float]
    public let audioDuration: TimeInterval
    public let transcribedPosition: TimeInterval

    public init(
        waveform: [Float],
        audioDuration: TimeInterval,
        transcribedPosition: TimeInterval
    ) {
        self.waveform = waveform
        self.audioDuration = max(0, audioDuration)
        self.transcribedPosition = min(max(0, transcribedPosition), max(0, audioDuration))
    }

    public var fractionTranscribed: Double {
        guard audioDuration > 0 else { return 0 }
        return transcribedPosition / audioDuration
    }

    public var timecode: String {
        "\(Self.format(transcribedPosition)) / \(Self.format(audioDuration))"
    }

    private static func format(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded(.down)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%02d:%02d", minutes, remainder)
    }
}

public enum WaveformEnvelope {
    public static func downsample(_ values: [Float], maximumCount: Int = 240) -> [Float] {
        guard maximumCount > 0, !values.isEmpty else { return [] }
        guard values.count > maximumCount else {
            return values.map(normalize)
        }

        return (0..<maximumCount).map { index in
            let start = index * values.count / maximumCount
            let end = max(start + 1, (index + 1) * values.count / maximumCount)
            return values[start..<min(end, values.count)].map(normalize).max() ?? 0
        }
    }

    private static func normalize(_ value: Float) -> Float {
        min(1, max(0, value.isFinite ? value : 0))
    }
}
