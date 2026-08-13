import XCTest
@testable import DictateMacCore

final class TranscriptDeliveryTests: XCTestCase {
    func testDeliveryValuesExplainEveryOutcome() {
        XCTAssertEqual(TranscriptDelivery.accessibilityInserted.rawValue, "accessibilityInserted")
        XCTAssertEqual(TranscriptDelivery.pasteShortcutPosted.rawValue, "pasteShortcutPosted")
        XCTAssertEqual(TranscriptDelivery.accessibilityDenied.rawValue, "accessibilityDenied")
        XCTAssertEqual(TranscriptDelivery.targetUnavailable.rawValue, "targetUnavailable")
    }
}
