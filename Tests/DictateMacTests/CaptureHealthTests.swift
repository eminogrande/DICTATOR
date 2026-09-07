import Foundation
import AVFAudio
import DictateMacCore
import XCTest
@testable import DictateMac

final class CaptureHealthTests: XCTestCase {
    @MainActor
    private func fixture(transcribe: Bool = false) throws -> (DictationController, SilentMicrophone, ArchiveStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DICTATOR-capture-health-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let suite = "DICTATOR-capture-health-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let archive = try ArchiveStore(rootURL: root)
        let microphone = SilentMicrophone()
        let transcriber: ((URL) async throws -> String)? = transcribe ? { _ in "Dies ist eine lokale Testaufnahme." } : nil
        let controller = DictationController(startServices: false, defaults: defaults,
                                             readinessValidator: { _ in }, archiveStore: archive,
                                             fileTranscriber: transcriber, meetingPermission: { true },
                                             microphoneRecorder: microphone)
        controller.meetingCaptureEnabled = false
        return (controller, microphone, archive)
    }

    @MainActor
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Capture state did not settle")
    }

    @MainActor
    func testUnexpectedMicrophoneStopEndsRECAndRetainsAudioAndWarning() async throws {
        let (controller, microphone, archive) = try fixture()
        controller.toggleRecording()
        try await wait { controller.isRecording }
        let original = try XCTUnwrap(archive.sessions().first)
        let bytes = try Data(contentsOf: original.audioURL)
        microphone.isRecording = false // Device failure; no real microphone is used.
        controller.updateAudioActivity()
        XCTAssertFalse(controller.isRecording)
        XCTAssertFalse(controller.isLatchedRecordingPublished)
        XCTAssertEqual(microphone.stopCalls, 1)
        try await wait { !controller.hasActiveWork }
        let saved = try XCTUnwrap(archive.sessions().first)
        XCTAssertEqual(saved.metadata.sessionID, original.metadata.sessionID)
        XCTAssertEqual(saved.metadata.status, .saved)
        XCTAssertTrue(saved.metadata.captureWarning?.contains("Mikrofon-Aufnahme unerwartet unterbrochen") == true)
        XCTAssertEqual(try Data(contentsOf: saved.audioURL), bytes)
        XCTAssertNotEqual(controller.activityPhase, "recording")
    }

    @MainActor
    func testCaptureWarningSurvivesSuccessfulBackgroundTranscription() async throws {
        let (controller, microphone, archive) = try fixture(transcribe: true)
        controller.toggleRecording()
        try await wait { controller.isRecording }
        microphone.isRecording = false
        controller.updateAudioActivity()
        try await wait { !controller.hasActiveWork }
        let session = try XCTUnwrap(archive.sessions().first)
        XCTAssertEqual(session.metadata.status, .completed)
        XCTAssertTrue(session.metadata.captureWarning?.contains("Mikrofon-Aufnahme unerwartet unterbrochen") == true)
        XCTAssertEqual(try String(contentsOf: session.transcriptURL, encoding: .utf8), "Dies ist eine lokale Testaufnahme.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.audioURL.path))
    }

    @MainActor
    func testHealthyTickAndExplicitStopDoNotInventCaptureFailure() async throws {
        let (controller, microphone, archive) = try fixture()
        controller.toggleRecording()
        try await wait { controller.isRecording }
        microphone.level = 0.25
        controller.updateAudioActivity()
        XCTAssertTrue(controller.isRecording)
        XCTAssertEqual(controller.microphoneLevel, 0.25)
        XCTAssertEqual(controller.microphoneStatus, "Receiving audio")
        controller.toggleRecording()
        controller.updateAudioActivity()
        try await wait { !controller.hasActiveWork }
        XCTAssertNil(try XCTUnwrap(archive.sessions().first).metadata.captureWarning)
        XCTAssertEqual(microphone.stopCalls, 1)
    }

    @MainActor
    func testIdleTickDoesNotStartStopOrCreateSession() throws {
        let (controller, microphone, archive) = try fixture()
        controller.updateAudioActivity()
        XCTAssertFalse(controller.hasActiveWork)
        XCTAssertEqual(microphone.startCalls, 0)
        XCTAssertEqual(microphone.stopCalls, 0)
        XCTAssertTrue(archive.sessions().isEmpty)
    }

    @MainActor
    func testFailedFnRStartupDoesNotKeepLatchIntentForNextHold() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DICTATOR-latch-failure-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let suite = "DICTATOR-latch-failure-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        var permission: CheckedContinuation<Bool, Never>?
        var permissionCalls = 0
        let microphone = SilentMicrophone()
        let controller = DictationController(startServices: false, defaults: defaults,
            readinessValidator: { _ in }, archiveStore: try ArchiveStore(rootURL: root),
            meetingPermission: {
                permissionCalls += 1
                if permissionCalls > 1 { return false }
                return await withCheckedContinuation { permission = $0 }
            }, microphoneRecorder: microphone)
        controller.refreshReadiness()
        try await wait { controller.canStartDictation }
        controller.handleFnAction(.start)
        try await wait { permission != nil }
        controller.handleFnAction(.toggle)
        controller.handleFnAction(.stop)
        permission?.resume(returning: false)
        try await wait { !controller.hasActiveWork }
        // A fresh short hold must still honor release within the 120ms chord window.
        controller.handleFnAction(.start)
        controller.handleFnAction(.stop)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(permissionCalls, 1)
        XCTAssertEqual(microphone.startCalls, 0)
        XCTAssertFalse(controller.hasActiveWork)
    }

    @MainActor
    func testFirstMeetingMixRecoversFullMicBeforeReadingStaleCheckpoint() async throws {
        let (controller, _, archive) = try fixture()
        var session = try archive.startSession(sourceApplication: "Meeting")
        session.metadata.status = .saved
        session.metadata.recordingKind = "meeting"
        session.metadata.captureWarning = "Mikrofon-Aufnahme wurde unterbrochen."
        session.metadata.systemAudioFilename = session.metadata.sessionID + ".system.wav"
        session.metadata.systemAudioOffset = 0
        // Two seconds retained, but the native header still advertises only one.
        var native = Data()
        func tag(_ value: String) { native.append(contentsOf: value.utf8) }
        func word<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { native.append(contentsOf: $0) }
        }
        tag("RIFF"); word(UInt32(4088 + 32_000)); tag("WAVEJUNK"); word(UInt32(28))
        native.append(Data(count: 28))
        tag("fmt "); word(UInt32(16)); word(UInt16(1)); word(UInt16(1))
        word(UInt32(16_000)); word(UInt32(32_000)); word(UInt16(2)); word(UInt16(16))
        tag("FLLR"); word(UInt32(4008)); native.append(Data(count: 4008))
        tag("data"); word(UInt32(32_000))
        XCTAssertEqual(native.count, 4096)
        for _ in 0..<32_000 { native.append(contentsOf: [UInt8(0), UInt8(32)]) }
        try native.write(to: session.audioURL)
        let systemURL = session.folderURL.appendingPathComponent(session.metadata.systemAudioFilename!)
        let systemWriter = try MeetingPCMWriter(url: systemURL)
        try systemWriter.append([Float](repeating: 0, count: 16_000))
        try systemWriter.close()
        let systemBytes = try Data(contentsOf: systemURL)
        try archive.writeMetadata(for: session)

        let prepared = try await controller.prepareSavedAudio(for: session)
        XCTAssertNotNil(prepared.metadata.recoveredAudioFilename)
        XCTAssertTrue(prepared.metadata.captureWarning?.contains("unterbrochen") == true)
        XCTAssertEqual(prepared.metadata.audioFilename, session.metadata.audioFilename)
        let mixedURL = session.folderURL.appendingPathComponent(try XCTUnwrap(prepared.metadata.transcriptionAudioFilename))
        let mixed = try AVAudioFile(forReading: mixedURL)
        XCTAssertEqual(mixed.length, 32_000)
        mixed.framePosition = 16_000
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: mixed.processingFormat, frameCapacity: 16_000))
        try mixed.read(into: buffer)
        XCTAssertEqual(buffer.frameLength, 16_000)
        XCTAssertGreaterThan(buffer.floatChannelData![0][0], 0.1)
        XCTAssertEqual(try Data(contentsOf: session.audioURL), native)
        XCTAssertEqual(try Data(contentsOf: systemURL), systemBytes)
        XCTAssertEqual(SessionLibraryInfo(session: prepared).audioURL, mixedURL)
        let repeated = try await controller.prepareSavedAudio(for: prepared)
        XCTAssertEqual(repeated.metadata.transcriptionAudioFilename, prepared.metadata.transcriptionAudioFilename)
        XCTAssertEqual(repeated.metadata.recoveredAudioFilename, prepared.metadata.recoveredAudioFilename)
    }

    @MainActor
    func testFinalizedNativeAVAudioFileRemainsUnchangedAndRetryable() throws {
        let (_, _, archive) = try fixture()
        var session = try archive.startSession(sourceApplication: "Meeting")
        session.metadata.status = .saved
        session.metadata.recordingKind = "dictation"
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false]
        var writer: AVAudioFile? = try AVAudioFile(forWriting: session.audioURL,
            settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: writer!.processingFormat, frameCapacity: 16_000))
        buffer.frameLength = 16_000
        buffer.floatChannelData![0].initialize(repeating: 0, count: 16_000)
        try writer!.write(from: buffer)
        writer = nil // Finalize the real native WAV before recovery examines it.
        try archive.writeMetadata(for: session)
        let source = try Data(contentsOf: session.audioURL)
        let metadata = try Data(contentsOf: session.metadataURL)
        let result = try archive.recoverMicrophone(for: session)
        XCTAssertNil(result.metadata.recoveredAudioFilename)
        XCTAssertEqual(try Data(contentsOf: session.audioURL), source)
        XCTAssertEqual(try Data(contentsOf: session.metadataURL), metadata)
        XCTAssertEqual(try AVAudioFile(forReading: session.audioURL).length, 16_000)
    }

    @MainActor
    func testCaptureWarningsAccumulateWithoutLosingEarlierFailure() {
        XCTAssertNil(DictationController.captureWarning(nil, adding: nil))
        XCTAssertEqual(DictationController.captureWarning("Mic failed", adding: nil), "Mic failed")
        XCTAssertEqual(DictationController.captureWarning("Mic failed", adding: ""), "Mic failed")
        XCTAssertEqual(DictationController.captureWarning("Mic failed", adding: "Mic failed"), "Mic failed")
        XCTAssertEqual(DictationController.captureWarning("Mic failed", adding: "Disk full"), "Mic failed\nDisk full")
    }
}

/// Writes one real silent PCM WAV, but never opens a device or plays sound.
@MainActor
private final class SilentMicrophone: MicrophoneRecording {
    var isRecording = false
    var elapsed: TimeInterval = 1
    var level: Float = 0
    var startCalls = 0
    var stopCalls = 0

    func start(at url: URL) throws {
        let writer = try MeetingPCMWriter(url: url)
        try writer.append([Float](repeating: 0, count: 16_000))
        try writer.close()
        startCalls += 1
        isRecording = true
    }

    func stop() {
        stopCalls += 1
        isRecording = false
    }
}
