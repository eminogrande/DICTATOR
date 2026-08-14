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
    private var statusBar: StatusBarController?
    private var brainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        transcriptionHUD = TranscriptionHUDController(controller: dictationController)
        statusBar = StatusBarController(controller: dictationController) { [weak self] in
            self?.showBrain()
        }
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
}

@MainActor
private final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let logger = Logger(subsystem: "de.emin.DictateMac", category: "StatusBar")

    init(controller: DictationController, openBrain: @escaping () -> Void) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 480, height: 720)
        popover.contentViewController = NSHostingController(
            rootView: DictationMenu(controller: controller, openBrain: openBrain)
        )

        if let button = statusItem.button {
            button.image = DictatorAssets.menuIcon
            button.imagePosition = .imageOnly
            button.toolTip = "DICTATOR"
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp])
        }
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        let action = StatusPopoverAction.next(isShown: popover.isShown)
        logger.info("Status item clicked; action=\(String(describing: action), privacy: .public)")
        switch action {
        case .show:
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.logger.info("Popover presented; isShown=\(self.popover.isShown, privacy: .public)")
            }
        case .close:
            popover.performClose(nil)
        }
    }
}

private enum DictatorAssets {
    static let menuIcon: NSImage = {
        let fallback = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "DICTATOR")!
        guard let url = Bundle.main.url(forResource: "DICTATOR-menu@2x", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return fallback
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()
}

private struct DictationMenu: View {
    @ObservedObject var controller: DictationController
    let openBrain: () -> Void
    @State private var apiKeyDraft = ""
    @State private var showAISettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    if controller.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(controller.statusText)
                        .font(.system(size: 17, weight: .semibold))
                }

                if !controller.transcriptionPreview.isEmpty {
                    Text(controller.transcriptionPreview)
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Button(controller.recordButtonTitle) {
                    controller.toggleRecording()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(!controller.canToggleRecording)

                Toggle("Auto-Paste", isOn: $controller.autoPasteEnabled)
                    .toggleStyle(.switch)

                Text(controller.autoPasteEnabled
                     ? "Fn release: copy + paste at cursor"
                     : "Fn release: copy to clipboard only")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)

                Toggle("Meeting audio: microphone + Mac audio", isOn: $controller.meetingCaptureEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: controller.meetingCaptureEnabled) { _, enabled in
                        if enabled, !controller.systemAudioGranted {
                            controller.requestSystemAudioPermission()
                        }
                    }

                Text(controller.meetingCaptureEnabled
                     ? "Final WAV and transcript include both audio sources"
                     : "Dictation records the microphone only")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)

                DisclosureGroup("Brain-enhanced transcript", isExpanded: $showAISettings) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Correct names and spelling", isOn: $controller.aiEnhancementEnabled)
                            .toggleStyle(.switch)

                        SecureField(
                            controller.hasOpenRouterAPIKey ? "Replace saved OpenRouter key" : "OpenRouter API key",
                            text: $apiKeyDraft
                        )
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveKey)

                        HStack {
                            Button("Save Key", action: saveKey)
                                .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).count < 20)
                            if controller.hasOpenRouterAPIKey {
                                Text("Saved in Keychain")
                                    .font(.system(size: 17))
                                    .foregroundStyle(.green)
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    controller.removeOpenRouterAPIKey()
                                }
                            }
                        }

                        TextField("OpenRouter model", text: $controller.openRouterModel)
                            .textFieldStyle(.roundedBorder)

                        Text(controller.enhancementStatusText)
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)

                        Text("Only transcript text + up to 8 short Brain snippets leave this Mac. Audio and the full Brain stay local.")
                            .font(.system(size: 17))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 8)
                }

                if !controller.latestTranscript.isEmpty {
                    Divider()
                    Text("Latest transcript")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                    Text(controller.latestTranscript)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }

                if !controller.usefulContext.isEmpty {
                    Divider()
                    Text("Things worth adding")
                        .font(.system(size: 17, weight: .semibold))
                    ForEach(controller.usefulContext) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            if let value = item.url, let url = URL(string: value) {
                                Link(item.title, destination: url)
                            } else {
                                Text(item.title).fontWeight(.medium)
                            }
                            Text(item.detail)
                                .font(.system(size: 17))
                                .foregroundStyle(.secondary)
                            Button("Open Brain source") {
                                NSWorkspace.shared.open(URL(fileURLWithPath: item.sourcePath))
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 17))
                        }
                    }
                }

                Divider()

                Button("Open Brain…", action: openBrain)

                Button("Open Archive") {
                    controller.openArchive()
                }

                Button(controller.microphoneButtonTitle) {
                    controller.requestMicrophonePermission()
                }
                .disabled(controller.microphoneGranted)

                Button(controller.systemAudioButtonTitle) {
                    controller.requestSystemAudioPermission()
                }
                .disabled(controller.systemAudioGranted)

                Button(controller.accessibilityButtonTitle) {
                    controller.requestAccessibilityPermission()
                }
                .disabled(controller.accessibilityGranted)

                Button("Quit DICTATOR") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(14)
        }
        .font(.system(size: 17))
        .frame(width: 452, height: 692)
        .onAppear {
            controller.refreshAccessibilityPermission()
            controller.refreshRecordingPermissions()
        }
    }

    private func saveKey() {
        controller.saveOpenRouterAPIKey(apiKeyDraft)
        apiKeyDraft = ""
    }
}
