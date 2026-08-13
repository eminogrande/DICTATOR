import XCTest
@testable import DictateMacCore

final class AutoPasteStrategyTests: XCTestCase {
    func testAutomaticInsertUsesPasteShortcutBeforeAccessibilityMutation() {
        XCTAssertEqual(AutoPasteStrategy.steps(for: .automaticInsert), [.pasteShortcut, .accessibilityFallback])
    }

    func testClipboardOnlyDoesNotAttemptInsertion() {
        XCTAssertEqual(AutoPasteStrategy.steps(for: .clipboardOnly), [])
    }
}
