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
        rebuildMenu()
        controller.$statusText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)
        controller.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)
        controller.$isLatchedRecordingPublished
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func menuAction() {
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func rebuildMenu() {
        // Rebuild lazily on next open; menu is constructed fresh in menuAction.
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
