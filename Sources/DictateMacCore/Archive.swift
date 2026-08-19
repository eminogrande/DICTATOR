import Foundation

public enum ArchiveNaming {
    public static func folderName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss.SSS'Z'"
        return formatter.string(from: date)
    }

    public static func baseName(
        sequence: Int,
        date: Date,
        headline: String,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let slug = GraphBrainText.slug(headline).isEmpty ? "recording" : GraphBrainText.slug(headline)
        return String(format: "%06d_%@_%@", sequence, formatter.string(from: date), slug)
    }
}

public struct GraphTextAnalysis: Equatable, Sendable {
    public let headline: String
    public let summary: String
    public let keywords: [String]
}

public enum GraphBrainText {
    private static let stopWords: Set<String> = [
        "aber", "alle", "alles", "also", "auch", "auf", "aus", "bei", "bin", "bis", "das", "dass", "dem", "den", "der", "des", "die", "dies", "diese", "dieser", "doch", "ein", "eine", "einer", "eines", "es", "für", "hat", "haben", "hier", "ich", "im", "in", "ist", "mit", "nicht", "oder", "sein", "sich", "sie", "sind", "und", "von", "war", "was", "wenn", "wie", "wir", "wird", "zu", "zum", "zur",
        "about", "all", "also", "am", "an", "and", "are", "as", "at", "be", "been", "but", "by", "can", "do", "for", "from", "had", "has", "have", "he", "her", "here", "him", "his", "how", "i", "if", "in", "into", "is", "it", "its", "just", "later", "like", "make", "me", "my", "not", "of", "on", "or", "our", "she", "so", "some", "than", "that", "the", "their", "them", "then", "there", "these", "they", "this", "to", "up", "us", "very", "want", "was", "we", "were", "what", "when", "where", "which", "who", "will", "with", "would", "you", "your"
    ]

    public static func analyze(_ transcript: String) -> GraphTextAnalysis {
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = firstSentence(cleaned)
        let meaningful = meaningfulWords(cleaned)
        let headlineWords = Array(meaningfulWords(summary).prefix(8))
        let headline = headlineWords.isEmpty ? "recording" : headlineWords.joined(separator: " ")

        var counts: [String: Int] = [:]
        var firstPosition: [String: Int] = [:]
        for (index, word) in meaningful.enumerated() {
            counts[word, default: 0] += 1
            firstPosition[word] = firstPosition[word] ?? index
        }
        let keywords = counts.keys.sorted {
            let leftCount = counts[$0, default: 0]
            let rightCount = counts[$1, default: 0]
            if leftCount != rightCount { return leftCount > rightCount }
            return firstPosition[$0, default: 0] < firstPosition[$1, default: 0]
        }.prefix(10)

        return GraphTextAnalysis(headline: headline, summary: summary, keywords: Array(keywords))
    }

    public static func slug(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let parts = folded.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return parts.prefix(8).joined(separator: "-")
    }

