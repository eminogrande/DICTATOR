import XCTest
@testable import DictateMacCore

final class FnHoldStateTests: XCTestCase {
    func testPressStartsAndReleaseStops() {
        var state = FnHoldState()

        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: true), .start)
        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: false), .stop)
    }

    func testDuplicateEventsDoNothing() {
        var state = FnHoldState()

        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: true), .start)
        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: true), .none)
        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: false), .stop)
        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: false), .none)
    }

    func testOtherModifierChangesDoNothing() {
        var state = FnHoldState()

        XCTAssertEqual(state.handle(keyCode: 58, functionFlag: true), .none)
        XCTAssertEqual(state.handle(keyCode: 58, functionFlag: false), .none)
    }
}
