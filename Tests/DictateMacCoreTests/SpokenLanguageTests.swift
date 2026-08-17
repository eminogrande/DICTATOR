import XCTest
@testable import DictateMacCore

final class SpokenLanguageTests: XCTestCase {
    func testKeepsDetectedGermanAndEnglish() {
        XCTAssertEqual(SpokenLanguage.locked(detected: "de"), "de")
        XCTAssertEqual(SpokenLanguage.locked(detected: "en"), "en")
    }

    func testPicksGermanOrEnglishWhenDetectionIsAnotherLanguage() {
        XCTAssertEqual(
            SpokenLanguage.locked(detected: "fr", probabilities: ["de": -0.2, "en": -1.4, "fr": -0.1]),
            "de"
        )
        XCTAssertEqual(
            SpokenLanguage.locked(detected: "es", probabilities: ["de": -1.8, "en": -0.3]),
            "en"
        )
    }
}
