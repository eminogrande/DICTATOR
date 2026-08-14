import XCTest
@testable import DictateMacCore

final class AudioSampleMixerTests: XCTestCase {
    func testMixesSystemAudioAtRecordedOffset() {
        XCTAssertEqual(
            AudioSampleMixer.mix(
                microphone: [0.1, 0.2, 0.3, 0.4],
                system: [0.5, 0.6],
                systemOffset: 2
            ),
            [0.1, 0.2, 0.8, 1.0]
        )
    }

    func testKeepsMicrophoneWhenSystemAudioIsUnavailable() {
        XCTAssertEqual(
            AudioSampleMixer.mix(microphone: [0.1, -0.2], system: [], systemOffset: 0),
            [0.1, -0.2]
        )
    }

    func testExtendsRecordingForLaterSystemAudio() {
        XCTAssertEqual(
            AudioSampleMixer.mix(microphone: [0.2], system: [0.3, 0.4], systemOffset: 1),
            [0.2, 0.3, 0.4]
        )
    }
}
