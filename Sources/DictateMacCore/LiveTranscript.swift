import Foundation

public struct LiveTranscriptSnapshot: Equatable, Sendable {
    public let confirmed: String
    public let provisional: String

    public init(confirmed: String, provisional: String) {
        self.confirmed = confirmed
        self.provisional = provisional
    }
}

public enum LiveTranscriptText {
    public static func make(
        confirmedSegments: [String],
        unconfirmedSegments: [String],
        currentText: String
    ) -> LiveTranscriptSnapshot {
        let confirmed = join(confirmedSegments)
        let current = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let provisional: String
        if current.isEmpty || current == "Waiting for speech..." {
            provisional = join(unconfirmedSegments)
        } else {
            provisional = removingConfirmedPrefix(confirmed, from: current)
        }
        return LiveTranscriptSnapshot(confirmed: confirmed, provisional: provisional)
    }

    public static func deliveryTranscript(confirmed: String, provisional: String) -> String {
        TranscriptCleaner.clean([confirmed, provisional].joined(separator: " "))
    }

    private static func join(_ values: [String]) -> String {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func removingConfirmedPrefix(_ confirmed: String, from current: String) -> String {
        guard !confirmed.isEmpty,
              current.lowercased().hasPrefix(confirmed.lowercased()),
              let end = current.index(current.startIndex, offsetBy: confirmed.count, limitedBy: current.endIndex) else {
            return current
        }
        return current[end...].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
