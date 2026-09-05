import XCTest
@testable import DictateMacCore

final class TranscriptionReadinessTests: XCTestCase {
    func testLoadingReadyFailureAndSelectionGenerations() {
        var r = TranscriptionReadiness(engineID: "fast")
        XCTAssertFalse(r.permitsRecording(engineID: "fast", busy: false, recording: false))
        let old = r.begin(engineID: "fast")
        let other = r.begin(engineID: "quality")
        let current = r.begin(engineID: "fast")
        r.complete(old)
        r.complete(other)
        XCTAssertEqual(r.phase, .loading)
        r.complete(current)
        XCTAssertTrue(r.permitsRecording(engineID: "fast", busy: false, recording: false))
        XCTAssertFalse(r.permitsRecording(engineID: "quality", busy: false, recording: false))
        XCTAssertFalse(r.permitsRecording(engineID: "fast", busy: true, recording: false))
        XCTAssertFalse(r.permitsRecording(engineID: "fast", busy: false, recording: true))
        let retry = r.begin(engineID: "fast")
        r.complete(retry, error: "Timed out")
        r.complete(retry) // late completion must not undo the deadline
        XCTAssertEqual(r.error, "Timed out")
        XCTAssertFalse(r.status(engineName: "Fast").isEmpty)
    }

    func testAllVisibleHUDStatesContainExplicitStatusEvenWithoutAudioOrText() {
        for recording in [false, true] {
            for title in ["", " \n", "Recording — live preview unavailable", "Transcribing locally, please wait…"] {
                let p = TranscriptionHUDPresentation.make(isVisible: true, isRecording: recording,
                                                         title: title, confirmed: "", provisional: "")!
                XCTAssertFalse(p.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertFalse(p.hasTranscript)
                let layout = TranscriptionHUDLayout.make(textHeight: 0, hasHeader: false,
                                                        hasFooter: !p.title.isEmpty, screenHeight: 900)
                XCTAssertGreaterThanOrEqual(layout.panelHeight, TranscriptionHUDLayout.footerHeight)
            }
        }
    }

    func testReadinessProbeTimeoutAndFastExitAreHandled() async throws {
        let result = try await SubprocessCapture.run(executableURL: URL(fileURLWithPath: "/usr/bin/true"), arguments: [], timeout: 2)
        XCTAssertEqual(result.terminationStatus, 0)
        do {
            _ = try await SubprocessCapture.run(executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], timeout: 0.05)
            XCTFail("Expected bounded probe")
        } catch { XCTAssertTrue(error is SubprocessTimeout) }
    }
}
