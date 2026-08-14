import XCTest
@testable import DictateMacCore

final class TranscriptionHUDLayoutTests: XCTestCase {
    func testLongerTranscriptExpandsPanelDownward() {
        let short = TranscriptionHUDLayout.height(
            textHeight: 60,
            hasAudio: true,
            hasTitle: false,
            screenHeight: 1_000
        )
        let long = TranscriptionHUDLayout.height(
            textHeight: 420,
            hasAudio: true,
            hasTitle: false,
            screenHeight: 1_000
        )
        XCTAssertGreaterThan(long, short)
    }

    func testPanelUsesVisibleScreenUntilThirtySixPointMargin() {
        XCTAssertEqual(
            TranscriptionHUDLayout.height(
                textHeight: 2_000,
                hasAudio: true,
                hasTitle: true,
                screenHeight: 1_000
            ),
            964
        )
    }

    func testWaveformOnlyKeepsCompactMinimum() {
        XCTAssertEqual(
            TranscriptionHUDLayout.height(
                textHeight: 0,
                hasAudio: true,
                hasTitle: false,
                screenHeight: 1_000
            ),
            128
        )
    }
}
