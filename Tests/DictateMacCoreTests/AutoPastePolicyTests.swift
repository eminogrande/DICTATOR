import XCTest
@testable import DictateMacCore

final class AutoPastePolicyTests: XCTestCase {
    func testEnabledPolicyRequestsAutomaticInsertion() {
        XCTAssertEqual(AutoPastePolicy.deliveryMode(isEnabled: true), .automaticInsert)
    }

    func testDisabledPolicyKeepsClipboardOnly() {
        XCTAssertEqual(AutoPastePolicy.deliveryMode(isEnabled: false), .clipboardOnly)
    }
}
