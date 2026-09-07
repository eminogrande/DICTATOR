import XCTest
import DictateMacCore
@testable import DictateMac

final class MeetingSessionTests: XCTestCase {
    private func archive() throws -> ArchiveStore {
        try ArchiveStore(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    @MainActor
    private func controller(_ archive: ArchiveStore, transcribe: ((URL) async throws -> String)? = nil) -> DictationController {
        DictationController(startServices: false,
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            archiveStore: archive, fileTranscriber: transcribe)
    }

    @MainActor
    private func finished(_ c: DictationController) async throws {
        for _ in 0..<500 {
            if !c.hasActiveWork { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Work did not finish")
    }

    @MainActor
    func testMeetingAndImportEnabledWithoutModelButFnBlocked() throws {
        let store = try archive()
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        let c = controller(store)
        XCTAssertTrue(c.canToggleRecording)
        XCTAssertTrue(c.canTranscribeFile)
        XCTAssertFalse(c.canStartDictation)
        c.handleFnAction(.start)
        XCTAssertFalse(c.isRecording)
        XCTAssertTrue(c.blockedHUDVisible)
    }

    @MainActor
    func testFailedSessionVisibleAndRetryPreservesAudioAndSessionIdentity() async throws {
        let store = try archive()
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        var session = try store.startSession(sourceApplication: "test")
        let audio = Data([1, 4, 8, 16]) // test double input, not inference proof
        try audio.write(to: session.audioURL)
        session.metadata.status = .failed
        session.metadata.error = "previous failure"
        try store.writeMetadata(for: session)
        var attempts = 0
        let c = controller(store) { url in
            attempts += 1
            XCTAssertEqual(url, session.audioURL)
            if attempts == 1 { throw EngineValidationError("test failure") }
            return "Meeting test transcript."
        }
        XCTAssertEqual(c.sessions.count, 1)
        c.retryTranscription(session.metadata.sessionID)
        c.retryTranscription(session.metadata.sessionID) // single-flight duplicate must do nothing
        try await finished(c)
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(c.activityPhase, "failed")
        XCTAssertEqual(c.sessions.first?.metadata.error, "test failure")
        XCTAssertEqual(try Data(contentsOf: session.audioURL), audio)
        c.retryTranscription(session.metadata.sessionID)
        try await finished(c)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(c.activityPhase, "completed")
        XCTAssertEqual(c.sessions.count, 1)
        XCTAssertEqual(c.sessions.first?.metadata.sessionID, session.metadata.sessionID)
        XCTAssertEqual(c.sessions.first?.metadata.status, .completed)
        XCTAssertNil(c.sessions.first?.metadata.error)
        XCTAssertNil(c.sessions.first?.metadata.delivery) // no paste on background retry
        XCTAssertEqual(try String(contentsOf: session.transcriptURL), "Meeting test transcript.")
        XCTAssertEqual(try Data(contentsOf: session.audioURL), audio)
    }

    @MainActor
    func testMissingModelLeavesAudioSavedAndRetryVisible() async throws {
        let store = try archive()
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        var session = try store.startSession(sourceApplication: "test")
        session.metadata.status = .failed
        try Data([2, 3]).write(to: session.audioURL)
        try store.writeMetadata(for: session)
        let c = controller(store)
        c.retryTranscription(session.metadata.sessionID)
        try await finished(c)
        XCTAssertEqual(c.activityPhase, "saved")
        XCTAssertEqual(c.sessions.first?.metadata.status, .saved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.audioURL.path))
    }

    @MainActor
    func testStoppingSuspendedMeetingStartupDoesNotRecordLater() async throws {
        let store = try archive()
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        var permission: CheckedContinuation<Bool, Never>?
        let c = DictationController(startServices: false,
            defaults: UserDefaults(suiteName: UUID().uuidString)!, archiveStore: store,
            meetingPermission: { await withCheckedContinuation { permission = $0 } })
        c.toggleRecording()
        for _ in 0..<100 {
            if permission != nil { break }
            await Task.yield()
        }
        XCTAssertNotNil(permission)
        XCTAssertTrue(c.isMeetingStarting)
        XCTAssertTrue(c.canToggleRecording)
        c.handleFnAction(.toggle) // Fn+R stop during the suspended microphone request
        permission?.resume(returning: true)
        try await finished(c)
        XCTAssertFalse(c.isRecording)
        XCTAssertFalse(c.isMeetingStarting)
        XCTAssertEqual(store.sessions().count, 0)
    }

    func testRetryRetainsExistingTextAndGraphFailureCannotDowngradeCompletion() throws {
        let store = try archive()
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        var session = try store.startSession(sourceApplication: "test")
        try Data([1]).write(to: session.audioURL)
        session.metadata.status = .transcribing
        try store.writeMetadata(for: session)
        try "User-edited original transcript".write(to: session.transcriptURL, atomically: true, encoding: .utf8)
        try store.recoverInterruptedSessions()
        // Break only the disposable test archive's derived index destination.
        let graph = store.rootURL.appendingPathComponent("graph.json")
        try FileManager.default.removeItem(at: graph)
        try FileManager.default.createDirectory(at: graph, withIntermediateDirectories: false)
        let saved = try store.saveTranscript("New ASR result", model: "test", for: session)
        XCTAssertEqual(saved.metadata.status, .completed)
        XCTAssertEqual(store.sessions().first?.metadata.status, .completed)
        XCTAssertEqual(try String(contentsOf: session.transcriptURL), "New ASR result")
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: store.rootURL, includingPropertiesForKeys: nil).first { $0.lastPathComponent.contains(".previous-") })
        XCTAssertEqual(try String(contentsOf: backup), "User-edited original transcript")
    }

    func testRelaunchRecoversInterruptedSessionsWithoutHidingOrDeletingAny() throws {
        let store = try archive()
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        var expected: [URL: Data] = [:]
        for status in [DictationStatus.recording, .transcribing, .failed, .saved, .completed] {
            var session = try store.startSession(sourceApplication: "test")
            session.metadata.status = status
            let audio = Data(status.rawValue.utf8)
            try audio.write(to: session.audioURL)
            expected[session.audioURL] = audio
            try store.writeMetadata(for: session)
        }
        try store.recoverInterruptedSessions()
        XCTAssertEqual(store.sessions().count, 5)
        XCTAssertFalse(store.sessions().contains { [.recording, .transcribing].contains($0.metadata.status) })
        XCTAssertEqual(store.sessions().filter { $0.metadata.status == .saved }.count, 3)
        for (url, audio) in expected { XCTAssertEqual(try Data(contentsOf: url), audio) }
        XCTAssertEqual(try ArchiveStore(rootURL: store.rootURL).sessions().count, 5)
    }
}
