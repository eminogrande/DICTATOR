import XCTest
@testable import DictateMacCore

final class TranscriptionHUDLayoutTests: XCTestCase {
    func testLongerTranscriptExpandsWithinCompactLimit() {
        let short = TranscriptionHUDLayout.make(textHeight: 24, hasHeader: true, screenHeight: 1_000)
        let long = TranscriptionHUDLayout.make(textHeight: 60, hasHeader: true, screenHeight: 1_000)
        XCTAssertGreaterThan(long.panelHeight, short.panelHeight)
        XCTAssertFalse(long.textOverflows)
        XCTAssertEqual(long.textViewportHeight, 60)
    }

    func testPanelNeverExceedsCompactHeight() {
        let layout = TranscriptionHUDLayout.make(textHeight: 2_000, hasHeader: true, screenHeight: 1_000)
        XCTAssertEqual(layout.panelHeight, 140)
        XCTAssertEqual(layout.textViewportHeight, 102)
        XCTAssertTrue(layout.textOverflows)
    }

    func testWaveformHeaderIsCompact() {
        let layout = TranscriptionHUDLayout.make(textHeight: 0, hasHeader: true, screenHeight: 1_000)
        XCTAssertEqual(layout.panelHeight, 34)
        XCTAssertEqual(layout.textViewportHeight, 0)
        XCTAssertFalse(layout.textOverflows)
    }

    func testFittingTextNeverScrollsBehindHeader() {
        let layout = TranscriptionHUDLayout.make(textHeight: 60, hasHeader: true, screenHeight: 1_000)
        XCTAssertEqual(layout.textViewportHeight, 60)
        XCTAssertFalse(layout.textOverflows)
    }

    func testFinalizingFooterSitsBelowTranscript() {
        let layout = TranscriptionHUDLayout.make(textHeight: 60, hasHeader: true, hasFooter: true, screenHeight: 1_000)
        XCTAssertEqual(layout.textViewportHeight, 60)
        XCTAssertEqual(layout.panelHeight, 126)
        XCTAssertFalse(layout.textOverflows)
    }
}
