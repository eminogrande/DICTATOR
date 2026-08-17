import XCTest
@testable import DictateMacCore

final class LiveTranscriptTests: XCTestCase {
    func testSeparatesConfirmedAndCurrentProvisionalText() {
        XCTAssertEqual(
            LiveTranscriptText.make(
                confirmedSegments: ["Hello world."],
                unconfirmedSegments: ["Old hypothesis"],
                currentText: "This is the current hypothesis"
            ),
            LiveTranscriptSnapshot(
                confirmed: "Hello world.",
                provisional: "This is the current hypothesis"
            )
        )
    }

    func testUsesUnconfirmedSegmentsBetweenDecoderUpdates() {
        XCTAssertEqual(
            LiveTranscriptText.make(
                confirmedSegments: ["Hallo."],
                unconfirmedSegments: ["Das ist Nuri."],
                currentText: ""
            ).provisional,
            "Das ist Nuri."
        )
    }

    func testRemovesRepeatedConfirmedPrefixFromCurrentHypothesis() {
        XCTAssertEqual(
            LiveTranscriptText.make(
                confirmedSegments: ["We already finished this part."],
                unconfirmedSegments: [],
                currentText: "We already finished this part. Only this is still changing"
            ).provisional,
            "Only this is still changing"
        )
    }

    func testNeverDisplaysWhisperWaitingMarkerAsSpeech() {
        XCTAssertEqual(
            LiveTranscriptText.make(
                confirmedSegments: [],
                unconfirmedSegments: [],
                currentText: "Waiting for speech..."
            ),
            LiveTranscriptSnapshot(confirmed: "", provisional: "")
        )
    }

    func testDeliveryTranscriptUsesLiveTextWithoutASecondPass() {
        XCTAssertEqual(
            LiveTranscriptText.deliveryTranscript(confirmed: "Das ist Nuri.", provisional: "weiter"),
            "Das ist Nuri. weiter"
        )
        XCTAssertEqual(
            LiveTranscriptText.deliveryTranscript(confirmed: "  ", provisional: ""),
            ""
        )
    }
}
