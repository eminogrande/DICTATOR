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

    func testProgressFramesTypeAndDeleteOnlyPreviousTranscriptText() {
        let source = "minimum font size should always be sixteen pixels"
        let frames = TranscriptionProgressFrames.make(from: source)
        XCTAssertTrue(frames.contains("..."))
        XCTAssertTrue(frames.contains("“m”"))
        XCTAssertTrue(frames.contains { $0.contains("minimum font size") })

        let fragments = frames
            .filter { $0.hasPrefix("“") }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "“”")) }
        XCTAssertTrue(fragments.allSatisfy(source.contains))

        let longestIndex = fragments.indices.max(by: { fragments[$0].count < fragments[$1].count })!
        XCTAssertTrue(fragments[longestIndex...].dropFirst().contains { $0.count < fragments[longestIndex].count })
    }
}
