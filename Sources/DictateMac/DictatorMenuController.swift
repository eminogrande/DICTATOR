import AppKit
import DictateMacCore
import Combine
import OSLog

@MainActor
final class DictatorMenuController: NSObject {
    private let statusItem: NSStatusItem
    private let logger = Logger(subsystem: "de.emin.DictateMac", category: "Menu")
    private var cancellables: Set<AnyCancellable> = []
    private let openBrain: () -> Void
    private let openArchive: () -> Void
    private let openSettings: () -> Void
    private weak var controller: DictationController?

    init(controller: DictationController,
         openBrain: @escaping () -> Void,
         openArchive: @escaping () -> Void,
         openSettings: @escaping () -> Void) {
        self.controller = controller
        self.openBrain = openBrain
        self.openArchive = openArchive
        self.openSettings = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = DictatorAssets.menuIcon
            button.imagePosition = .imageOnly
            button.toolTip = "DICTATOR"
            button.target = self
            button.action = #selector(menuAction)
            button.sendAction(on: [.leftMouseUp])
        }
        controller.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording in self?.updateIcon(isRecording: recording) }
            .store(in: &cancellables)
        controller.$isLatchedRecordingPublished
            .receive(on: DispatchQueue.main)
            .sink { [weak self] latched in self?.updateIcon(isRecording: latched) }
            .store(in: &cancellables)
        updateIcon(isRecording: controller.isRecording)
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func updateIcon(isRecording: Bool) {
        guard let button = statusItem.button else { return }
        if isRecording {
            button.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop recording")
            button.contentTintColor = .systemRed
            button.toolTip = "Recording — click to stop"
        } else {
            button.image = DictatorAssets.menuIcon
            button.contentTintColor = nil
            button.toolTip = "DICTATOR"
        }
    }

    @objc private func menuAction() {
        // QuickTime-style: while recording, a click on the icon stops the take directly.
        if controller?.isRecording == true {
            controller?.toggleRecording()
            return
        }
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let recordTitle = controller?.isLatchedRecording == true
            ? "Stop Meeting Recording"
            : "Record Meeting"
        let recordItem = menu.addItem(withTitle: recordTitle, action: #selector(toggleMeeting), keyEquivalent: "r")
        recordItem.target = self
        recordItem.keyEquivalentModifierMask = .function

        let recentItem = menu.addItem(withTitle: "Recent Dictations", action: #selector(openArchiveAction), keyEquivalent: "")
        recentItem.target = self

        menu.addItem(.separator())

        let brainItem = menu.addItem(withTitle: "Open Brain", action: #selector(openBrainAction), keyEquivalent: "")
        brainItem.target = self

        menu.addItem(.separator())

        let settingsItem = menu.addItem(withTitle: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self

        let quitItem = menu.addItem(withTitle: "Quit DICTATOR", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self

        return menu
    }

    @objc private func toggleMeeting() {
        controller?.toggleRecording()
    }

    @objc private func openArchiveAction() {
        openArchive()
    }

    @objc private func openBrainAction() {
        openBrain()
    }

    @objc private func openSettingsAction() {
        openSettings()
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}
