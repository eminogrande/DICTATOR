import AppKit
import UniformTypeIdentifiers

/// A quick-control menu, not a second transcript browser.
@MainActor
final class DictatorMenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    let menu = NSMenu()
    private let activityView = MenuSessionActivityView()
    private var timer: Timer?
    private var recordItem: NSMenuItem!
    private var fileItem: NSMenuItem!
    private var cancelItem: NSMenuItem!
    private let openLibrary: () -> Void
    private let openPreferences: () -> Void
    private weak var controller: DictationController?

    init(controller: DictationController, openLibrary: @escaping () -> Void,
         openPreferences: @escaping () -> Void) {
        self.controller = controller
        self.openLibrary = openLibrary
        self.openPreferences = openPreferences
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.minimumWidth = 280
        let activity = NSMenuItem()
        activity.view = activityView
        menu.addItem(activity)
        menu.addItem(.separator())
        recordItem = add("Aufnahme starten", symbol: "record.circle", action: #selector(toggleMeeting))
        recordItem.toolTip = "Mit Fn + R starten oder stoppen"
        fileItem = add("Datei importieren…", symbol: "square.and.arrow.down", action: #selector(transcribeFileAction), key: "o")
        cancelItem = add("Texterstellung anhalten", symbol: "stop.circle", action: #selector(cancelTranscription))
        _ = add("Aufnahmen öffnen", symbol: "rectangle.split.2x1", action: #selector(openLibraryAction))
        menu.addItem(.separator())
        _ = add("Einstellungen…", symbol: "gearshape", action: #selector(openPreferencesAction), key: ",")
        _ = add("DICTATOR beenden", symbol: "power", action: #selector(quitAction), key: "q")
        statusItem.menu = menu
        refreshLiveStatus()
        let clock = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshLiveStatus() }
        }
        RunLoop.main.add(clock, forMode: .common)
        timer = clock
    }

    deinit {
        timer?.invalidate()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func add(_ title: String, symbol: String?, action: Selector, key: String = "") -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        if let symbol {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            image?.isTemplate = true
            image?.size = NSSize(width: 14, height: 14)
            item.image = image
        }
        return item
    }

    func menuWillOpen(_ menu: NSMenu) { refreshLiveStatus() }

    private func refreshLiveStatus() {
        guard let controller else { return }
        let title = SessionActivityPresentation.title(controller, now: Date())
        if let button = statusItem.button {
            DictatorAssets.applyMenuBranding(to: button, phase: controller.activityPhase, activityTitle: title)
            button.toolTip = "DICTATOR — " + SessionActivityPresentation.detail(controller)
            button.setAccessibilityLabel("DICTATOR — " + title)
        }
        let oldHeight = activityView.frame.height
        activityView.update(controller: controller)
        let recordTitle = controller.isMeetingStarting ? "Start abbrechen" : (controller.isRecording ? "Aufnahme stoppen" : "Aufnahme starten")
        if recordItem.title != recordTitle {
            recordItem.title = recordTitle
            recordItem.image = NSImage(systemSymbolName: controller.isRecording || controller.isMeetingStarting ? "stop.circle" : "record.circle", accessibilityDescription: recordTitle)
            recordItem.image?.isTemplate = true
            recordItem.image?.size = NSSize(width: 14, height: 14)
        }
        recordItem.isEnabled = controller.canToggleRecording
        fileItem.isEnabled = controller.canTranscribeFile
        cancelItem.isHidden = !controller.canCancelTranscription
        cancelItem.isEnabled = controller.canCancelTranscription
        if activityView.frame.height != oldHeight { menu.update() }
    }

    @objc private func toggleMeeting() { controller?.toggleRecording() }
    @objc private func cancelTranscription() { controller?.cancelFileTranscription() }
    @objc private func openLibraryAction() { openLibrary() }
    @objc private func openPreferencesAction() { openPreferences() }
    @objc private func quitAction() { NSApplication.shared.terminate(nil) }
    @objc private func transcribeFileAction() {
        guard controller?.canTranscribeFile == true else { return }
        let panel = NSOpenPanel()
        panel.title = "Audio oder Video importieren"
        panel.prompt = "Importieren"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie, .audiovisualContent]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.controller?.transcribeAudioFile(url)
        }
    }
}

/// Content-sized status with no transcript/error dump or nested navigation.
@MainActor
final class MenuSessionActivityView: NSView {
    private let heading = NSTextField(labelWithString: "")
    private let elapsed = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let mic = NSTextField(labelWithString: "Mikrofon")
    private let mac = NSTextField(labelWithString: "Mac-Audio")
    private let micState = NSTextField(labelWithString: "")
    private let macState = NSTextField(labelWithString: "")
    private let micMeter = NSProgressIndicator()
    private let macMeter = NSProgressIndicator()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 56))
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        elapsed.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        elapsed.alignment = .right
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        for label in [heading, elapsed, detail, mic, mac, micState, macState] {
            if label !== heading && label !== elapsed && label !== detail { label.font = .systemFont(ofSize: 12) }
            addSubview(label)
        }
        for meter in [micMeter, macMeter] {
            meter.style = .bar
            meter.isIndeterminate = false
            meter.minValue = 0
            meter.maxValue = 1
            addSubview(meter)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(controller: DictationController) {
        let phase = controller.activityPhase
        let recording = controller.isRecording
        layoutStatus(recording: recording)
        switch phase {
        case "starting": heading.stringValue = "Aufnahme startet"; detail.stringValue = "Mikrofon wird vorbereitet"
        case "recording": heading.stringValue = "Aufnahme läuft"
        case "saving": heading.stringValue = "Audio wird gesichert"; detail.stringValue = "Bitte kurz warten"
        case "transcribing": heading.stringValue = "Text wird erstellt"; detail.stringValue = "Läuft im Hintergrund"
        case "completed": heading.stringValue = "Text gespeichert"; detail.stringValue = "In Aufnahmen ansehen und kopieren"
        case "saved": heading.stringValue = "Audio gespeichert"; detail.stringValue = "Text jederzeit später erstellen"
        case "failed": heading.stringValue = "Aufnahme prüfen"; detail.stringValue = "Details und Wiederholen in Aufnahmen"
        default:
            heading.stringValue = "Bereit für eine Aufnahme"
            detail.stringValue = controller.canStartDictation ? "Zum Diktieren Fn gedrückt halten" : controller.readiness.isLoading ? "Diktieren wird vorbereitet" : "Diktieren: Einstellungen öffnen"
        }
        let timed = ["recording", "saving", "transcribing"].contains(phase)
        let age = controller.activityStartedAt.map { max(0, Date().timeIntervalSince($0)) } ?? 0
        let seconds = recording ? max(controller.recordingElapsed, age) : age
        elapsed.stringValue = timed ? SessionLibraryInfo.durationLabel(seconds) : ""
        if recording {
            micState.stringValue = Self.sourceLabel(controller.microphoneStatus)
            macState.stringValue = Self.sourceLabel(controller.systemAudioStatus)
            micState.toolTip = controller.microphoneStatus
            macState.toolTip = controller.systemAudioStatus
            micMeter.doubleValue = SessionActivityPresentation.level(controller.microphoneLevel)
            macMeter.doubleValue = SessionActivityPresentation.level(controller.systemAudioLevel)
        }
        setAccessibilityLabel(heading.stringValue + " " + elapsed.stringValue)
        micMeter.setAccessibilityLabel("Mikrofon: " + controller.microphoneStatus)
        macMeter.setAccessibilityLabel("Mac-Audio: " + controller.systemAudioStatus)
    }

    func layoutStatus(recording: Bool) {
        let height: CGFloat = recording ? 100 : 56
        if frame.height != height { setFrameSize(NSSize(width: 280, height: height)) }
        heading.frame = NSRect(x: 14, y: height - 28, width: 172, height: 20)
        elapsed.frame = NSRect(x: 190, y: height - 27, width: 76, height: 18)
        detail.frame = NSRect(x: 14, y: 9, width: 252, height: 18)
        detail.isHidden = recording
        for view in [mic, mac, micState, macState, micMeter, macMeter] as [NSView] { view.isHidden = !recording }
        if recording {
            for (label, meter, state, y) in [(mic, micMeter, micState, 44.0), (mac, macMeter, macState, 17.0)] {
                label.frame = NSRect(x: 14, y: y, width: 66, height: 18)
                meter.frame = NSRect(x: 82, y: y + 6, width: 72, height: 6)
                state.frame = NSRect(x: 163, y: y, width: 103, height: 18)
            }
        }
    }

    static func sourceLabel(_ status: String) -> String {
        switch status {
        case "Listening": return "Wartet auf Ton"
        case "Receiving audio", "No audio yet", "Quiet", "Not recording", "Off", "Not requested", "Starting…":
            return SessionActivityPresentation.sourceStatus(status)
        default: return "Nicht verfügbar"
        }
    }
}
