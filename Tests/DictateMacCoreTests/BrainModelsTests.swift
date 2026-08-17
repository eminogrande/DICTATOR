import Foundation
import XCTest
@testable import DictateMacCore

final class BrainModelsTests: XCTestCase {
    func testSearchResponseDecodesTokenBoundedResults() throws {
        let data = Data(#"{"query":"font size","results":[{"id":"file:1","type":"file","label":"Design.swift","path":"/repo/Design.swift","score":0.0325,"excerpt":"minimumFontSize = 16","related":[]}]}"#.utf8)
        let response = try JSONDecoder().decode(BrainSearchResponse.self, from: data)
        XCTAssertEqual(response.results.first?.label, "Design.swift")
        XCTAssertEqual(response.results.first?.score, 0.0325)
    }


    func testBrainBrowserSectionsMapToSidecarTypes() {
        XCTAssertEqual(BrainBrowserSection.sidebarSections, [.home, .all, .recording, .transcript, .session, .memory, .document, .project, .file, .function])
        XCTAssertNil(BrainBrowserSection.home.browseType)
        XCTAssertEqual(BrainBrowserSection.all.browseType, "all")
        XCTAssertEqual(BrainBrowserSection.recording.browseType, "recording")
        XCTAssertFalse(BrainBrowserSection.sidebarSections.contains(.search))
    }

    func testManagedRepositoryRefreshDecodesSidecarResult() throws {
        let data = Data(#"{"repositories":{"due":true,"checked":10,"updated":2,"unchanged":7,"failed":1,"entries":[]},"embeddings":null}"#.utf8)
        let response = try JSONDecoder().decode(BrainManagedRefreshResponse.self, from: data)
        XCTAssertEqual(response.repositories.checked, 10)
        XCTAssertEqual(response.repositories.updated, 2)
        XCTAssertEqual(response.repositories.failed, 1)
    }

    func testHermesSyncDecodesImportedCounts() throws {
        let data = Data(#"{"graphPath":"/tmp/graph.json","nodes":12,"edges":4,"nodeTypes":{"memory":2,"session":1},"imported":{"documents":0,"memories":2,"sessions":1,"turns":3}}"#.utf8)
        let response = try JSONDecoder().decode(BrainHermesSyncResponse.self, from: data)
        XCTAssertEqual(response.imported.memories, 2)
        XCTAssertEqual(response.imported.sessions, 1)
        XCTAssertEqual(response.imported.turns, 3)
    }
}
