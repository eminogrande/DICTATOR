import XCTest
@testable import DictateMacCore

final class SpokenLanguageTests: XCTestCase {
    func testUsesDetectedLanguageWithoutRemapping() {
        XCTAssertEqual(SpokenLanguage.locked(detected: "de"), "de")
        XCTAssertEqual(SpokenLanguage.locked(detected: "en"), "en")
        XCTAssertEqual(SpokenLanguage.locked(detected: "tr"), "tr")
        XCTAssertEqual(SpokenLanguage.locked(detected: "FR"), "fr")
    }

    func testIgnoresEmptyDetection() {
        XCTAssertNil(SpokenLanguage.locked(detected: "  "))
    }
}
