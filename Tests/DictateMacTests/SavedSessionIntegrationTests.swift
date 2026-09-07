import XCTest
import DictateMacCore
import CryptoKit
@testable import DictateMac

/// Explicit opt-in only: runs real ASR on ONE named saved session. Never deletes sources.
final class SavedSessionIntegrationTests: XCTestCase {
    @MainActor
    func testExplicitSavedSessionRetry() async throws {
        guard let root = ProcessInfo.processInfo.environment["DICTATOR_RETRY_ARCHIVE"],
              let id = ProcessInfo.processInfo.environment["DICTATOR_RETRY_SESSION_ID"] else {
            throw XCTSkip("Opt-in saved-audio integration requires exact archive path and session ID")
        }
        let store = try ArchiveStore(rootURL: URL(fileURLWithPath: root))
        let session = try XCTUnwrap(store.sessions().first { $0.metadata.sessionID == id })
        XCTAssertTrue([DictationStatus.failed, .saved].contains(session.metadata.status))
        guard [.failed, .saved].contains(session.metadata.status) else { return }
        let before = try checksum(session.audioURL)
        let c = DictationController(startServices: false,
            defaults: UserDefaults(suiteName: UUID().uuidString)!, archiveStore: store,
            fileTranscriber: { url in
                let task = try WhisperCppFileTask(wavURL: url)
                return try await task.run { snapshot in
                    if !snapshot.text.isEmpty { print("REAL_ASR_PREVIEW", snapshot.text) }
                }
            })
        c.retryTranscription(id)
        for _ in 0..<1_800 {
            if !c.hasActiveWork { break }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        XCTAssertFalse(c.hasActiveWork)
        XCTAssertEqual(c.activityPhase, "completed", c.statusText)
        let result = try XCTUnwrap(store.sessions().first { $0.metadata.sessionID == id })
        XCTAssertEqual(result.metadata.status, .completed, result.metadata.error ?? "")
        XCTAssertFalse(try String(contentsOf: result.transcriptURL).isEmpty)
        XCTAssertEqual(try checksum(session.audioURL), before)
        print("RETRY_VERIFIED", id, result.transcriptURL.path, before)
    }

    private func checksum(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
