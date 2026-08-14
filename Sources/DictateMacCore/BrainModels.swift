import Foundation

public struct BrainRelatedItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let type: String
    public let label: String
    public let path: String?
}

public struct BrainSearchItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let type: String
    public let label: String
    public let path: String?
    public let score: Int
    public let excerpt: String
    public let related: [BrainRelatedItem]
}

public struct BrainSearchResponse: Codable, Equatable, Sendable {
    public let query: String
    public let results: [BrainSearchItem]
}

public struct BrainStats: Codable, Equatable, Sendable {
    public let graphPath: String
    public let nodes: Int
    public let edges: Int
    public let nodeTypes: [String: Int]
    public let repository: String?
    public let language: String?
    public let files: Int?
    public let functions: Int?
}

public enum TranscriptionProgressFrames {
    public static func make(from previousTranscript: String) -> [String] {
        let words = previousTranscript.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return [".", "..", "...", "....", "....."] }
        let excerpt = Array(words.suffix(10))
        var frames = [".", "..", "..."]
        for count in 1...excerpt.count {
            frames.append("“" + excerpt.prefix(count).joined(separator: " ") + "”")
        }
        if excerpt.count > 3 {
            for count in stride(from: excerpt.count - 1, through: max(2, excerpt.count / 2), by: -1) {
                frames.append("“" + excerpt.prefix(count).joined(separator: " ") + "”")
            }
        }
        frames.append("...")
        return frames
    }
}
