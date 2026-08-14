import AppKit
import Combine
import DictateMacCore
import Foundation

@MainActor
final class DictationController: ObservableObject {
    @Published private(set) var statusText = "Loading/downloading large-v3-turbo…"
    @Published private(set) var latestTranscript = ""
    @Published private(set) var transcriptionHUDTitle = ""
    @Published private(set) var liveConfirmedText = ""
    @Published private(set) var liveProvisionalText = ""
    @Published private(set) var liveAudioProgress = LiveAudioProgress(
        waveform: [],
        audioDuration: 0,
        transcribedPosition: 0
    )
    @Published private(set) var usefulContext: [TranscriptContextItem] = []
    @Published private(set) var hasOpenRouterAPIKey = false
    @Published private(set) var enhancementStatusText = "Optional — local transcription stays available"
    @Published private(set) var isTranscribing = false
    @Published private(set) var isRecording = false
    @Published private(set) var isBusy = true
    @Published private(set) var accessibilityGranted = TranscriptDeliveryService.isAccessibilityGranted
    @Published private(set) var microphoneGranted = AudioRecorder.isAuthorized
    @Published private(set) var systemAudioGranted = SystemAudioCapture.isAuthorized
    @Published var autoPasteEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoPasteEnabled, forKey: Self.autoPasteDefaultsKey)
        }
    }
    @Published var aiEnhancementEnabled: Bool {
        didSet {
            UserDefaults.standard.set(aiEnhancementEnabled, forKey: Self.aiEnhancementDefaultsKey)
        }
    }
    @Published var meetingCaptureEnabled: Bool {
        didSet {
            UserDefaults.standard.set(meetingCaptureEnabled, forKey: Self.meetingCaptureDefaultsKey)
        }
    }
    @Published var openRouterModel: String {
        didSet {
            UserDefaults.standard.set(openRouterModel, forKey: Self.openRouterModelDefaultsKey)
        }
    }

    private static let autoPasteDefaultsKey = "autoPasteEnabled"
    private static let aiEnhancementDefaultsKey = "aiEnhancementEnabled"
    private static let meetingCaptureDefaultsKey = "meetingCaptureEnabled"
    private static let openRouterModelDefaultsKey = "openRouterModel"

    private let transcriber = LocalTranscriber()
    private let targetTracker = TargetApplicationTracker()
    private let evidenceProvider = BrainEvidenceProvider()
    private let keyStore = OpenRouterKeyStore()
    private var archive: ArchiveStore?
    private var currentSession: DictationSession?
    private var targetApplication: NSRunningApplication?
    private var currentSessionAutoPasteEnabled = true
    private var modelReady = false
    private var operationInProgress = false
    private var fnKeyMonitor: FnKeyMonitor?
    private var recordingStartedByFn = false
    private var fnReleasedDuringStartup = false
    private var systemAudioCapture: SystemAudioCapture?
    private var microphoneStartedAt: Date?


    var recordButtonTitle: String {
        isRecording ? "Stop" : "Record"
    }

    var canToggleRecording: Bool {
        isRecording || (modelReady && !operationInProgress)
    }

    var accessibilityButtonTitle: String {
        accessibilityGranted ? "Accessibility Granted" : "Enable Accessibility…"
    }

    var microphoneButtonTitle: String {
        microphoneGranted ? "Microphone Granted" : "Enable Microphone…"
    }

    var systemAudioButtonTitle: String {
        systemAudioGranted ? "Mac Audio Granted" : "Enable Mac Audio…"
    }

    init() {
        let defaults = UserDefaults.standard
        autoPasteEnabled = defaults.object(forKey: Self.autoPasteDefaultsKey) == nil
            ? true
            : defaults.bool(forKey: Self.autoPasteDefaultsKey)
        aiEnhancementEnabled = defaults.bool(forKey: Self.aiEnhancementDefaultsKey)
        meetingCaptureEnabled = defaults.bool(forKey: Self.meetingCaptureDefaultsKey)
        let storedModel = defaults.string(forKey: Self.openRouterModelDefaultsKey)
        openRouterModel = storedModel == "deepseek/deepseek-v4-flash-latest"
            ? "~deepseek/deepseek-v4-flash-latest"
            : storedModel ?? "~deepseek/deepseek-v4-flash-latest"
        hasOpenRouterAPIKey = ((try? keyStore.read()) ?? nil) != nil

        do {
            archive = try ArchiveStore()
        } catch {
            statusText = "Archive unavailable: \(error.localizedDescription)"
            isBusy = false
            return
        }

        Task {
            await prepareModel()
        }

        fnKeyMonitor = FnKeyMonitor { [weak self] action in
            self?.handleFnAction(action)
        }
        fnKeyMonitor?.start()
        if !accessibilityGranted {
            TranscriptDeliveryService.requestAccessibilityPermission()
        }
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            Task {
                await startRecording(triggeredByFn: false)
            }
        }
    }

    func openArchive() {
        guard let archive else {
            return
        }
        NSWorkspace.shared.open(archive.rootURL)
    }

    func requestAccessibilityPermission() {
        TranscriptDeliveryService.requestAccessibilityPermission()
        refreshAccessibilityPermission()
    }

    func refreshAccessibilityPermission() {
        accessibilityGranted = TranscriptDeliveryService.isAccessibilityGranted
    }

    func refreshRecordingPermissions() {
        microphoneGranted = AudioRecorder.isAuthorized
        systemAudioGranted = SystemAudioCapture.isAuthorized
    }

    func requestMicrophonePermission() {
        Task {
            microphoneGranted = await AudioRecorder.requestPermission()
            if !microphoneGranted {
                openPrivacySettings("Privacy_Microphone")
            }
        }
    }

    func requestSystemAudioPermission() {
        systemAudioGranted = SystemAudioCapture.requestPermission()
        if !systemAudioGranted {
            openPrivacySettings("Privacy_ScreenCapture")
        }
    }

    private func openPrivacySettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    func saveOpenRouterAPIKey(_ value: String) {
        do {
            try keyStore.save(value)
            hasOpenRouterAPIKey = true
            enhancementStatusText = "Key saved in Keychain"
        } catch {
            enhancementStatusText = error.localizedDescription
        }
    }

    func removeOpenRouterAPIKey() {
        do {
            try keyStore.delete()
            hasOpenRouterAPIKey = false
            aiEnhancementEnabled = false
            enhancementStatusText = "Key removed"
        } catch {
            enhancementStatusText = error.localizedDescription
        }
    }


    private func prepareModel() async {
        do {
            try await transcriber.loadModel()
            modelReady = true
            statusText = "Ready — hold Fn to talk"
        } catch {
            statusText = "Model failed: \(error.localizedDescription)"
        }
        isBusy = false
    }

    private func handleFnAction(_ action: PushToTalkAction) {
        switch action {
        case .none:
            break
        case .start:
            guard modelReady, !isRecording, !operationInProgress else {
                return
            }
            recordingStartedByFn = true
            fnReleasedDuringStartup = false
            Task {
                await startRecording(triggeredByFn: true)
            }
        case .stop:
            guard recordingStartedByFn else {
                return
            }
            if !isRecording {
                fnReleasedDuringStartup = true
            } else {
                stopRecording()
            }
        }
    }

    private func startRecording(triggeredByFn: Bool) async {
        guard modelReady, !operationInProgress, let archive else {
            return
        }
        if !triggeredByFn {
            recordingStartedByFn = false
            fnReleasedDuringStartup = false
        }
        operationInProgress = true
        isBusy = true
        statusText = "Requesting microphone access…"

        guard await AudioRecorder.requestPermission() else {
            microphoneGranted = false
            statusText = "Microphone denied — allow it in System Settings"
            isBusy = false
            operationInProgress = false
            recordingStartedByFn = false
            return
        }
        microphoneGranted = true

        let target = targetTracker.targetApplication()
        do {
            var session = try archive.startSession(
                sourceApplication: target?.localizedName
            )
            currentSession = session
            targetApplication = target
            startLivePresentation()
            microphoneStartedAt = Date()
            do {
                try await transcriber.startStreaming(
                    onUpdate: { [weak self] snapshot in
                        guard let self else { return }
                        self.liveConfirmedText = snapshot.confirmed
                        self.liveProvisionalText = snapshot.provisional
                    },
                    onAudioUpdate: { [weak self] progress in
                        self?.liveAudioProgress = progress
                    }
                )
            } catch {
                session.metadata.status = .failed
                session.metadata.completedAt = Date()
                session.metadata.error = error.localizedDescription
                try? archive.writeMetadata(for: session)
                currentSession = nil
                targetApplication = nil
                stopLivePresentation()
                microphoneStartedAt = nil
                throw error
            }

            if meetingCaptureEnabled, systemAudioGranted {
                let capture = SystemAudioCapture()
                do {
                    try await capture.start()
                    systemAudioCapture = capture
                    systemAudioGranted = true
                } catch {
                    systemAudioCapture = nil
                    transcriptionHUDTitle = "Mac audio unavailable — microphone only"
                }
            } else if meetingCaptureEnabled {
                transcriptionHUDTitle = "Mac audio permission needed — microphone only"
            }

            currentSessionAutoPasteEnabled = autoPasteEnabled
            session.metadata.autoPasteEnabled = currentSessionAutoPasteEnabled
            session.metadata.meetingCaptureEnabled = meetingCaptureEnabled
            session.metadata.systemAudioCaptured = systemAudioCapture != nil
            try archive.writeMetadata(for: session)
            currentSession = session
            isRecording = true
            isBusy = false
            operationInProgress = false
            if meetingCaptureEnabled, systemAudioCapture != nil {
                statusText = triggeredByFn
                    ? "Recording microphone + Mac audio — release Fn to stop"
                    : "Recording microphone + Mac audio"
            } else {
                statusText = triggeredByFn ? "Recording — release Fn to stop" : "Recording"
            }
            if triggeredByFn && fnReleasedDuringStartup {
                fnReleasedDuringStartup = false
                stopRecording()
            }
        } catch {
            if let systemAudioCapture, let microphoneStartedAt {
                _ = await systemAudioCapture.stop(relativeTo: microphoneStartedAt)
            }
            systemAudioCapture = nil
            microphoneStartedAt = nil
            statusText = "Recording failed: \(error.localizedDescription)"
            isBusy = false
            operationInProgress = false
            recordingStartedByFn = false
        }
    }

    private func stopRecording() {
        guard isRecording, !operationInProgress else {
            return
        }
        recordingStartedByFn = false
        fnReleasedDuringStartup = false
        isRecording = false
        isBusy = true
        operationInProgress = true
        statusText = "Saving recording"
        transcriptionHUDTitle = systemAudioCapture == nil
            ? "Saving microphone audio"
            : "Saving microphone + Mac audio"

        Task {
            await finishDictation()
        }
    }

    private func finishDictation() async {
        guard var session = currentSession, let archive else {
            if let systemAudioCapture, let microphoneStartedAt {
                _ = await systemAudioCapture.stop(relativeTo: microphoneStartedAt)
            }
            systemAudioCapture = nil
            microphoneStartedAt = nil
            stopLivePresentation()
            statusText = "Session unavailable"
            isBusy = false
            operationInProgress = false
            return
        }

        session.metadata.status = .transcribing
        try? archive.writeMetadata(for: session)

        do {
            let systemAudio: CapturedSystemAudio?
            if let systemAudioCapture, let microphoneStartedAt {
                systemAudio = await systemAudioCapture.stop(relativeTo: microphoneStartedAt)
            } else {
                systemAudio = nil
            }
            self.systemAudioCapture = nil
            self.microphoneStartedAt = nil
            session.metadata.systemAudioCaptured = !(systemAudio?.samples.isEmpty ?? true)
            transcriptionHUDTitle = "Finalizing, please wait"
            statusText = "Finalizing, please wait"
            try await transcriber.stopStreamingAndSave(
                to: session.audioURL,
                systemAudio: systemAudio
            )
            let rawTranscript = try await transcriber.transcribe(audioURL: session.audioURL)
            let transcript = TranscriptCleaner.clean(rawTranscript)
            guard !transcript.isEmpty else {
                throw DictationError.emptyTranscript
            }
            liveAudioProgress = LiveAudioProgress(
                waveform: liveAudioProgress.waveform,
                audioDuration: liveAudioProgress.audioDuration,
                transcribedPosition: liveAudioProgress.audioDuration
            )
            liveConfirmedText = transcript
            liveProvisionalText = ""
            transcriptionHUDTitle = aiEnhancementEnabled
                ? "Checking grounded corrections"
                : "Preparing transcript"

            let enhancementResult = await enhanceIfEnabled(transcript)
            let finalTranscript = enhancementResult.enhancement?.correctedTranscript ?? transcript
            session.metadata.enhancementModel = enhancementResult.enhancement == nil ? nil : openRouterModel
            session.metadata.enhancementEvidencePaths = enhancementResult.evidence.compactMap(\.path)
            session.metadata.usefulContext = enhancementResult.enhancement?.usefulContext
            session.metadata.enhancementError = enhancementResult.error
            session = try archive.nameAndWriteTranscript(
                finalTranscript,
                rawTranscript: enhancementResult.enhancement == nil ? nil : transcript,
                for: session
            )
            currentSession = session
            latestTranscript = finalTranscript
            usefulContext = enhancementResult.enhancement?.usefulContext ?? []
            liveConfirmedText = finalTranscript
            liveProvisionalText = ""
            transcriptionHUDTitle = "Copying transcript"
            statusText = "Delivering final transcript"
            let delivery = await TranscriptDeliveryService.deliver(
                finalTranscript,
                to: targetApplication,
                mode: AutoPastePolicy.deliveryMode(isEnabled: currentSessionAutoPasteEnabled)
            )

            session.metadata.status = .completed
            session.metadata.completedAt = Date()
            session.metadata.delivery = delivery
            session.metadata.autoPasteEnabled = currentSessionAutoPasteEnabled
            session.metadata.error = nil
            try archive.complete(session)

            stopLivePresentation()
            refreshAccessibilityPermission()
            switch delivery {
            case .accessibilityInserted:
                statusText = "Inserted into \(targetApplication?.localizedName ?? "target app")"
            case .pasteShortcutPosted:
                statusText = "Paste sent to \(targetApplication?.localizedName ?? "target app")"
            case .accessibilityDenied:
                statusText = "Copied — enable Accessibility for DICTATOR"
            case .targetUnavailable:
                statusText = "Copied — target field unavailable"
            case .clipboardOnly:
                statusText = "Copied — Auto-Paste is off"
            }
        } catch {
            session.metadata.status = .failed
            session.metadata.completedAt = Date()
            session.metadata.error = error.localizedDescription
            try? archive.writeMetadata(for: session)
            stopLivePresentation()
            statusText = "Transcription failed: \(error.localizedDescription)"
        }

        stopLivePresentation()
        currentSession = nil
        targetApplication = nil
        isBusy = false
        operationInProgress = false
    }

    private func enhanceIfEnabled(_ transcript: String) async -> (
        enhancement: TranscriptEnhancement?,
        evidence: [BrainEvidenceItem],
        error: String?
    ) {
        guard aiEnhancementEnabled else { return (nil, [], nil) }
        let key: String
        do {
            guard let stored = try keyStore.read() else {
                enhancementStatusText = "Add an OpenRouter key to enable enhancement"
                return (nil, [], "OpenRouter key not configured")
            }
            key = stored
        } catch {
            enhancementStatusText = error.localizedDescription
            return (nil, [], error.localizedDescription)
        }

        statusText = "Improving with Brain context…"
        let evidence = await evidenceProvider.evidence(for: transcript)
        do {
            let candidate = try await OpenRouterClient(apiKey: key, model: openRouterModel)
                .enhance(transcript: transcript, evidence: evidence)
            guard let enhancement = TranscriptEnhancementContract.validate(
                candidate,
                rawTranscript: transcript,
                evidence: evidence
            ) else {
                enhancementStatusText = "Unsafe rewrite rejected — local transcript used"
                return (nil, evidence, "Enhancement failed preservation contract")
            }
            enhancementStatusText = "Enhanced from \(evidence.count) Brain sources"
            return (enhancement, evidence, nil)
        } catch {
            if case OpenRouterError.unauthorized = error {
                aiEnhancementEnabled = false
                enhancementStatusText = "OpenRouter authorization failed — correction disabled"
            } else {
                enhancementStatusText = "Enhancement unavailable — local transcript used"
            }
            return (nil, evidence, error.localizedDescription)
        }
    }

    private func startLivePresentation() {
        isTranscribing = true
        usefulContext = []
        transcriptionHUDTitle = ""
        liveConfirmedText = ""
        liveProvisionalText = ""
        liveAudioProgress = LiveAudioProgress(
            waveform: [],
            audioDuration: 0,
            transcribedPosition: 0
        )
    }

    private func stopLivePresentation() {
        isTranscribing = false
        transcriptionHUDTitle = ""
        liveConfirmedText = ""
        liveProvisionalText = ""
        liveAudioProgress = LiveAudioProgress(
            waveform: [],
            audioDuration: 0,
            transcribedPosition: 0
        )
    }

}

private enum DictationError: LocalizedError {
    case emptyTranscript

    var errorDescription: String? {
        "No speech was recognized."
    }
}
