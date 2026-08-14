import XCTest
@testable import DictateMacCore

final class TranscriptionHUDPresentationTests: XCTestCase {
    func testTranscribingProducesVisibleLocalProgress() {
        XCTAssertEqual(
            TranscriptionHUDPresentation.make(
                isTranscribing: true,
                preview: "......"
            ),
            TranscriptionHUDPresentation(
                title: "Transcribing locally",
                detail: "......"
            )
        )
    }

    func testTranscribingFallsBackToImmediateDots() {
        XCTAssertEqual(
            TranscriptionHUDPresentation.make(
                isTranscribing: true,
                preview: ""
            )?.detail,
            "..."
        )
    }

    func testIdleHasNoHUD() {
        XCTAssertNil(
            TranscriptionHUDPresentation.make(
                isTranscribing: false,
                preview: "stale text"
            )
        )
    }
}
