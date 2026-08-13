import Foundation

public enum TranscriptCleaner {
    public static func clean(_ transcript: String) -> String {
        transcript
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
