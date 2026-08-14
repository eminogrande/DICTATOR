import XCTest
@testable import DictateMacCore

final class LiveAudioProgressTests: XCTestCase {
    func testFormatsDecodedPositionAndCurrentAudioLength() {
        let progress = LiveAudioProgress(
            waveform: [0.1, 0.9],
            audioDuration: 125.8,
            transcribedPosition: 62.4
        )

        XCTAssertEqual(progress.timecode, "01:02 / 02:05")
        XCTAssertEqual(progress.fractionTranscribed, 62.4 / 125.8, accuracy: 0.0001)
    }

    func testClampsPositionToRecordedAudio() {
        let progress = LiveAudioProgress(
            waveform: [],
            audioDuration: 5,
            transcribedPosition: 9
        )

        XCTAssertEqual(progress.transcribedPosition, 5)
        XCTAssertEqual(progress.fractionTranscribed, 1)
    }

    func testDownsampleKeepsPeakDetailAndBoundsValues() {
        XCTAssertEqual(
            WaveformEnvelope.downsample([-1, 0.2, 0.9, 2], maximumCount: 2),
            [0.2, 1]
        )
    }
}
