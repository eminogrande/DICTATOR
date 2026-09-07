import AppKit
import DictateMacCore
import UniformTypeIdentifiers

@MainActor
final class DictatorMenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let activityView = MenuSessionActivityView()
    private let recentMenu = NSMenu()
    private var timer: Timer?
    private var recordItem: NSMenuItem!
    private var fileItem: NSMenuItem!
    private var cancelItem: NSMenuItem!
    private var recentRows: [(id: String, item: NSMenuItem, state: NSMenuItem, retry: NSMenuItem, copy: NSMenuItem, open: NSMenuItem)] = []
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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        recentMenu.autoenablesItems = false
        let activity = NSMenuItem()
        activity.view = activityView
        menu.addItem(activity)
        menu.addItem(.separator())
        recordItem = add("Aufnahme starten", action: #selector(toggleMeeting), key: "r")
        recordItem.keyEquivalentModifierMask = .function
        fileItem = add("Datei importieren…", action: #selector(transcribeFileAction), key: "o")
        cancelItem = add("Texterstellung anhalten", action: #selector(cancelTranscription))
        let recent = add("Letzte Aufnahmen", action: nil)
        recent.submenu = recentMenu
        _ = add("Alle Aufnahmen…", action: #selector(openSettingsAction))
        _ = add("Aufnahmeordner öffnen", action: #selector(openArchiveAction))
        menu.addItem(.separator())
        _ = add("Wissensarchiv öffnen", action: #selector(openBrainAction))
        _ = add("App öffnen", action: #selector(openSettingsAction), key: ",")
        menu.addItem(.separator())
        _ = add("DICTATOR beenden", action: #selector(quitAction), key: "q")

        // A normal attached native menu: clicking REC never stops the recording.
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageLeading
        rebuildRecentSessions()
        refreshLiveStatus()
        // NSMenu tracks in a nested run loop; default-mode timers and queue-only
        // updates freeze there. Keep the same NSView/items and tick in common modes.
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

    private func add(_ title: String, action: Selector?, key: String = "") -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        controller?.refreshSessions()
        rebuildRecentSessions()
        refreshLiveStatus()
    }

    private func refreshLiveStatus() {
        guard let controller else { return }
        let title = SessionActivityPresentation.title(controller, now: Date())
        let color = SessionActivityPresentation.color(controller.activityPhase)
        if let button = statusItem.button {
            DictatorAssets.applyMenuBranding(to: button, phase: controller.activityPhase, activityTitle: title)
            button.toolTip = "\(title) — \(SessionActivityPresentation.detail(controller)). Für Aktionen klicken."
            button.setAccessibilityLabel("DICTATOR — " + title)
        }
        activityView.update(controller: controller, title: title, color: color)
        recordItem.title = controller.isMeetingStarting ? "Start abbrechen" : (controller.isRecording ? "Aufnahme stoppen" : "Aufnahme starten")
        recordItem.isEnabled = controller.canToggleRecording
        fileItem.isEnabled = controller.canTranscribeFile
        cancelItem.isHidden = !controller.canCancelTranscription
        cancelItem.isEnabled = controller.canCancelTranscription
        // Mutate existing rows, never tear down the tracking menu on clock ticks.
        for row in recentRows {
            guard let session = controller.sessions.first(where: { $0.metadata.sessionID == row.id }) else { continue }
            row.item.title = sessionTitle(session)
            row.state.title = SessionActivityPresentation.status(session.metadata.status.rawValue)
            let completed = session.metadata.status == .completed
            row.retry.isEnabled = controller.canRetryTranscription
            row.retry.isHidden = completed
            row.retry.title = session.metadata.status == .saved ? "Text erstellen" : "Erneut versuchen"
            row.copy.isHidden = !completed
            row.open.isHidden = false
        }
    }

    private func sessionTitle(_ session: DictationSession) -> String {
        let info = controller?.libraryDetails[session.metadata.sessionID]
        return "\(info?.title ?? SessionLibraryInfo.title(for: session.metadata)) · \(info?.durationLabel ?? "—") · \(info?.wordCount ?? 0) Wörter"
    }

    private func rebuildRecentSessions() {
        recentMenu.removeAllItems()
        recentRows.removeAll()
        guard let controller else { return }
        for session in controller.sessions.sorted(by: { $0.metadata.startedAt > $1.metadata.startedAt }).prefix(5) {
            let id = session.metadata.sessionID
            let item = recentMenu.addItem(withTitle: sessionTitle(session), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            item.submenu = submenu
            let state = submenu.addItem(withTitle: SessionActivityPresentation.status(session.metadata.status.rawValue), action: nil, keyEquivalent: "")
            state.isEnabled = false
            if let error = session.metadata.error, !error.isEmpty, !error.hasPrefix("Audio saved. Loading ") {
                // Scrollable, selectable full error, not a clipped one-line menu title.
                let errorItem = NSMenuItem()
                errorItem.view = MenuSessionActivityView.textPanel(error, width: 370, height: 100)
                submenu.addItem(errorItem)
            }
            func action(_ title: String, _ selector: Selector) -> NSMenuItem {
                let child = submenu.addItem(withTitle: title, action: selector, keyEquivalent: "")
                child.target = self
                child.representedObject = id
                return child
            }
            _ = action("Im Finder zeigen", #selector(revealAudio(_:)))
            let completed = session.metadata.status == .completed
            let retry = action(session.metadata.status == .saved ? "Text erstellen" : "Erneut versuchen", #selector(retrySession(_:)))
            retry.isEnabled = controller.canRetryTranscription
            retry.isHidden = completed
            let copy = action("Text kopieren", #selector(copySession(_:)))
            let open = action("Aufnahme öffnen", #selector(openSession(_:)))
            copy.isHidden = !completed
            open.isHidden = false
            recentRows.append((id, item, state, retry, copy, open))
        }
        if recentRows.isEmpty {
            let empty = recentMenu.addItem(withTitle: "Noch keine Aufnahmen", action: nil, keyEquivalent: "")
            empty.isEnabled = false
        }
        recentMenu.addItem(.separator())
        let all = recentMenu.addItem(withTitle: "Alle Aufnahmen…", action: #selector(openSettingsAction), keyEquivalent: "")
        all.target = self
    }

    @objc private func toggleMeeting() { controller?.toggleRecording() }
    @objc private func cancelTranscription() { controller?.cancelFileTranscription() }
    @objc private func retrySession(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { controller?.retryTranscription(id) }
    }
    @objc private func revealAudio(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { controller?.revealAudioInFolder(id) }
    }
    @objc private func copySession(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { controller?.copySessionTranscript(id) }
    }
    @objc private func openSession(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { controller?.selectedLibrarySessionID = id; openSettings() }
    }
    @objc private func transcribeFileAction() {
        guard controller?.canTranscribeFile == true else { return }
        let panel = NSOpenPanel()
        panel.title = "Audio oder Video importieren"
        panel.prompt = "Text erstellen"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie, .audiovisualContent]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.controller?.transcribeAudioFile(url)
        }
    }
    @objc private func openArchiveAction() { openArchive() }
    @objc private func openBrainAction() { openBrain() }
    @objc private func openSettingsAction() { openSettings() }
    @objc private func quitAction() { NSApplication.shared.terminate(nil) }
}

/// Native persistent menu content, updated even during NSMenu tracking.
@MainActor
private final class MenuSessionActivityView: NSView {
    private let heading = NSTextField(labelWithString: "")
    private let mic = NSTextField(wrappingLabelWithString: "")
    private let mac = NSTextField(wrappingLabelWithString: "")
    private let micMeter = NSProgressIndicator()
    private let macMeter = NSProgressIndicator()
    private let progress = NSProgressIndicator()
    private let detailScroll: NSScrollView
    private let detailText: NSTextView

    init() {
        let scroll = Self.textPanel("", width: 370, height: 120)
        detailScroll = scroll
        detailText = scroll.documentView as! NSTextView
        super.init(frame: NSRect(x: 0, y: 0, width: 394, height: 290))
        heading.frame = NSRect(x: 12, y: 260, width: 370, height: 22)
        heading.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        addSubview(heading)
        mic.frame = NSRect(x: 12, y: 212, width: 370, height: 38)
        mac.frame = NSRect(x: 12, y: 154, width: 370, height: 38)
        for label in [mic, mac] {
            label.font = .menuFont(ofSize: 0)
            addSubview(label)
        }
        for (meter, y) in [(micMeter, 200.0), (macMeter, 142.0), (progress, 240.0)] {
            meter.frame = NSRect(x: 12, y: y, width: 370, height: 8)
            meter.style = .bar
            meter.isIndeterminate = false
            meter.minValue = 0
            meter.maxValue = 1
            addSubview(meter)
        }
        addSubview(detailScroll)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(controller: DictationController, title: String, color: NSColor) {
        heading.stringValue = title
        heading.textColor = color
        let recording = controller.isRecording
        for view in [mic, mac, micMeter, macMeter] as [NSView] { view.isHidden = !recording }
        mic.stringValue = "Mikrofon · \(SessionActivityPresentation.sourceStatus(controller.microphoneStatus))"
        mac.stringValue = "Mac-Audio · \(SessionActivityPresentation.sourceStatus(controller.systemAudioStatus))"
        micMeter.doubleValue = SessionActivityPresentation.level(controller.microphoneLevel)
        macMeter.doubleValue = SessionActivityPresentation.level(controller.systemAudioLevel)
        progress.isHidden = controller.activityPhase != "transcribing"
        progress.isIndeterminate = controller.fileProgress <= 0
        if progress.isIndeterminate && !progress.isHidden { progress.startAnimation(nil) }
        else { progress.stopAnimation(nil); progress.doubleValue = min(1, max(0, controller.fileProgress)) }
        detailScroll.frame = NSRect(x: 12, y: 10, width: 370, height: recording ? 122 : 218)
        let partial = SessionActivityPresentation.partial(controller)
        let text = SessionActivityPresentation.detail(controller) + (partial.isEmpty ? "" : "\n\n\(partial)")
        if detailText.string != text { detailText.string = text }
        detailText.textColor = controller.activityPhase == "failed" ? .systemRed : .labelColor
    }

    static func textPanel(_ text: String, width: CGFloat, height: CGFloat) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let field = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        field.isEditable = false
        field.isSelectable = true
        field.drawsBackground = false
        field.font = .menuFont(ofSize: 0)
        field.textColor = .labelColor
        field.textContainerInset = NSSize(width: 2, height: 4)
        field.isVerticallyResizable = true
        field.isHorizontallyResizable = false
        field.autoresizingMask = [.width]
        field.textContainer?.widthTracksTextView = true
        field.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        field.string = text
        scroll.documentView = field
        return scroll
    }
}
