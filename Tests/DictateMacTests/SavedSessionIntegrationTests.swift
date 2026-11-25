import XCTest
import DictateMacCore
import CryptoKit
@testable import DictateMac

/// Explicit opt-in: copy ONE named saved session into an isolated archive for real ASR.
/// The user's archive and source audio remain untouched; successful fixture audio is deleted.
final class SavedSessionIntegrationTests: XCTestCase {
    @MainActor
    func testExplicitSavedSessionRetry() async throws {
        guard let root = ProcessInfo.processInfo.environment["DICTATOR_RETRY_ARCHIVE"],
              let id = ProcessInfo.processInfo.environment["DICTATOR_RETRY_SESSION_ID"] else {
            throw XCTSkip("Opt-in saved-audio integration requires exact archive path and session ID")
        }
        let sourceRoot = URL(fileURLWithPath: root)
        let sourceMetadataURL = sourceRoot.appendingPathComponent(id).appendingPathExtension("json")
        let sourceMetadata = try MetadataCodec.decode(Data(contentsOf: sourceMetadataURL))
        guard [.failed, .saved].contains(sourceMetadata.status) else {
            return XCTFail("Explicit source must be saved or failed")
        }
        let source = sourceRoot.appendingPathComponent(sourceMetadata.compressedAudioFilename
            ?? sourceMetadata.transcriptionAudioFilename ?? sourceMetadata.recoveredAudioFilename ?? sourceMetadata.audioFilename)
        let before = try checksum(source)
        let isolatedRoot = FileManager.default.temporaryDirectory.appendingPathComponent("DICTATOR-ASR-" + UUID().uuidString)
        let store = try ArchiveStore(rootURL: isolatedRoot)
        defer { try? FileManager.default.removeItem(at: isolatedRoot) }
        var session = try store.startSession(sourceApplication: "isolated integration fixture")
        let copiedAudio = session.audioURL.deletingPathExtension().appendingPathExtension(source.pathExtension)
        try FileManager.default.copyItem(at: source, to: copiedAudio)
        session.audioURL = copiedAudio
        session.metadata.audioFilename = copiedAudio.lastPathComponent
        session.metadata.status = .saved
        try store.writeMetadata(for: session)
        let fixtureID = session.metadata.sessionID
        let c = DictationController(startServices: false,
            defaults: UserDefaults(suiteName: UUID().uuidString)!, archiveStore: store,
            fileTranscriber: { url in
                let task = try WhisperCppFileTask(wavURL: url)
                return try await task.run { snapshot in
                    if !snapshot.text.isEmpty { print("REAL_ASR_PREVIEW", snapshot.text) }
                }
            })
        c.retryTranscription(fixtureID)
        for _ in 0..<1_800 {
            if !c.hasActiveWork { break }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        XCTAssertFalse(c.hasActiveWork)
        XCTAssertEqual(c.activityPhase, "completed", c.statusText)
        let result = try XCTUnwrap(store.sessions().first { $0.metadata.sessionID == fixtureID })
        XCTAssertEqual(result.metadata.status, .completed, result.metadata.error ?? "")
        XCTAssertFalse(try String(contentsOf: result.transcriptURL).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copiedAudio.path))
        XCTAssertNotNil(result.metadata.audioDeletedAt)
        XCTAssertEqual(try checksum(source), before)
        print("RETRY_VERIFIED_SOURCE_UNCHANGED", id, before)
    }

    private func checksum(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