    private static func firstSentence(_ text: String) -> String {
        guard !text.isEmpty else { return "No speech recognized." }
        if let boundary = text.firstIndex(where: { ".!?".contains($0) }) {
            return String(text[...boundary]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let words = text.split(whereSeparator: { $0.isWhitespace })
        let shortened = words.prefix(24).joined(separator: " ")
        return shortened + (words.count > 24 ? "…" : "")
    }

    private static func meaningfulWords(_ text: String) -> [String] {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var seen: Set<String> = []
        var result: [String] = []
        for raw in folded.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted) {
            guard raw.count >= 3, !stopWords.contains(raw), !seen.contains(raw) else { continue }
            seen.insert(raw)
            result.append(raw)
        }
        return result
    }
}

public enum DictationStatus: String, Codable, Sendable {
    case recording
    case transcribing
    case completed
    case failed
}

public enum TranscriptDelivery: String, Codable, Sendable {
    case accessibilityInserted
    case pasteShortcutPosted
    case accessibilityDenied
    case targetUnavailable
    case clipboardOnly

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        if value == "copied" {
            self = .clipboardOnly
        } else if let delivery = Self(rawValue: value) {
            self = delivery
        } else {
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Unknown transcript delivery: \(value)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct DictationMetadata: Codable, Equatable, Sendable {
    public var sessionID: String
    public var sequence: Int?
    public var startedAt: Date
    public var completedAt: Date?
    public var model: String
    public var sourceApplication: String?
    public var audioFilename: String
    public var transcriptFilename: String
    public var metadataFilename: String?
    public var headline: String?
    public var summary: String?
    public var keywords: [String]?
    public var status: DictationStatus
    public var delivery: TranscriptDelivery?
    public var autoPasteEnabled: Bool?
    public var meetingCaptureEnabled: Bool?
    public var systemAudioCaptured: Bool?
    public var rawTranscriptFilename: String?
    public var enhancementModel: String?
    public var enhancementEvidencePaths: [String]?
    public var usefulContext: [TranscriptContextItem]?
    public var enhancementError: String?
    public var error: String?

    public init(
        sessionID: String,
        sequence: Int? = nil,
        startedAt: Date,
        completedAt: Date?,
        model: String,
        sourceApplication: String?,
        audioFilename: String,
        transcriptFilename: String,
        metadataFilename: String? = nil,
        headline: String? = nil,
        summary: String? = nil,
        keywords: [String]? = nil,
        status: DictationStatus,
        delivery: TranscriptDelivery?,
        autoPasteEnabled: Bool? = nil,
        meetingCaptureEnabled: Bool? = nil,
        systemAudioCaptured: Bool? = nil,
        rawTranscriptFilename: String? = nil,
        enhancementModel: String? = nil,
        enhancementEvidencePaths: [String]? = nil,
        usefulContext: [TranscriptContextItem]? = nil,
        enhancementError: String? = nil,
        error: String?
    ) {
        self.sessionID = sessionID
        self.sequence = sequence
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.model = model
        self.sourceApplication = sourceApplication
        self.audioFilename = audioFilename
        self.transcriptFilename = transcriptFilename
        self.metadataFilename = metadataFilename
        self.headline = headline
        self.summary = summary
        self.keywords = keywords
        self.status = status
        self.delivery = delivery
        self.autoPasteEnabled = autoPasteEnabled
        self.meetingCaptureEnabled = meetingCaptureEnabled
        self.systemAudioCaptured = systemAudioCaptured
        self.rawTranscriptFilename = rawTranscriptFilename
        self.enhancementModel = enhancementModel
        self.enhancementEvidencePaths = enhancementEvidencePaths
        self.usefulContext = usefulContext
        self.enhancementError = enhancementError
        self.error = error
    }
}

public enum MetadataCodec {
    public static func encode(_ metadata: DictationMetadata) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(timestamp(from: date))
        }
        return try encoder.encode(metadata)
    }

    public static func decode(_ data: Data) throws -> DictationMetadata {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let date = date(from: value) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid ISO-8601 date"))
            }
            return date
        }
        return try decoder.decode(DictationMetadata.self, from: data)
    }

    public static func timestamp(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func date(from timestamp: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestamp)
    }
}

public struct GraphNode: Codable, Equatable, Sendable {
    public var id: String
    public var sequence: Int
    public var timestamp: String
    public var headline: String
    public var summary: String
    public var keywords: [String]
    public var audioFile: String
    public var transcriptFile: String
    public var metadataFile: String
    public var sourceApplication: String?
    public var related: [String]

    public init(id: String, sequence: Int, timestamp: String, headline: String, summary: String, keywords: [String], audioFile: String, transcriptFile: String, metadataFile: String, sourceApplication: String?, related: [String]) {
        self.id = id
        self.sequence = sequence
        self.timestamp = timestamp
        self.headline = headline
        self.summary = summary
        self.keywords = keywords
        self.audioFile = audioFile
        self.transcriptFile = transcriptFile
        self.metadataFile = metadataFile
        self.sourceApplication = sourceApplication
        self.related = related
    }
}

