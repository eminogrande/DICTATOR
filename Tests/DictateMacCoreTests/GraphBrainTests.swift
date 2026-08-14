import Foundation
import XCTest
@testable import DictateMacCore

final class GraphBrainTests: XCTestCase {
    func testMeaningfulFlatFilename() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-13T13:16:46Z"))
        let berlin = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))

        XCTAssertEqual(
            ArchiveNaming.baseName(
                sequence: 28,
                date: date,
                headline: "Audio files automatically named right way",
                timeZone: berlin
            ),
            "000028_2026-08-13_15-16_audio-files-automatically-named-right-way"
        )
    }

    func testSummaryHeadlineAndKeywordsAreLocalAndDeterministic() {
        let transcript = "I want all audio files automatically named in the right way. This makes the archive searchable later."
        let analysis = GraphBrainText.analyze(transcript)

        XCTAssertEqual(analysis.summary, "I want all audio files automatically named in the right way.")
        XCTAssertEqual(analysis.headline, "audio files automatically named right way")
        XCTAssertTrue(analysis.keywords.contains("audio"))
        XCTAssertTrue(analysis.keywords.contains("archive"))
        XCTAssertTrue(analysis.keywords.contains("searchable"))
        XCTAssertLessThanOrEqual(analysis.keywords.count, 10)
    }

    func testCompletedSessionIsFlatAndKeepsGraphMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-13T13:16:46Z"))
        let archive = try ArchiveStore(rootURL: root)
        var session = try archive.startSession(at: date, sourceApplication: "Notes")
        try Data("RIFF-audio".utf8).write(to: session.audioURL)

        session = try archive.nameAndWriteTranscript("Graph brain connects archive keywords.", for: session)
        session.metadata.status = .completed
        session.metadata.delivery = .clipboardOnly
        try archive.complete(session)

        XCTAssertEqual(session.folderURL, root)
        XCTAssertEqual(
            session.audioURL.deletingLastPathComponent().standardizedFileURL,
            root.standardizedFileURL
        )
        XCTAssertTrue(session.audioURL.lastPathComponent.hasSuffix("_graph-brain-connects-archive-keywords.wav"))
        XCTAssertEqual(try String(contentsOf: session.transcriptURL), "Graph brain connects archive keywords.")
        let savedMetadata = try MetadataCodec.decode(Data(contentsOf: session.metadataURL))
        XCTAssertEqual(savedMetadata.headline, "graph brain connects archive keywords")
        XCTAssertTrue(savedMetadata.keywords?.contains("graph") == true)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]).contains {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        })
    }


}
