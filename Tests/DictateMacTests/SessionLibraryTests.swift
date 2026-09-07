import XCTest
import AVFAudio
import DictateMacCore
@testable import DictateMac

final class SessionLibraryTests: XCTestCase {
    private func fixture() throws -> (ArchiveStore, DictationSession) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dictator-library-test-" + UUID().uuidString)
        let store = try ArchiveStore(rootURL: root)
        var session = try store.startSession(sourceApplication: "Fixture")
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = 16_000
        buffer.int16ChannelData![0].initialize(repeating: 0, count: 16_000)
        do { let file = try AVAudioFile(forWriting: session.audioURL, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: false); try file.write(from: buffer) }
        try "Hallo, Welt!".write(to: session.transcriptURL, atomically: true, encoding: .utf8)
        session.metadata.status = .completed
        session.metadata.headline = "broken generated title"
        try store.writeMetadata(for: session)
        return (store, session)
    }

    func testLegacyFactsReadRealAudioWithoutMutatingFiles() throws {
        let (store, session) = try fixture()
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        let before = try [session.audioURL, session.transcriptURL, session.metadataURL].map { try Data(contentsOf: $0) }
        let info = SessionLibraryInfo(session: session)
        XCTAssertEqual(info.durationSeconds!, 1, accuracy: 0.001)
        XCTAssertEqual(info.durationLabel, "0:01")
        XCTAssertEqual(info.wordCount, 2)
        XCTAssertEqual(info.transcript, "Hallo, Welt!")
        XCTAssertEqual(info.audioURL, session.audioURL)
        XCTAssertTrue(info.title.hasPrefix("Aufnahme #"))
        XCTAssertFalse(info.title.contains("broken generated"))
        XCTAssertEqual(before, try [session.audioURL, session.transcriptURL, session.metadataURL].map { try Data(contentsOf: $0) })
    }

    func testUnknownFactsStayUnknownAndEveryStateLoads() throws {
        let (store, original) = try fixture()
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        var missing = original
        missing.audioURL = store.rootURL.appendingPathComponent("absent.wav")
        missing.transcriptURL = store.rootURL.appendingPathComponent("absent.txt")
        let info = SessionLibraryInfo(session: missing)
        XCTAssertNil(info.audioURL)
        XCTAssertNil(info.durationSeconds)
        XCTAssertEqual(info.durationLabel, "—")
        XCTAssertEqual(info.wordCount, 0)
        XCTAssertEqual(info.transcript, "")
        for state in [DictationStatus.recording, .saved, .transcribing, .completed, .failed] {
            var row = original
            row.metadata.status = state
            XCTAssertNotNil(SessionLibraryInfo(session: row).audioURL)
        }
    }

    func testTitleUsesOriginalImportNameOrExplicitUserTitle() throws {
        let (store, session) = try fixture()
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        var metadata = session.metadata
        metadata.recordingKind = "import"
        metadata.originalFilename = "Kundengespräch September.m4a"
        XCTAssertEqual(SessionLibraryInfo.title(for: metadata), "Kundengespräch September")
        metadata.displayTitle = "Projekt Atlas"
        XCTAssertEqual(SessionLibraryInfo.title(for: metadata), "Projekt Atlas")
        XCTAssertEqual(SessionLibraryInfo.kind(for: metadata), "Import")
    }

    func testUnicodeWordCountAndUnknownDuration() {
        XCTAssertEqual(SessionLibraryInfo.countWords("Hallo, Welt!"), 2)
        XCTAssertEqual(SessionLibraryInfo.countWords("--- … ! \n"), 0)
        XCTAssertEqual(SessionLibraryInfo.countWords("Grüße İstanbul don't"), 3)
        XCTAssertEqual(SessionLibraryInfo.durationLabel(nil), "—")
        XCTAssertEqual(SessionLibraryInfo.durationLabel(.nan), "—")
        XCTAssertEqual(SessionLibraryInfo.durationLabel(3013), "50:13")
        XCTAssertEqual(SessionLibraryInfo.durationLabel(3661), "1:01:01")
    }

    @MainActor
    func testDeniedFnStartupReleasesLibraryPlaybackGate() async throws {
        let (store, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        var asked = false
        let controller = DictationController(startServices: false,
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            readinessValidator: { _ in }, archiveStore: store,
            meetingPermission: { asked = true; return false })
        controller.refreshReadiness()
        for _ in 0..<100 {
            if controller.canStartDictation { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(controller.canStartDictation)
        controller.handleFnAction(.start)
        for _ in 0..<100 {
            if asked && !controller.hasActiveWork { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(asked)
        XCTAssertFalse(controller.isRecording)
        XCTAssertFalse(controller.isMeetingStarting)
        XCTAssertNotEqual(controller.activityPhase, "starting")
        XCTAssertEqual(controller.activityPhase, "failed")
        XCTAssertFalse(controller.hasActiveWork)
        controller.handleFnAction(.stop)
    }

    @MainActor
    func testInvalidatedFnStartupReleasesLibraryPlaybackGate() async throws {
        let (store, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        var permission: CheckedContinuation<Bool, Never>?
        let controller = DictationController(startServices: false,
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            readinessValidator: { _ in }, archiveStore: store,
            meetingPermission: { await withCheckedContinuation { permission = $0 } })
        controller.refreshReadiness()
        for _ in 0..<100 {
            if controller.canStartDictation { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        controller.handleFnAction(.start)
        for _ in 0..<100 {
            if permission != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNotNil(permission)
        controller.refreshReadiness()
        permission?.resume(returning: true)
        for _ in 0..<100 {
            if !controller.hasActiveWork { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(controller.isRecording)
        XCTAssertFalse(controller.hasActiveWork)
        XCTAssertNotEqual(controller.activityPhase, "starting")
        controller.handleFnAction(.stop)
    }

    @MainActor
    func testRenameChangesOnlyTitleAndSurvivesReload() throws {
        let (store, original) = try fixture()
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        let originalMetadata = try MetadataCodec.decode(Data(contentsOf: original.metadataURL))
        let originalAudio = try Data(contentsOf: original.audioURL)
        let originalText = try Data(contentsOf: original.transcriptURL)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let controller = DictationController(startServices: false, defaults: defaults, archiveStore: store)
        controller.refreshSessions()
        try controller.renameSession(original.metadata.sessionID, title: "Meeting mit Anna")
        let renamed = try XCTUnwrap(store.sessions().first)
        XCTAssertEqual(renamed.metadata.displayTitle, "Meeting mit Anna")
        var restored = renamed.metadata
        restored.displayTitle = nil
        XCTAssertEqual(restored, originalMetadata)
        XCTAssertEqual(try Data(contentsOf: original.audioURL), originalAudio)
        XCTAssertEqual(try Data(contentsOf: original.transcriptURL), originalText)
        XCTAssertEqual(controller.libraryDetails[original.metadata.sessionID]?.title, "Meeting mit Anna")
        XCTAssertThrowsError(try controller.renameSession(original.metadata.sessionID, title: String(repeating: "x", count: 161)))
        XCTAssertThrowsError(try controller.renameSession(original.metadata.sessionID, title: "Titel\nZeile"))
        try controller.renameSession(original.metadata.sessionID, title: "")
        XCTAssertNil(store.sessions().first?.metadata.displayTitle)
    }
}
