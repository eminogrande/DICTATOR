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
    private let dictationController = DictationController()
    private let brainController = BrainController()
    private var transcriptionHUD: TranscriptionHUDController?
    private var menuController: DictatorMenuController?
    private var brainWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        transcriptionHUD = TranscriptionHUDController(controller: dictationController)
        menuController = DictatorMenuController(
            controller: dictationController,
            openBrain: { [weak self] in self?.showBrain() },
            openArchive: { [weak self] in self?.dictationController.openArchive() },
            openSettings: { [weak self] in self?.showSettings() }
        )
        // Show a window at launch so the app visibly "opens".
        showSettings()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
            let hostingController = NSHostingController(rootView: SettingsView(controller: dictationController))
            let created = NSWindow(contentViewController: hostingController)
            created.title = "DICTATOR Settings"
            created.styleMask = [.titled, .closable, .miniaturizable]
            created.setContentSize(NSSize(width: 540, height: 640))
            created.isReleasedWhenClosed = false
            created.center()
            settingsWindow = created
            window = created
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
