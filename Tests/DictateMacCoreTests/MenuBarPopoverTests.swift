import XCTest
@testable import DictateMacCore

final class MenuBarPopoverTests: XCTestCase {
    func testStatusButtonShowsWhenClosedAndClosesWhenOpen() {
        XCTAssertEqual(StatusPopoverAction.next(isShown: false), .show)
        XCTAssertEqual(StatusPopoverAction.next(isShown: true), .close)
    }
}
