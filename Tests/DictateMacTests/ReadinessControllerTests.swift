import XCTest
import DictateMacCore
@testable import DictateMac

final class ReadinessControllerTests: XCTestCase {
    @MainActor
    private func controller(validator: @escaping (TranscriptionEngine) async throws -> Void) -> DictationController {
        let defaults = UserDefaults(suiteName: "DICTATOR-tests-" + UUID().uuidString)!
        return DictationController(startServices: false, defaults: defaults, readinessValidator: validator)
    }

    @MainActor
    private func settled(_ c: DictationController) async throws {
        for _ in 0..<300 {
            if !c.readiness.isLoading { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Readiness never settled")
    }

    @MainActor
    func testEveryFnStartAndFileIsBlockedWhileLoadingWithoutArchiveOrMic() async throws {
        let c = controller { _ in }
        XCTAssertEqual(c.readiness.phase, .loading)
        XCTAssertFalse(c.canToggleRecording)
        for action in [PushToTalkAction.start, .compressStart, .toggle] {
            c.handleFnAction(action)
            XCTAssertFalse(c.isRecording)
            XCTAssertFalse(c.hasActiveWork)
        }
        XCTAssertTrue(c.blockedHUDVisible)
        XCTAssertFalse(c.readinessStatus.isEmpty)
        c.transcribeAudioFile(URL(fileURLWithPath: "/not-a-real-file.wav"))
        XCTAssertFalse(c.isTranscribingFile)
        c.handleFnAction(.stop)
        XCTAssertFalse(c.blockedHUDVisible)
    }

    @MainActor
    func testFailureBlocksFnAndRetryCanBecomeReadyWithoutPreview() async throws {
        var fail = true
        let c = controller { _ in if fail { throw EngineValidationError("Missing VAD") } }
        c.refreshReadiness()
        try await settled(c)
        XCTAssertEqual(c.readiness.error, "Missing VAD")
        c.handleFnAction(.start)
        XCTAssertFalse(c.hasActiveWork)
        XCTAssertTrue(c.blockedHUDVisible)
        c.handleFnAction(.stop)
        fail = false
        c.retryReadiness()
        XCTAssertFalse(c.canToggleRecording)
        try await settled(c)
        XCTAssertTrue(c.canToggleRecording) // preview never started in this controller
        XCTAssertTrue(c.canTranscribeFile)
        // Completing validation never automatically records a previously blocked hold.
        XCTAssertFalse(c.isRecording)
    }

    @MainActor
    func testSelectionImmediatelyRevokesReadyAndOldProbeCannotEnableNewEngine() async throws {
        let c = controller { engine in
            if engine == .qwen3ASR { throw EngineValidationError("Missing cached weights") }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        c.refreshReadiness()
        try await settled(c)
        XCTAssertTrue(c.canToggleRecording)
        c.transcriptionEngine = .whisperKit
        XCTAssertFalse(c.canToggleRecording)
        c.transcriptionEngine = .qwen3ASR
        c.handleFnAction(.start)
        try await settled(c)
        XCTAssertEqual(c.readiness.engineID, TranscriptionEngine.qwen3ASR.rawValue)
        XCTAssertEqual(c.readiness.error, "Missing cached weights")
        XCTAssertFalse(c.canToggleRecording)
        XCTAssertFalse(c.isRecording)
    }

    @MainActor
    func testSlowBuiltInCannotBlockNewSidecarSelection() async throws {
        var release: CheckedContinuation<Void, Never>?
        let c = controller { engine in
            if engine == .whisperKit { await withCheckedContinuation { release = $0 } }
        }
        c.transcriptionEngine = .whisperKit
        while release == nil { await Task.yield() }
        c.transcriptionEngine = .whisperCpp
        try await settled(c)
        XCTAssertTrue(c.canToggleRecording)
        release?.resume()
        await Task.yield()
        XCTAssertEqual(c.readiness.engineID, TranscriptionEngine.whisperCpp.rawValue)
    }

    @MainActor
    func testMissingInstalledModelReallyBlocksControllerBeforeCapture() async throws {
        let root = try EngineValidation.temporaryOutputDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("wcpp/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"),
                                         to: bin.appendingPathComponent("whisper-cli"))
        let c = controller { try $0.checkInstallation(toolsURL: root) }
        c.refreshReadiness()
        try await settled(c)
        XCTAssertTrue(c.readiness.error?.contains("Model is missing:") == true)
        c.handleFnAction(.start)
        XCTAssertFalse(c.canToggleRecording)
        XCTAssertFalse(c.hasActiveWork)
    }

    @MainActor
    func testRuntimeDependencyFailureReallyBlocksControllerBeforeCapture() async throws {
        let root = try EngineValidation.temporaryOutputDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let c = controller { _ in
            let result = try await SubprocessCapture.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: [root.appendingPathComponent("missing-python-runtime").path], timeout: 2)
            XCTAssertNotEqual(result.terminationStatus, 0)
            _ = try EngineValidation.checkedText(result, output: root.appendingPathComponent("output.txt"))
        }
        c.refreshReadiness()
        try await settled(c)
        XCTAssertNotNil(c.readiness.error)
        c.handleFnAction(.start)
        XCTAssertFalse(c.canToggleRecording)
        XCTAssertFalse(c.hasActiveWork)
    }

    func testProbeRequiresRealOutputNotExitCodeOrStdoutChatter() throws {
        let directory = try EngineValidation.temporaryOutputDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let out = directory.appendingPathComponent("result.txt")
        let result = CapturedSubprocessResult(terminationStatus: 0, stdout: Data("model loaded".utf8), stderr: Data())
        XCTAssertThrowsError(try EngineValidation.checkedText(result, output: out))
        try "  \n".write(to: out, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try EngineValidation.checkedText(result, output: out))
        try "Ready for local dictation.".write(to: out, atomically: true, encoding: .utf8)
        XCTAssertFalse(try EngineValidation.checkedText(result, output: out).isEmpty)
    }

    func testWhisperProbeUsesVADAndSameArgumentsAsFinalPass() {
        let args = WhisperCppService.arguments(wavURL: EngineValidation.fixtureURL)
        XCTAssertTrue(args.contains("--vad"))
        XCTAssertTrue(args.contains(TranscriptionEngine.wcppVADModelURL.path))
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: EngineValidation.fixtureURL.path))
        XCTAssertEqual(TranscriptionEngine.localEnvironment["HF_HUB_OFFLINE"], "1")
    }

    func testInstalledSidecarsReallyInferWhenExplicitlyRequested() async throws {
        guard ProcessInfo.processInfo.environment["DICTATOR_VALIDATE_LOCAL_ENGINES"] == "1" else {
            throw XCTSkip("Opt-in local integration: DICTATOR_VALIDATE_LOCAL_ENGINES=1 ./test.sh --filter testInstalledSidecars")
        }
        let requested = ProcessInfo.processInfo.environment["DICTATOR_VALIDATE_ENGINE"]
        for engine in [TranscriptionEngine.whisperCpp, .qwen3ASR] where requested == nil || requested == engine.rawValue {
            try await EngineValidation.validateSidecar(engine)
            print("INFERENCE_VALIDATED: \(engine.rawValue)")
        }
    }
}
