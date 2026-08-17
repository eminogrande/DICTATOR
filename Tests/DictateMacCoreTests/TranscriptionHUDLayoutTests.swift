import XCTest
@testable import DictateMacCore

final class TranscriptionHUDLayoutTests: XCTestCase {
    func testLongerTranscriptExpandsPanelDownward() {
        let short = TranscriptionHUDLayout.make(
            textHeight: 60,
            hasHeader: true,
            screenHeight: 1_000
        )
        let long = TranscriptionHUDLayout.make(
            textHeight: 420,
            hasHeader: true,
            screenHeight: 1_000
        )
        XCTAssertGreaterThan(long.panelHeight, short.panelHeight)
        XCTAssertFalse(long.textOverflows)
        XCTAssertEqual(long.textViewportHeight, 420)
    }

    func testPanelUsesVisibleScreenUntilThirtySixPointMargin() {
        let layout = TranscriptionHUDLayout.make(
            textHeight: 2_000,
            hasHeader: true,
            screenHeight: 1_000
        )
        XCTAssertEqual(layout.panelHeight, 964)
        XCTAssertEqual(layout.textViewportHeight, 812)
        XCTAssertTrue(layout.textOverflows)
    }

    func testWaveformHeaderHasDedicatedHeight() {
        let layout = TranscriptionHUDLayout.make(
            textHeight: 0,
            hasHeader: true,
            screenHeight: 1_000
        )
        XCTAssertEqual(layout.panelHeight, 136)
        XCTAssertEqual(layout.textViewportHeight, 0)
        XCTAssertFalse(layout.textOverflows)
    }

    func testFittingTextNeverScrollsBehindHeader() {
        let layout = TranscriptionHUDLayout.make(
            textHeight: 240,
            hasHeader: true,
            screenHeight: 1_000
        )
        XCTAssertEqual(layout.textViewportHeight, 240)
        XCTAssertFalse(layout.textOverflows)
    }

    func testFinalizingFooterSitsBelowTranscript() {
        let layout = TranscriptionHUDLayout.make(
            textHeight: 240,
            hasHeader: true,
            hasFooter: true,
            screenHeight: 1_000
        )
        XCTAssertEqual(layout.textViewportHeight, 240)
        XCTAssertEqual(layout.panelHeight, 460)
        XCTAssertFalse(layout.textOverflows)
    }
}
