import XCTest
@testable import DictateMacCore

final class TranscriptionHUDPresentationTests: XCTestCase {
    func testShowsUsefulRecallBeforeFirstWord() {
        let presentation = TranscriptionHUDPresentation.make(
            isVisible: true,
            title: "Zuletzt wichtig",
            recall: "DICTATOR: Streaming geplant. Nächster Schritt: echter Live-Text.",
            confirmed: "",
            provisional: ""
        )
        XCTAssertEqual(
            presentation,
            TranscriptionHUDPresentation(
                title: "Zuletzt wichtig",
                recall: "DICTATOR: Streaming geplant. Nächster Schritt: echter Live-Text.",
                confirmed: "",
                provisional: ""
            )
        )
        XCTAssertFalse(presentation?.hasTranscript ?? true)
    }

    func testShowsConfirmedAndProvisionalLiveText() {
        let presentation = TranscriptionHUDPresentation.make(
            isVisible: true,
            title: "Live transcript",
            recall: "Recent context",
            confirmed: "This part is stable.",
            provisional: "This may still change"
        )
        XCTAssertTrue(presentation?.hasTranscript ?? false)
        XCTAssertEqual(presentation?.confirmed, "This part is stable.")
        XCTAssertEqual(presentation?.provisional, "This may still change")
    }

    func testEmptyRecallUsesUsefulLoadingCopy() {
        XCTAssertEqual(
            TranscriptionHUDPresentation.make(
                isVisible: true,
                title: "Zuletzt wichtig",
                recall: "",
                confirmed: "",
                provisional: ""
            )?.recall,
            "Loading useful recent context…"
        )
    }

    func testIdleHasNoHUD() {
        XCTAssertNil(
            TranscriptionHUDPresentation.make(
                isVisible: false,
                title: "stale",
                recall: "stale",
                confirmed: "stale",
                provisional: "stale"
            )
        )
    }
}
