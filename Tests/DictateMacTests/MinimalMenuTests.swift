import AppKit
import DictateMacCore
import XCTest
@testable import DictateMac

final class MinimalMenuTests: XCTestCase {
    @MainActor
    private func controller() throws -> DictationController {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DICTATOR-menu-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let suite = "DICTATOR-menu-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return DictationController(startServices: false, defaults: defaults,
                                   readinessValidator: { _ in }, archiveStore: try ArchiveStore(rootURL: root))
    }

    @MainActor
    func testFiveDirectActionsNoSubmenusAndSeparatePreferences() throws {
        let c = try controller()
        var library = 0
        var preferences = 0
        let menu = DictatorMenuController(controller: c, openLibrary: { library += 1 }, openPreferences: { preferences += 1 })
        let actions = menu.menu.items.filter { !$0.isHidden && !$0.isSeparatorItem && $0.action != nil }
        XCTAssertEqual(actions.map(\.title), ["Aufnahme starten", "Datei importieren…", "Aufnahmen öffnen", "Einstellungen…", "DICTATOR beenden"])
        XCTAssertTrue(menu.menu.items.allSatisfy { $0.submenu == nil })
        XCTAssertTrue(actions[0].isEnabled, "Meeting audio is available even before model readiness")
        XCTAssertEqual(actions[1].isEnabled, c.canTranscribeFile, "Preserve the controller’s import readiness rules")
        XCTAssertTrue(actions[0].keyEquivalent.isEmpty, "AppKit cannot represent Fn; do not accidentally bind a bare R")
        for index in [2, 3] {
            XCTAssertTrue(NSApp.sendAction(actions[index].action!, to: actions[index].target, from: actions[index]))
        }
        XCTAssertEqual(library, 1)
        XCTAssertEqual(preferences, 1)
        XCTAssertEqual(actions[3].keyEquivalent, ",")
        XCTAssertEqual(actions[3].keyEquivalentModifierMask, .command)
    }

    @MainActor
    func testStatusShrinksAndNeverContainsTranscriptOrRawErrorPanel() throws {
        let c = try controller()
        let view = MenuSessionActivityView()
        view.update(controller: c)
        XCTAssertEqual(view.frame.size, NSSize(width: 280, height: 56))
        XCTAssertFalse(view.subviews.contains { $0 is NSScrollView || $0 is NSTextView })
        XCTAssertTrue(view.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Diktieren wird vorbereitet" })
        view.layoutStatus(recording: true)
        XCTAssertEqual(view.frame.height, 100)
        XCTAssertEqual(view.subviews.filter { $0 is NSProgressIndicator && !$0.isHidden }.count, 2)
        for child in view.subviews where !child.isHidden {
            XCTAssertFalse(child.frame.isEmpty)
            XCTAssertTrue(view.bounds.contains(child.frame), "Visible controls must fit without clipping")
        }
        view.layoutStatus(recording: false)
        XCTAssertEqual(view.frame.height, 56)
        XCTAssertTrue(view.subviews.filter { $0 is NSProgressIndicator }.allSatisfy(\.isHidden))
        XCTAssertEqual(MenuSessionActivityView.sourceLabel("Listening"), "Wartet auf Ton")
        XCTAssertEqual(MenuSessionActivityView.sourceLabel("Receiving audio"), "Signal da")
        XCTAssertEqual(MenuSessionActivityView.sourceLabel("No audio yet"), "Noch kein Signal")
        XCTAssertEqual(MenuSessionActivityView.sourceLabel("Permission denied with a lengthy framework error"), "Nicht verfügbar")
    }

    /// Opt-in real native popup capture, no microphone, hotkey service or user archive.
    @MainActor
    func testNativeMenuVisualQA() async throws {
        guard let destination = ProcessInfo.processInfo.environment["DICTATOR_MENU_VISUAL_QA"] else {
            throw XCTSkip("Set DICTATOR_MENU_VISUAL_QA to capture isolated native menu previews")
        }
        try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
        let c = try controller()
        c.refreshReadiness()
        for _ in 0..<300 {
            if !c.readiness.isLoading { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(c.canStartDictation)
        let menu = DictatorMenuController(controller: c, openLibrary: {}, openPreferences: {})
        let original = NSApp.appearance
        defer { NSApp.appearance = original }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            let capture = Timer(timeInterval: 0.8, repeats: false) { _ in
                MainActor.assumeIsolated {
                    defer { menu.menu.cancelTrackingWithoutAnimation() }
                    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                    guard let window = windows.first(where: {
                        ($0[kCGWindowOwnerPID as String] as? Int32) == ProcessInfo.processInfo.processIdentifier &&
                        ($0[kCGWindowLayer as String] as? Int ?? 0) > 0 &&
                        ($0[kCGWindowBounds as String] as? [String: CGFloat])?["Height"] ?? 0 > 100
                    }), let id = window[kCGWindowNumber as String] as? Int else {
                        XCTFail("Native popup window not found"); return
                    }
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    task.arguments = ["-x", "-l", String(id), destination + "/menu-" + name + ".png"]
                    do { try task.run(); task.waitUntilExit(); XCTAssertEqual(task.terminationStatus, 0) }
                    catch { XCTFail("Capture failed: \(error)") }
                    print("NATIVE_MENU_CAPTURE", name, window[kCGWindowBounds as String] ?? "")
                }
            }
            RunLoop.main.add(capture, forMode: .common)
            let screen = NSScreen.main!.visibleFrame
            menu.menu.popUp(positioning: nil, at: NSPoint(x: screen.minX + 350, y: screen.maxY - 120), in: nil)
            capture.invalidate()
            XCTAssertTrue(FileManager.default.fileExists(atPath: destination + "/menu-" + name + ".png"))
        }
    }
}
