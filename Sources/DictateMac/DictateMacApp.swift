import AppKit
import DictateMacCore
import OSLog
import SwiftUI

@main
struct DictateMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var dictationController = DictationController()
    private var duplicateInstance = false
    private let brainController = BrainController()
    private var transcriptionHUD: TranscriptionHUDController?
    private var menuController: DictatorMenuController?
    private var brainWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second copy must never reinterpret another instance's active sessions.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            duplicateInstance = true
            NSApplication.shared.terminate(nil)
            return
        }
        NSApplication.shared.setActivationPolicy(.regular)
        transcriptionHUD = TranscriptionHUDController(controller: dictationController)
        menuController = DictatorMenuController(
            controller: dictationController,
            openLibrary: { [weak self] in self?.showSettings() },
            openPreferences: { [weak self] in self?.showPreferences() }
        )
        // Show a window at launch so the app visibly "opens".
        showSettings()
        if let menu = NSApplication.shared.mainMenu { wirePreferencesCommand(menu) }
    }

    private func wirePreferencesCommand(_ menu: NSMenu) {
        for item in menu.items {
            if item.keyEquivalent == "," {
                item.target = self
                item.action = #selector(showPreferences)
                item.title = "Einstellungen…"
            }
            if let submenu = item.submenu { wirePreferencesCommand(submenu) }
        }
    }

    @objc private func showPreferences() {
        showSettings()
        NotificationCenter.default.post(name: Notification.Name("DICTATORShowPreferences"), object: nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if duplicateInstance { return .terminateNow }
        guard dictationController.hasActiveWork else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "DICTATOR is still working"
        alert.informativeText = dictationController.isRecording
            ? "Stop the recording first so its audio is safely saved. Closing the window keeps recording."
            : "Wait for transcription or stop it from Sessions. Closing the window keeps it running."
        alert.addButton(withTitle: "Keep working")
        alert.runModal()
        return .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func showBrain() {
        let window: NSWindow
        if let brainWindow {
            window = brainWindow
        } else {
            let hostingController = NSHostingController(rootView: BrainView(controller: brainController))
            let created = NSWindow(contentViewController: hostingController)
            created.title = "DICTATOR Brain"
            created.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            created.setContentSize(NSSize(width: 1_080, height: 700))
            created.minSize = NSSize(width: 1_080, height: 700)
            created.isReleasedWhenClosed = false
            created.center()
            brainWindow = created
            window = created
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func showSettings() {
        let window: NSWindow
        if let settingsWindow {
            window = settingsWindow
        } else {
            let hostingController = NSHostingController(rootView: SettingsView(
                controller: dictationController, openBrain: { [weak self] in self?.showBrain() }
            ))
            let created = NSWindow(contentViewController: hostingController)
            created.title = "DICTATOR"
            created.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            created.collectionBehavior.insert(.fullScreenPrimary)
            created.titlebarAppearsTransparent = true
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            created.setContentSize(NSSize(width: min(1180, screen.width - 60), height: min(780, screen.height - 60)))
            created.contentMinSize = NSSize(width: 900, height: 560)
            created.setFrameAutosaveName("DICTATORLibraryWindow")
            created.isReleasedWhenClosed = false
            created.center()
            settingsWindow = created
            window = created
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
