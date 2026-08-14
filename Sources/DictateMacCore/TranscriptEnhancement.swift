import Foundation

public struct BrainEvidenceItem: Codable, Equatable, Sendable {
    public let id: String
    public let type: String
    public let label: String
    public let path: String?
    public let excerpt: String
    public let url: String?

    public init(id: String, type: String, label: String, path: String?, excerpt: String, url: String?) {
        self.id = id
        self.type = type
        self.label = label
        self.path = path
        self.excerpt = excerpt
        self.url = url
    }
}

public struct TranscriptContextItem: Codable, Equatable, Sendable, Identifiable {
    public let title: String
    public let detail: String
    public let url: String?
    public let sourcePath: String

    public var id: String { [title, sourcePath].joined(separator: "|") }

    public init(title: String, detail: String, url: String?, sourcePath: String) {
        self.title = title
        self.detail = detail
        self.url = url
        self.sourcePath = sourcePath
    }
}

public struct TranscriptCorrection: Codable, Equatable, Sendable {
    public let original: String
    public let replacement: String
    public let confidence: Double

    public init(original: String, replacement: String, confidence: Double) {
        self.original = original
        self.replacement = replacement
        self.confidence = confidence
    }
}

public struct TranscriptEnhancement: Codable, Equatable, Sendable {
    public let correctedTranscript: String
    public let corrections: [TranscriptCorrection]
    public let usefulContext: [TranscriptContextItem]

    public init(
        correctedTranscript: String,
        corrections: [TranscriptCorrection] = [],
        usefulContext: [TranscriptContextItem]
    ) {
        self.correctedTranscript = correctedTranscript
        self.corrections = corrections
        self.usefulContext = usefulContext
    }
}

public enum TranscriptEnhancementContract {
    public static func validate(
        _ candidate: TranscriptEnhancement,
        rawTranscript: String,
        evidence: [BrainEvidenceItem]
    ) -> TranscriptEnhancement? {
        let raw = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let corrected = candidate.correctedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !corrected.isEmpty else { return nil }
        guard corrected.count >= max(1, raw.count * 3 / 4), corrected.count <= max(32, raw.count * 5 / 4) else { return nil }

        let rawWords = words(raw)
        let correctedWords = words(corrected)
        guard !rawWords.isEmpty else { return nil }
        let editCount = editDistance(rawWords, correctedWords)
        let allowedEdits = max(2, Int(ceil(Double(rawWords.count) * 0.15)))
        guard editCount <= allowedEdits else { return nil }
        if editCount > 0 {
            guard !candidate.corrections.isEmpty,
                  candidate.corrections.count <= allowedEdits,
                  candidate.corrections.allSatisfy({ $0.confidence >= 0.90 && $0.confidence <= 1.0 }),
                  candidate.corrections.allSatisfy({ correction in
                      contains(correction.original, in: rawWords)
                          && contains(correction.replacement, in: correctedWords)
                  }),
                  candidate.corrections.allSatisfy({ isGrounded($0, in: evidence) }) else { return nil }
        }

        let paths = Set(evidence.compactMap(\.path))
        let urls = Set(evidence.compactMap(\.url))
        let grounded = candidate.usefulContext.filter { item in
            paths.contains(item.sourcePath) && (item.url == nil || urls.contains(item.url!))
        }.prefix(3)

        return TranscriptEnhancement(
            correctedTranscript: corrected,
            corrections: candidate.corrections,
            usefulContext: Array(grounded)
        )
    }

    private static func words(_ value: String) -> [String] {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    private static func contains(_ value: String, in words: [String]) -> Bool {
        let needle = self.words(value)
        guard !needle.isEmpty, needle.count <= words.count else { return false }
        return words.indices.contains { start in
            let end = start + needle.count
            return end <= words.count && Array(words[start..<end]) == needle
        }
    }

    private static func isGrounded(_ correction: TranscriptCorrection, in evidence: [BrainEvidenceItem]) -> Bool {
        if words(correction.original) == words(correction.replacement) { return true }
        return evidence.contains { item in
            let source = [item.label, item.excerpt, item.path ?? "", item.url ?? ""]
                .joined(separator: " ")
            return contains(correction.replacement, in: words(source))
        }
    }

    private static func editDistance(_ left: [String], _ right: [String]) -> Int {
        var previous = Array(0...right.count)
        for (leftIndex, leftWord) in left.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, rightWord) in right.enumerated() {
                current.append(min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + (leftWord == rightWord ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous[right.count]
    }
}
