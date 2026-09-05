import XCTest
@testable import DictateMacCore

final class TranscriptionHUDPresentationTests: XCTestCase {
    func testStartsWithoutRecallOrPlaceholderCopy() {
        let presentation = TranscriptionHUDPresentation.make(
            isVisible: true,
            title: "",
            confirmed: "",
            provisional: ""
        )
        XCTAssertEqual(
            presentation,
            TranscriptionHUDPresentation(
                title: "Loading…",
                confirmed: "",
                provisional: ""
            )
        )
        XCTAssertFalse(presentation?.hasTranscript ?? true)
    }

    func testShowsConfirmedAndProvisionalLiveText() {
        let presentation = TranscriptionHUDPresentation.make(
            isVisible: true,
            title: "",
            confirmed: "This part is stable.",
            provisional: "This may still change"
        )
        XCTAssertTrue(presentation?.hasTranscript ?? false)
        XCTAssertEqual(presentation?.confirmed, "This part is stable.")
        XCTAssertEqual(presentation?.provisional, "This may still change")
    }

    func testPreservesExplicitProcessingPhase() {
        let presentation = TranscriptionHUDPresentation.make(
            isVisible: true,
            title: "Creating final transcript",
            confirmed: "Complete spoken text",
            provisional: ""
        )
        XCTAssertEqual(presentation?.title, "Creating final transcript")
    }

    func testIdleHasNoHUD() {
        XCTAssertNil(
            TranscriptionHUDPresentation.make(
                isVisible: false,
                title: "stale",
                confirmed: "stale",
                provisional: "stale"
            )
        )
    }
}