public struct GraphDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var updatedAt: String
    public var nodes: [GraphNode]
    public var keywordIndex: [String: [String]]
}

public enum GraphBrain {
    public static func connect(_ nodes: [GraphNode]) -> [GraphNode] {
        nodes.map { node in
            var copy = node
            let own = Set(node.keywords)
            copy.related = nodes.filter { candidate in
                candidate.id != node.id && !own.isDisjoint(with: candidate.keywords)
            }.sorted { $0.sequence > $1.sequence }.prefix(12).map(\.id)
            return copy
        }
    }

    public static func document(nodes: [GraphNode], updatedAt: Date = Date()) -> GraphDocument {
        let connected = connect(nodes.sorted { $0.sequence < $1.sequence })
        var index: [String: [String]] = [:]
        for node in connected {
            for keyword in node.keywords { index[keyword, default: []].append(node.id) }
        }
        return GraphDocument(version: 1, updatedAt: MetadataCodec.timestamp(from: updatedAt), nodes: connected, keywordIndex: index)
    }
}

public struct DictationSession: Sendable {
    public let folderURL: URL
    public var audioURL: URL
    public var transcriptURL: URL
    public var metadataURL: URL
    public var metadata: DictationMetadata

    public init(folderURL: URL, audioURL: URL, transcriptURL: URL, metadataURL: URL, metadata: DictationMetadata) {
        self.folderURL = folderURL
        self.audioURL = audioURL
        self.transcriptURL = transcriptURL
        self.metadataURL = metadataURL
        self.metadata = metadata
    }
}

public struct ArchiveStore: Sendable {
    public static let modelName = "large-v3_turbo"
    public let rootURL: URL

