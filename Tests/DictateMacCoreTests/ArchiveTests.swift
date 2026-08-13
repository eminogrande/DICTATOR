import Foundation
import XCTest
@testable import DictateMacCore

final class ArchiveTests: XCTestCase {
    func testFolderNameUsesStableUTCTimestamp() throws {
        let date = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-13T13:16:46Z")
        )

        XCTAssertEqual(
            ArchiveNaming.folderName(for: date),
            "2026-08-13T13-16-46.000Z"
        )
    }

    func testMetadataRoundTripsAsJSON() throws {
        let date = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-13T13:16:46Z")
        )
        let metadata = DictationMetadata(
            sessionID: "2026-08-13T13-16-46.000Z",
            startedAt: date,
            completedAt: nil,
            model: "large-v3_turbo",
            sourceApplication: "Notes",
            audioFilename: "audio.wav",
            transcriptFilename: "transcript.txt",
            status: .recording,
            delivery: nil,
            autoPasteEnabled: false,
            error: nil
        )

        let encoded = try MetadataCodec.encode(metadata)
        let decoded = try MetadataCodec.decode(encoded)

        XCTAssertEqual(decoded, metadata)
        XCTAssertEqual(decoded.autoPasteEnabled, false)
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains("large-v3_turbo"))
    }

    func testTranscriptCleanupCollapsesWhitespace() {
        let raw = "  Hallo   world\n\nThis\tis English.  "

        XCTAssertEqual(
            TranscriptCleaner.clean(raw),
            "Hallo world This is English."
        )
    }
}
