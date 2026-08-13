import XCTest
@testable import DictateMacCore

final class TranscriptInsertionDecisionTests: XCTestCase {
    func testSuccessfulAccessibilityInsertionFinishesDelivery() {
        XCTAssertEqual(
            TranscriptInsertionDecision.afterAccessibilityResult(0),
            .inserted
        )
    }

    func testFailedAccessibilityInsertionFallsBackToPasteShortcut() {
        XCTAssertEqual(
            TranscriptInsertionDecision.afterAccessibilityResult(-25205),
            .usePasteShortcut
        )
    }
}
