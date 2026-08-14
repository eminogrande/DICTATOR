import XCTest
@testable import DictateMacCore

final class EnhancedArchiveTests: XCTestCase {
    func testEnhancedSessionKeepsExactRawWhisperTranscript() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let archive = try ArchiveStore(rootURL: root)
        var session = try archive.startSession(sourceApplication: "Notes")
        try Data("RIFF-test-audio".utf8).write(to: session.audioURL)

        session = try archive.nameAndWriteTranscript(
            "Please open the Nuri repository.",
            rawTranscript: "please open the nuwi repo",
            for: session
        )

        XCTAssertEqual(try String(contentsOf: session.transcriptURL), "Please open the Nuri repository.")
        let rawName = try XCTUnwrap(session.metadata.rawTranscriptFilename)
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent(rawName)),
            "please open the nuwi repo"
        )
    }
}
