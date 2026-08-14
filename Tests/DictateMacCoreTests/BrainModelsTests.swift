import Foundation
import XCTest
@testable import DictateMacCore

final class BrainModelsTests: XCTestCase {
    func testSearchResponseDecodesTokenBoundedResults() throws {
        let data = Data(#"{"query":"font size","results":[{"id":"file:1","type":"file","label":"Design.swift","path":"/repo/Design.swift","score":7,"excerpt":"minimumFontSize = 16","related":[]}]}"#.utf8)
        let response = try JSONDecoder().decode(BrainSearchResponse.self, from: data)
        XCTAssertEqual(response.results.first?.label, "Design.swift")
        XCTAssertEqual(response.results.first?.score, 7)
    }

    func testProgressFramesUseOnlyPreviousTranscriptWords() {
        let source = "minimum font size should always be sixteen pixels"
        let frames = TranscriptionProgressFrames.make(from: source)
        XCTAssertTrue(frames.contains("..."))
        XCTAssertTrue(frames.contains { $0.contains("minimum font size") })
        let allowed = Set(source.split(separator: " ").map(String.init))
        for frame in frames where frame.contains("“") {
            let words = frame.trimmingCharacters(in: CharacterSet(charactersIn: "“”")).split(separator: " ").map(String.init)
            XCTAssertTrue(words.allSatisfy(allowed.contains))
        }
    }
}
