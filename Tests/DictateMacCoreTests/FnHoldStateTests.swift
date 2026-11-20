import XCTest
@testable import DictateMacCore

final class FnHoldStateTests: XCTestCase {
    func testHoldStartsAndReleaseStops() {
        var state = FnHoldState()

        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: true, at: 10), .start)
        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: false, at: 10.6), .stop)
    }

    func testDuplicateEventsDoNothing() {
        var state = FnHoldState()

        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: true, at: 10), .start)
        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: true, at: 10.1), .none)
        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: false, at: 10.6), .stop)
        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: false, at: 10.7), .none)
    }

    func testOtherModifierChangesDoNothing() {
        var state = FnHoldState()

        XCTAssertEqual(state.handle(keyCode: 58, functionFlag: true, at: 10), .none)
        XCTAssertEqual(state.handle(keyCode: 58, functionFlag: false, at: 10.1), .none)
    }

    func testDoubleTapLatchesAndNextPressStops() {
        var state = FnHoldState()

        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: true, at: 10), .start)
        // Tap release defers the stop for the double-tap window.
        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: false, at: 10.1), .none)
        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: true, at: 10.2), .latch)
        XCTAssertTrue(state.isLatched)
        // Releasing the second tap must not stop the latched take.
        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: false, at: 10.25), .none)
        XCTAssertEqual(state.handleDoubleTapTimeout(at: 10.9), .none)
        XCTAssertTrue(state.isLatched)
        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: true, at: 12), .stop)
        XCTAssertFalse(state.isLatched)
        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: false, at: 12.05), .none)
        XCTAssertEqual(state.handleDoubleTapTimeout(at: 12.9), .none)
    }

    func testSingleTapStopsWhenWindowExpires() {
        var state = FnHoldState()

        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: true, at: 10), .start)
        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: false, at: 10.1), .none)
        XCTAssertEqual(state.handleDoubleTapTimeout(at: 10.2), .none)
        XCTAssertEqual(state.handleDoubleTapTimeout(at: 10.5), .stop)
        XCTAssertEqual(state.handleDoubleTapTimeout(at: 10.6), .none)
    }

    func testDoubleTapWindowExpiresBeforeLateSecondTapRecordsAgain() {
        var state = FnHoldState()

        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: true, at: 10), .start)
        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: false, at: 10.1), .none)
        XCTAssertEqual(state.handleDoubleTapTimeout(at: 10.5), .stop)
        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: true, at: 10.6), .start)
    }

    func testHoldIsNotDeferred() {
        var state = FnHoldState()

        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: true, at: 10), .start)
        XCTAssertNil(state.secondsUntilDoubleTapTimeout)
        XCTAssertEqual(state.handle(keyCode: 63, functionFlag: false, at: 10.5), .stop)
        XCTAssertNil(state.secondsUntilDoubleTapTimeout)
    }
}
