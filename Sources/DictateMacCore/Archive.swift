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
}

public struct DictationMetadata: Codable, Equatable, Sendable {
    public var sessionID: String
    public var startedAt: Date
    public var completedAt: Date?
    public var model: String
    public var sourceApplication: String?
    public var audioFilename: String
    public var transcriptFilename: String
    public var status: DictationStatus
    public var delivery: TranscriptDelivery?
    public var error: String?

    public init(
        sessionID: String,
        startedAt: Date,
        completedAt: Date?,
        model: String,
        sourceApplication: String?,
        audioFilename: String,
        transcriptFilename: String,
        status: DictationStatus,
        delivery: TranscriptDelivery?,
        error: String?
    ) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.model = model
        self.sourceApplication = sourceApplication
        self.audioFilename = audioFilename
        self.transcriptFilename = transcriptFilename
        self.status = status
        self.delivery = delivery
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
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Invalid ISO-8601 date")
                )
            }
            return date
        }
        return try decoder.decode(DictationMetadata.self, from: data)
    }

    private static func timestamp(from date: Date) -> String {
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

public struct DictationSession: Sendable {
    public let folderURL: URL
    public let audioURL: URL
    public let transcriptURL: URL
    public let metadataURL: URL
    public var metadata: DictationMetadata

    public init(
        folderURL: URL,
        audioURL: URL,
        transcriptURL: URL,
        metadataURL: URL,
        metadata: DictationMetadata
    ) {
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
            let applicationSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.rootURL = applicationSupport
                .appendingPathComponent("DictateMac", isDirectory: true)
                .appendingPathComponent("Dictations", isDirectory: true)
        }
        try FileManager.default.createDirectory(
            at: self.rootURL,
            withIntermediateDirectories: true
        )
    }

    public func startSession(
        at date: Date = Date(),
        sourceApplication: String?
    ) throws -> DictationSession {
        let baseName = ArchiveNaming.folderName(for: date)
        let folderURL = availableFolderURL(baseName: baseName)
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: false
        )

        let audioURL = folderURL.appendingPathComponent("audio.wav")
        let transcriptURL = folderURL.appendingPathComponent("transcript.txt")
        let metadataURL = folderURL.appendingPathComponent("metadata.json")
        let metadata = DictationMetadata(
            sessionID: folderURL.lastPathComponent,
            startedAt: date,
            completedAt: nil,
            model: Self.modelName,
            sourceApplication: sourceApplication,
            audioFilename: audioURL.lastPathComponent,
            transcriptFilename: transcriptURL.lastPathComponent,
            status: .recording,
            delivery: nil,
            error: nil
        )

        try Data().write(to: transcriptURL, options: .atomic)
        try write(metadata, to: metadataURL)

        return DictationSession(
            folderURL: folderURL,
            audioURL: audioURL,
            transcriptURL: transcriptURL,
            metadataURL: metadataURL,
            metadata: metadata
        )
    }

    public func writeTranscript(_ transcript: String, for session: DictationSession) throws {
        try Data(transcript.utf8).write(to: session.transcriptURL, options: .atomic)
    }

    public func writeMetadata(for session: DictationSession) throws {
        try write(session.metadata, to: session.metadataURL)
    }

    private func availableFolderURL(baseName: String) -> URL {
        var candidate = rootURL.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = rootURL.appendingPathComponent("\(baseName)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }

    private func write(_ metadata: DictationMetadata, to url: URL) throws {
        try MetadataCodec.encode(metadata).write(to: url, options: .atomic)
    }
}
