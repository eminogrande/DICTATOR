import XCTest
@testable import DictateMacCore

final class MeetingToggleTests: XCTestCase {
    func testIdleStartsLatchedMeeting() {
        XCTAssertEqual(MeetingToggle.result(isRecording: false, startedByHold: false), .start)
    }

    func testHoldPlusRKeepsRecording() {
        XCTAssertEqual(MeetingToggle.result(isRecording: true, startedByHold: true), .latch)
    }

    func testSecondFnRStopsLatchedRecording() {
        XCTAssertEqual(MeetingToggle.result(isRecording: true, startedByHold: false), .stop)
    }
}