    public init(rootURL: URL? = nil) throws {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            self.rootURL = support.appendingPathComponent("DictateMac", isDirectory: true).appendingPathComponent("Dictations", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
        try migrateLegacyFolders()
        try rebuildGraph()
    }

    public func startSession(at date: Date = Date(), sourceApplication: String?) throws -> DictationSession {
        let sequence = try nextSequence()
        let base = ArchiveNaming.baseName(sequence: sequence, date: date, headline: "recording")
        let audioURL = rootURL.appendingPathComponent(base + ".wav")
        let transcriptURL = rootURL.appendingPathComponent(base + ".txt")
        let metadataURL = rootURL.appendingPathComponent(base + ".json")
        let metadata = DictationMetadata(
            sessionID: base,
            sequence: sequence,
            startedAt: date,
            completedAt: nil,
            model: Self.modelName,
            sourceApplication: sourceApplication,
            audioFilename: audioURL.lastPathComponent,
            transcriptFilename: transcriptURL.lastPathComponent,
            metadataFilename: metadataURL.lastPathComponent,
            headline: "recording",
            summary: nil,
            keywords: [],
            status: .recording,
            delivery: nil,
            error: nil
        )
        try Data().write(to: transcriptURL, options: .atomic)
        try write(metadata, to: metadataURL)
        return DictationSession(folderURL: rootURL, audioURL: audioURL, transcriptURL: transcriptURL, metadataURL: metadataURL, metadata: metadata)
    }

    public func nameAndWriteTranscript(
        _ transcript: String,
        rawTranscript: String? = nil,
        for original: DictationSession
    ) throws -> DictationSession {
        var session = original
        let analysis = GraphBrainText.analyze(transcript)
        let sequence: Int
        if let existingSequence = session.metadata.sequence {
            sequence = existingSequence
        } else {
            sequence = try nextSequence()
        }
        let base = ArchiveNaming.baseName(sequence: sequence, date: session.metadata.startedAt, headline: analysis.headline)
        let audioURL = rootURL.appendingPathComponent(base + ".wav")
        let transcriptURL = rootURL.appendingPathComponent(base + ".txt")
        let rawTranscriptURL = rootURL.appendingPathComponent(base + ".raw.txt")
        let metadataURL = rootURL.appendingPathComponent(base + ".json")

        try Data(transcript.utf8).write(to: session.transcriptURL, options: .atomic)
        try moveVerified(from: session.audioURL, to: audioURL)
        try moveVerified(from: session.transcriptURL, to: transcriptURL)
        try moveVerified(from: session.metadataURL, to: metadataURL)

        session.audioURL = audioURL
        session.transcriptURL = transcriptURL
        session.metadataURL = metadataURL
        session.metadata.sessionID = base
        session.metadata.sequence = sequence
        session.metadata.audioFilename = audioURL.lastPathComponent
        session.metadata.transcriptFilename = transcriptURL.lastPathComponent
        if let rawTranscript {
            try Data(rawTranscript.utf8).write(to: rawTranscriptURL, options: .atomic)
            session.metadata.rawTranscriptFilename = rawTranscriptURL.lastPathComponent
        } else {
            session.metadata.rawTranscriptFilename = nil
        }
        session.metadata.metadataFilename = metadataURL.lastPathComponent
        session.metadata.headline = analysis.headline
        session.metadata.summary = analysis.summary
        session.metadata.keywords = analysis.keywords
        try write(session.metadata, to: metadataURL)
        return session
    }

    public func writeTranscript(_ transcript: String, for session: DictationSession) throws {
        try Data(transcript.utf8).write(to: session.transcriptURL, options: .atomic)
    }

    /// Latest completed takes with their transcript text, newest first — for the menu bar list.
    public func recentTranscripts(limit: Int = 5) -> [(id: String, headline: String, text: String, date: Date)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)) ?? []
        let metadataFiles = files.filter { $0.pathExtension == "json" && $0.lastPathComponent != "graph.json" }
        var sessions: [(date: Date, id: String, headline: String, textURL: URL)] = []
        for file in metadataFiles {
            guard let metadata = try? MetadataCodec.decode(Data(contentsOf: file)),
                  metadata.status == .completed,
                  let headline = metadata.headline else { continue }
            sessions.append((
                date: metadata.startedAt,
                id: file.deletingPathExtension().lastPathComponent,
                headline: headline,
                textURL: rootURL.appendingPathComponent(metadata.transcriptFilename)
            ))
        }
        return sessions
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .compactMap { entry in
                guard let text = try? String(contentsOf: entry.textURL, encoding: .utf8), !text.isEmpty else { return nil }
                return (id: entry.id, headline: entry.headline, text: text, date: entry.date)
            }
    }

    public func writeMetadata(for session: DictationSession) throws {
        try write(session.metadata, to: session.metadataURL)
    }

    public func complete(_ session: DictationSession) throws {
        try writeMetadata(for: session)
        try rebuildGraph()
    }

    public func rebuildGraph() throws {
        let files = try FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
        var nodes: [GraphNode] = []
        for file in files where file.pathExtension == "json" && file.lastPathComponent != "graph.json" {
            guard let metadata = try? MetadataCodec.decode(Data(contentsOf: file)),
                  metadata.status == .completed,
                  let sequence = metadata.sequence,
                  let headline = metadata.headline,
                  let summary = metadata.summary else { continue }
            nodes.append(GraphNode(
                id: metadata.sessionID,
                sequence: sequence,
                timestamp: MetadataCodec.timestamp(from: metadata.startedAt),
                headline: headline,
                summary: summary,
                keywords: metadata.keywords ?? [],
                audioFile: metadata.audioFilename,
                transcriptFile: metadata.transcriptFilename,
                metadataFile: metadata.metadataFilename ?? file.lastPathComponent,
                sourceApplication: metadata.sourceApplication,
                related: []
            ))
        }
        let document = GraphBrain.document(nodes: nodes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(document).write(to: rootURL.appendingPathComponent("graph.json"), options: .atomic)
        try indexMarkdown(document).write(to: rootURL.appendingPathComponent("INDEX.md"), atomically: true, encoding: .utf8)
    }

    private func nextSequence() throws -> Int {
        let files = try FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
        let maximum = files.compactMap { file -> Int? in
            let prefix = file.lastPathComponent.prefix(while: { $0.isNumber })
            return prefix.count == 6 ? Int(prefix) : nil
        }.max() ?? 0
        return maximum + 1
    }

    private func migrateLegacyFolders() throws {
        let manager = FileManager.default
        let children = try manager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey])
        let folders = children.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !folders.isEmpty else { return }
        var sequence = try nextSequence()
        for folder in folders {
            let oldMetadataURL = folder.appendingPathComponent("metadata.json")
            guard var metadata = try? MetadataCodec.decode(Data(contentsOf: oldMetadataURL)) else { continue }
            let oldTranscriptURL = folder.appendingPathComponent(metadata.transcriptFilename)
            let oldAudioURL = folder.appendingPathComponent(metadata.audioFilename)
            guard manager.fileExists(atPath: oldAudioURL.path), manager.fileExists(atPath: oldTranscriptURL.path) else { continue }
            let transcript = (try? String(contentsOf: oldTranscriptURL, encoding: .utf8)) ?? ""
            let analysis = GraphBrainText.analyze(transcript)
            let base = ArchiveNaming.baseName(sequence: sequence, date: metadata.startedAt, headline: analysis.headline)
            let newAudioURL = rootURL.appendingPathComponent(base + ".wav")
            let newTranscriptURL = rootURL.appendingPathComponent(base + ".txt")
            let newMetadataURL = rootURL.appendingPathComponent(base + ".json")

            try copyVerified(from: oldAudioURL, to: newAudioURL)
            try copyVerified(from: oldTranscriptURL, to: newTranscriptURL)
            metadata.sessionID = base
            metadata.sequence = sequence
            metadata.audioFilename = newAudioURL.lastPathComponent
            metadata.transcriptFilename = newTranscriptURL.lastPathComponent
            metadata.metadataFilename = newMetadataURL.lastPathComponent
            metadata.headline = analysis.headline
            metadata.summary = analysis.summary
            metadata.keywords = analysis.keywords
            try write(metadata, to: newMetadataURL)
            guard try Data(contentsOf: newMetadataURL) == MetadataCodec.encode(metadata) else { throw ArchiveError.verificationFailed }
            try manager.removeItem(at: folder)
            sequence += 1
        }
    }

    private func copyVerified(from source: URL, to destination: URL) throws {
        let manager = FileManager.default
        if !manager.fileExists(atPath: destination.path) { try manager.copyItem(at: source, to: destination) }
        guard try Data(contentsOf: source) == Data(contentsOf: destination) else { throw ArchiveError.verificationFailed }
    }

    private func moveVerified(from source: URL, to destination: URL) throws {
        guard source != destination else { return }
        let data = try Data(contentsOf: source)
        try data.write(to: destination, options: .atomic)
        guard try Data(contentsOf: destination) == data else { throw ArchiveError.verificationFailed }
        try FileManager.default.removeItem(at: source)
    }

    private func write(_ metadata: DictationMetadata, to url: URL) throws {
        try MetadataCodec.encode(metadata).write(to: url, options: .atomic)
    }

    private func indexMarkdown(_ document: GraphDocument) -> String {
        var lines = ["# DICTATOR Graph Brain", "", "Search `graph.json` for structured nodes, keywords, and related recordings.", "", "## Timeline", ""]
        for node in document.nodes.sorted(by: { $0.sequence > $1.sequence }) {
            lines.append("### \(String(format: "%06d", node.sequence)) — \(node.headline)")
            lines.append("")
            lines.append("- Time: \(node.timestamp)")
            lines.append("- Summary: \(node.summary)")
            lines.append("- Keywords: \(node.keywords.joined(separator: ", "))")
            lines.append("- Files: [audio](\(node.audioFile)) · [transcript](\(node.transcriptFile)) · [metadata](\(node.metadataFile))")
            if !node.related.isEmpty { lines.append("- Related: \(node.related.joined(separator: ", "))") }
            lines.append("")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

private enum ArchiveError: Error {
    case verificationFailed
}
