import Foundation
import XCTest
@testable import DictateMac

final class WhisperCppFileTaskTests: XCTestCase {
    private final class Snapshots: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [WhisperCppFileTask.Snapshot] = []
        func append(_ value: WhisperCppFileTask.Snapshot) {
            lock.lock(); defer { lock.unlock() }; values.append(value)
        }
        func all() -> [WhisperCppFileTask.Snapshot] {
            lock.lock(); defer { lock.unlock() }; return values
        }
    }

    private func task(_ script: String) throws -> WhisperCppFileTask {
        try WhisperCppFileTask(wavURL: EngineValidation.fixtureURL,
                               executableURL: URL(fileURLWithPath: "/bin/sh"),
                               arguments: ["-c", script, "sidecar-test"])
    }

    func testSharedArgumentsKeepAutoLanguageVADAndRuntimeLibraries() {
        let args = WhisperCppService.arguments(wavURL: EngineValidation.fixtureURL)
        XCTAssertTrue(args.contains("--vad"))
        XCTAssertTrue(args.contains(TranscriptionEngine.wcppVADModelURL.path))
        XCTAssertTrue(args.contains(TranscriptionEngine.wcppModelURL.path))
        XCTAssertEqual(args[args.firstIndex(of: "-l")! + 1], "auto")
        XCTAssertFalse(args.contains("-tr"))
        XCTAssertFalse(args.contains("--translate"))
        XCTAssertEqual(TranscriptionEngine.localEnvironment["DYLD_LIBRARY_PATH"],
                       TranscriptionEngine.wcppURL.deletingLastPathComponent().path)
    }

    func testTimestampParsingRejectsDiagnostics() {
        let segment = WhisperCppFileTask.segment("[00:01:02.340 --> 00:01:05.670]   Merhaba dünya")
        XCTAssertEqual(segment?.end, 65.67)
        XCTAssertEqual(segment?.text, "Merhaba dünya")
        XCTAssertEqual(WhisperCppFileTask.segment("[01:02.340 --> 01:05.670] hi")?.text, "hi")
        XCTAssertNil(WhisperCppFileTask.segment("[warning] not a transcript"))
        XCTAssertNil(WhisperCppFileTask.segment("[bad --> timestamp] not a transcript"))
        XCTAssertNil(WhisperCppFileTask.segment("[00:00 --> 00:NaN] not a transcript"))
    }

    func testStreamsSplitLinesButFinalComesFromOutputFile() async throws {
        let snapshots = Snapshots()
        let runner = try task("""
        printf '[00:00:01.000 --> '
        sleep 0.2
        printf '00:00:02.000]   partial preview\n'
        sleep 0.3
        printf 'Authoritative final text.\n' > "$3.txt"
        """)
        let final = try await runner.run { snapshots.append($0) }
        XCTAssertEqual(final, "Authoritative final text.")
        let values = snapshots.all()
        XCTAssertTrue(values.contains { $0.text == "partial preview" && $0.fraction == 0 })
        XCTAssertEqual(values.last?.text, final)
        XCTAssertEqual(values.last?.fraction, 1)
        XCTAssertTrue(values.dropLast().allSatisfy { $0.fraction == 0 })
    }

    func testFinalTextDoesNotRequireTimestampedStdout() async throws {
        let runner = try task("printf 'Only output file.\\n' > \"$3.txt\"")
        let text = try await runner.run { _ in }
        XCTAssertEqual(text, "Only output file.")
    }

    func testLargeStderrCannotDeadlockAndIsPreservedIncludingLastLine() async throws {
        let runner = try task("""
        i=0
        while [ "$i" -lt 12000 ]; do printf 'diagnostic-line\n' >&2; i=$((i+1)); done
        printf 'FINAL-ERROR\n' >&2
        exit 6
        """)
        do {
            _ = try await runner.run { _ in }
            XCTFail("Expected failure")
        } catch WhisperCppError.processFailed(let exit, let stderr, let signalled) {
            XCTAssertEqual(exit, 6)
            XCTAssertFalse(signalled)
            XCTAssertTrue(stderr.hasSuffix("FINAL-ERROR\n"))
            XCTAssertEqual(stderr.components(separatedBy: "diagnostic-line\n").count - 1, 12000)
        }
    }

    func testSignalFailureIsNotMisreportedAsExitCode() async throws {
        let runner = try task("printf 'signal diagnostic\\n' >&2; kill -ABRT $$")
        do {
            _ = try await runner.run { _ in }
            XCTFail("Expected signal")
        } catch WhisperCppError.processFailed(let exit, let stderr, let signalled) {
            XCTAssertEqual(exit, 6)
            XCTAssertTrue(signalled)
            XCTAssertTrue(stderr.contains("signal diagnostic"))
        }
    }

    func testCancellationBeforeLaunchIsTyped() async throws {
        let runner = try task("exit 99")
        runner.cancel()
        do {
            _ = try await runner.run { _ in }
            XCTFail("Expected cancellation")
        } catch WhisperCppError.cancelled { }
    }

    func testSwiftTaskCancellationReapsSilentChild() async throws {
        let runner = try task("exec /bin/sleep 30")
        let running = Task { try await runner.run { _ in } }
        try await Task.sleep(nanoseconds: 100_000_000)
        running.cancel()
        do {
            _ = try await running.value
            XCTFail("Expected cancellation")
        } catch WhisperCppError.cancelled { }
    }

    func testLaunchFailureDoesNotLeavePipeReaderWaiting() async throws {
        let runner = try WhisperCppFileTask(wavURL: EngineValidation.fixtureURL,
                                           executableURL: URL(fileURLWithPath: "/no-such-sidecar"))
        do {
            _ = try await runner.run { _ in }
            XCTFail("Expected launch failure")
        } catch { XCTAssertFalse(error is CancellationError) }
    }

    func testMissingOutputIsNotAcceptedFromPreview() async throws {
        let runner = try task("printf '[00:00:01.000 --> 00:00:02.000] preview only\\n'")
        do {
            _ = try await runner.run { _ in }
            XCTFail("Expected missing output")
        } catch WhisperCppError.noOutput { }
    }
}
