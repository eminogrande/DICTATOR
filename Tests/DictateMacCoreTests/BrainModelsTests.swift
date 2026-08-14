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


    func testBrainBrowserSectionsMapToSidecarTypes() {
        XCTAssertEqual(BrainBrowserSection.sidebarSections, [.home, .all, .recording, .transcript, .session, .memory, .document, .project, .file, .function])
        XCTAssertNil(BrainBrowserSection.home.browseType)
        XCTAssertEqual(BrainBrowserSection.all.browseType, "all")
        XCTAssertEqual(BrainBrowserSection.recording.browseType, "recording")
        XCTAssertFalse(BrainBrowserSection.sidebarSections.contains(.search))
    }
}
