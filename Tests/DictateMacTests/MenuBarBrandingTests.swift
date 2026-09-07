import AppKit
import XCTest
@testable import DictateMac

final class MenuBarBrandingTests: XCTestCase {
    @MainActor
    func testWordmarkStaysCompactOutsideActiveWork() {
        for phase in ["idle", "completed", "failed", "saved"] {
            XCTAssertEqual(DictatorAssets.menuTitle(phase: phase, activityTitle: "FERTIG"), "DICTATOR")
        }
        XCTAssertEqual(DictatorAssets.menuTitle(phase: "recording", activityTitle: "REC 12:34"), "DICTATOR  REC 12:34")
        XCTAssertEqual(DictatorAssets.menuTitle(phase: "transcribing", activityTitle: "TXT 1:23"), "DICTATOR  TXT 1:23")
    }

    @MainActor
    func testNativeTitleAndTemplateAdaptWithoutForcedBlackTint() {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let button = NSButton(title: "", target: nil, action: nil)
            button.appearance = NSAppearance(named: appearance)
            button.contentTintColor = .black // Simulate the old forced-tint regression.
            DictatorAssets.applyMenuBranding(to: button, phase: "idle", activityTitle: "DICTATOR")
            XCTAssertEqual(button.title, "DICTATOR")
            XCTAssertNil(button.contentTintColor)
            XCTAssertEqual(button.image?.isTemplate, true)
            XCTAssertEqual(button.image?.size, NSSize(width: 14, height: 14))
            DictatorAssets.applyMenuBranding(to: button, phase: "recording", activityTitle: "REC 0:03")
            XCTAssertEqual(button.title, "DICTATOR  REC 0:03")
            XCTAssertNil(button.contentTintColor)
            XCTAssertNotNil(button.image)
            XCTAssertEqual(button.image?.isTemplate, false)
        }
    }
}
