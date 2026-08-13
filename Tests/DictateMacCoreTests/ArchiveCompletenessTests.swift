import Foundation
import XCTest
@testable import DictateMacCore

final class ArchiveCompletenessTests: XCTestCase {
    func testCompletedSessionPersistsAudioTranscriptAndMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let archive = try ArchiveStore(rootURL: root)
        var session = try archive.startSession(sourceApplication: "Notes")
        try Data("RIFF-test-audio".utf8).write(to: session.audioURL)
        try archive.writeTranscript("Permanent transcript", for: session)
        session.metadata.status = .completed
        session.metadata.delivery = .clipboardOnly
        session.metadata.autoPasteEnabled = false
        try archive.writeMetadata(for: session)

        XCTAssertTrue(FileManager.default.fileExists(atPath: session.audioURL.path))
        XCTAssertEqual(try String(contentsOf: session.transcriptURL), "Permanent transcript")
        let metadata = try MetadataCodec.decode(Data(contentsOf: session.metadataURL))
        XCTAssertEqual(metadata.status, .completed)
        XCTAssertEqual(metadata.delivery, .clipboardOnly)
        XCTAssertEqual(metadata.autoPasteEnabled, false)
    }
}
