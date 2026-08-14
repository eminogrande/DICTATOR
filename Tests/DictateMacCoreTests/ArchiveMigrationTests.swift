import CryptoKit
import Foundation
import XCTest
@testable import DictateMacCore

final class ArchiveMigrationTests: XCTestCase {
    func testLegacyFolderMigratesFlatWithoutChangingAudioOrTranscriptBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("2026-08-13T13-16-46.000Z")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let audio = Data("RIFF-original-audio".utf8)
        let transcript = Data("Wallet recovery meeting notes.".utf8)
        try audio.write(to: legacy.appendingPathComponent("audio.wav"))
        try transcript.write(to: legacy.appendingPathComponent("transcript.txt"))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-13T13:16:46Z"))
        let metadata = DictationMetadata(
            sessionID: legacy.lastPathComponent,
            startedAt: date,
            completedAt: date,
            model: "large-v3_turbo",
            sourceApplication: "Notes",
            audioFilename: "audio.wav",
            transcriptFilename: "transcript.txt",
            status: .completed,
            delivery: .clipboardOnly,
            error: nil
        )
        try MetadataCodec.encode(metadata).write(to: legacy.appendingPathComponent("metadata.json"))
        let audioHash = SHA256.hash(data: audio)
        let transcriptHash = SHA256.hash(data: transcript)

        _ = try ArchiveStore(rootURL: root)

        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        let migratedAudio = try XCTUnwrap(files.first { $0.pathExtension == "wav" })
        let migratedTranscript = try XCTUnwrap(files.first { $0.pathExtension == "txt" })
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: migratedAudio)), audioHash)
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: migratedTranscript)), transcriptHash)
        XCTAssertTrue(migratedAudio.lastPathComponent.hasPrefix("000001_"))
        XCTAssertTrue(migratedAudio.lastPathComponent.contains("wallet-recovery-meeting-notes"))
    }
}
