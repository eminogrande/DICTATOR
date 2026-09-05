import AppKit
import AVFoundation
import Combine
import DictateMacCore
import Foundation
import OSLog

@MainActor
final class DictationController: ObservableObject {
    @Published private(set) var statusText = "Loading Fast…"
    @Published private(set) var readiness = TranscriptionReadiness(engineID: TranscriptionEngine.whisperCpp.rawValue)
    @Published private(set) var blockedHUDVisible = false
    @Published private(set) var latestTranscript = ""
    /// True while the current take is an Fn+A compress take (result = minimal numbered list).
    @Published private(set) var compressMode = false
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
    @Published private(set) var isTranscribingFile = false
    @Published private(set) var fileProgress: Double = 0
    @Published private(set) var filePartialText = ""
    @Published private(set) var isBusy = true
    @Published private(set) var accessibilityGranted = TranscriptDeliveryService.isAccessibilityGranted
    @Published private(set) var microphoneGranted = AudioRecorder.isAuthorized
    @Published private(set) var systemAudioGranted = SystemAudioCapture.isAuthorized
    @Published var autoPasteEnabled: Bool {
        didSet {
            settings.set(autoPasteEnabled, forKey: Self.autoPasteDefaultsKey)
        }
    }
    @Published var aiEnhancementEnabled: Bool {
        didSet {
            settings.set(aiEnhancementEnabled, forKey: Self.aiEnhancementDefaultsKey)
        }
    }
    @Published var meetingCaptureEnabled: Bool {
        didSet {
            settings.set(meetingCaptureEnabled, forKey: Self.meetingCaptureDefaultsKey)
        }
    }
    @Published var openRouterModel: String {
        didSet {
            settings.set(openRouterModel, forKey: Self.openRouterModelDefaultsKey)
        }
    }
    @Published var transcriptionEngine: TranscriptionEngine = .whisperCpp {
        didSet {
            settings.set(transcriptionEngine.rawValue, forKey: Self.engineDefaultsKey)
            if transcriptionEngine != oldValue { refreshReadiness() }
        }
    }

    private static let autoPasteDefaultsKey = "autoPasteEnabled"
    private static let aiEnhancementDefaultsKey = "aiEnhancementEnabled"
    private static let meetingCaptureDefaultsKey = "meetingCaptureEnabled"
    private static let openRouterModelDefaultsKey = "openRouterModel"
    private static let engineDefaultsKey = "transcriptionEngine"

    private let transcriber = LocalTranscriber()
    private let micRecorder = AudioRecorder()
    private let targetTracker = TargetApplicationTracker()
    private let evidenceProvider = BrainEvidenceProvider()
    private let keyStore = OpenRouterKeyStore()
    private var archive: ArchiveStore?
    private var currentSession: DictationSession?
    private var targetApplication: NSRunningApplication?
    private var currentSessionAutoPasteEnabled = true
    private let settings: UserDefaults
    private let readinessValidator: ((TranscriptionEngine) async throws -> Void)?
    private var readinessTask: Task<Void, Never>?
    private var previewTask: Task<Void, Error>?
    private var sessionEngine: TranscriptionEngine = .whisperCpp
    private var modelReady: Bool {
        readiness.permitsRecording(engineID: transcriptionEngine.rawValue, busy: false, recording: false)
    }
    var hasActiveWork: Bool { isRecording || operationInProgress }
    var canTranscribeFile: Bool { modelReady && !hasActiveWork }
    var readinessStatus: String { readiness.status(engineName: transcriptionEngine.displayName) }

    private var operationInProgress = false
    private var fnKeyMonitor: FnKeyMonitor?
    private var recordingStartedByFn = false
    private var fnReleasedDuringStartup = false
    private var systemAudioCapture: SystemAudioCapture?
    private var microphoneStartedAt: Date?
    private var streamingActive = false
    private var activeFileTask: WhisperCppFileTask?
    private var whisperKitReady = false


    var isLatchedRecording: Bool { isRecording && !recordingStartedByFn }

    @Published var isLatchedRecordingPublished: Bool = false

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

    init(startServices: Bool = true, defaults: UserDefaults = .standard,
         readinessValidator: ((TranscriptionEngine) async throws -> Void)? = nil) {
        self.settings = defaults
        self.readinessValidator = readinessValidator
        autoPasteEnabled = defaults.object(forKey: Self.autoPasteDefaultsKey) == nil
            ? true
            : defaults.bool(forKey: Self.autoPasteDefaultsKey)
        aiEnhancementEnabled = defaults.bool(forKey: Self.aiEnhancementDefaultsKey)
        meetingCaptureEnabled = defaults.bool(forKey: Self.meetingCaptureDefaultsKey)
        let storedModel = defaults.string(forKey: Self.openRouterModelDefaultsKey)
        openRouterModel = storedModel == "deepseek/deepseek-v4-flash-latest"
            ? "~deepseek/deepseek-v4-flash-latest"
            : storedModel ?? "~deepseek/deepseek-v4-flash-latest"
        if let storedEngine = defaults.string(forKey: Self.engineDefaultsKey),
           let engine = TranscriptionEngine(rawValue: storedEngine) {
            transcriptionEngine = engine
        }
        readiness = TranscriptionReadiness(engineID: transcriptionEngine.rawValue)
        statusText = readinessStatus
        guard startServices else { isBusy = false; return }
        hasOpenRouterAPIKey = ((try? keyStore.read()) ?? nil) != nil

        do {
            archive = try ArchiveStore()
        } catch {
            statusText = "Archive unavailable: \(error.localizedDescription)"
            isBusy = false
            return
        }

        isBusy = false
        refreshReadiness()
        preparePreview()

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
                await startRecording(triggeredByFn: false, forceMeetingAudio: false)
            }
        }
    }

    func openArchive() {
        guard let archive else {
            return
        }
        NSWorkspace.shared.open(archive.rootURL)
    }

    /// Transcribe a user-picked audio file: whisper.cpp full-file pass → paste + archive.
    func transcribeAudioFile(_ url: URL) {
        guard !isRecording, !operationInProgress else {
            statusText = "Finish the current take first"
            return
        }
        guard ensureReady() else { return }
        let engine = transcriptionEngine
        operationInProgress = true
        isBusy = true
        isTranscribingFile = true
        fileProgress = 0
        filePartialText = ""
        statusText = "Converting audio…"

        Task {
            defer {
                isBusy = false
                operationInProgress = false
                isTranscribingFile = false
                activeFileTask = nil
            }
            guard let archive else {
                statusText = "Archive unavailable"
                return
            }
            do {
                var session = try archive.startSession(sourceApplication: "Audio File")
                session.metadata.status = .transcribing
                try archive.writeMetadata(for: session)

                // Normalize any input (wav/mp3/m4a/mp4/mov/flac/ogg/aiff) to 16 kHz mono WAV.
                let destination = session.audioURL
                try await Task.detached(priority: .utility) {
                    try Self.convertToWav16kMono(url, to: destination)
                }.value

                let raw: String
                let modelName: String
                switch engine {
                case .qwen3ASR:
                    let qwen = try await QwenASRService.transcribe(wavURL: session.audioURL)
                    raw = qwen.text
                    modelName = qwen.model
                case .whisperKit:
                    raw = try await transcriber.transcribe(wavURL: session.audioURL)
                    modelName = "WhisperKit large-v3-turbo"
                case .whisperCpp:
                    let task = try WhisperCppFileTask(wavURL: session.audioURL)
                    activeFileTask = task
                    statusText = "Transcribing…"
                    raw = try await task.run { [weak self] snapshot in
                        Task { @MainActor in
                            self?.fileProgress = snapshot.fraction
                            self?.filePartialText = snapshot.text
                            self?.statusText = Self.progressLabel(snapshot.fraction)
                        }
                    }
                    modelName = "whisper.cpp large-v3-turbo"
                }
                let transcript = TranscriptCleaner.clean(raw)
                guard !transcript.isEmpty else { throw DictationError.emptyTranscript }
                session.metadata.model = modelName

                session = try archive.nameAndWriteTranscript(transcript, for: session)
                currentSession = session
                latestTranscript = transcript
                statusText = "Delivering final transcript"
                let deliveryTarget = targetTracker.targetApplication()
                let delivery = await TranscriptDeliveryService.deliver(
                    transcript,
                    to: deliveryTarget,
                    mode: AutoPastePolicy.deliveryMode(isEnabled: autoPasteEnabled)
                )
                session.metadata.status = .completed
                session.metadata.completedAt = Date()
                session.metadata.delivery = delivery
                session.metadata.autoPasteEnabled = autoPasteEnabled
                try archive.complete(session)
                currentSession = nil
                switch delivery {
                case .accessibilityInserted, .pasteShortcutPosted:
                    statusText = "Audio file transcribed"
                case .accessibilityDenied, .targetUnavailable:
                    statusText = "Copied — enable Accessibility for DICTATOR"
                case .clipboardOnly:
                    statusText = "Copied — Auto-Paste is off"
                }
            } catch {
                statusText = "Audio file failed: \(error.localizedDescription)"
            }
        }
    }

    /// Cancel the in-flight file transcription (kills whisper.cpp).
    func cancelFileTranscription() {
        activeFileTask?.cancel()
        statusText = "Cancelling…"
    }

    private static func progressLabel(_ fraction: Double) -> String {
        let pct = Int((fraction * 100).rounded())
        return "Transcribing… \(pct)%"
    }

    /// Recent takes for the menu bar list: headline + time, text attached by the menu.
    func recentTranscriptsForMenu(limit: Int = 5) -> [(id: String, displayTitle: String, text: String)] {
        guard let archive else { return [] }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return archive.recentTranscripts(limit: limit).map { entry in
            (id: entry.id, displayTitle: "\(entry.headline) — \(formatter.string(from: entry.date))", text: entry.text)
        }
    }

    /// Reveal a transcript (and its audio + metadata) in Finder.
    func revealTranscriptInFolder(_ id: String) {
        guard let archive else { return }
        let file = archive.rootURL.appendingPathComponent(id + ".txt")
        NSWorkspace.shared.activateFileViewerSelecting([file])
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

    nonisolated private static func convertToWav16kMono(_ source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = [
            "-f", "WAVE", "-d", "LEI16@16000", "-c", "1",
            source.path, destination.path,
        ]
        let err = Pipe()
        process.standardError = err
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw AudioConversionError.afconvertFailed(exit: process.terminationStatus, message: message)
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


    /// Refresh only readiness; never stop a recording or file job. Each job pins
    /// its engine. Slow results from a previous selection are discarded.
    func refreshReadiness() {
        let engine = transcriptionEngine
        let token = readiness.begin(engineID: engine.rawValue)
        if !hasActiveWork { statusText = readinessStatus }
        // A stuck optional/Built-in load must not delay a newly selected sidecar.
        // Generation tokens reject superseded probe results.
        readinessTask = Task { [weak self] in
            guard let self, self.readiness.generation == token else { return }
            let deadline = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 180_000_000_000)
                guard !Task.isCancelled, let self else { return }
                self.readiness.complete(token, error: "Loading timed out. Retry or choose another quality.")
                if !self.hasActiveWork { self.statusText = self.readinessStatus }
            }
            defer { deadline.cancel() }
            do {
                if let validator = self.readinessValidator {
                    try await validator(engine)
                } else if engine == .whisperKit {
                    self.preparePreview()
                    try await self.previewTask?.value
                    guard self.whisperKitReady else { throw EngineValidationError("Built-in is unavailable.") }
                } else {
                    try await EngineValidation.validateSidecar(engine)
                }
                self.readiness.complete(token)
            } catch {
                self.readiness.complete(token, error: error.localizedDescription)
            }
            if self.readiness.generation == token && !self.hasActiveWork {
                self.statusText = self.readinessStatus
            }
        }
    }

    private func preparePreview() {
        guard previewTask == nil else { return }
        previewTask = Task {
            do {
                try await transcriber.loadModel()
                let text = try await transcriber.transcribe(wavURL: EngineValidation.fixtureURL)
                guard !TranscriptCleaner.clean(text).isEmpty else {
                    throw EngineValidationError("Built-in produced no transcript.")
                }
                whisperKitReady = true
            } catch {
                whisperKitReady = false
                throw error
            }
        }
    }

    func retryReadiness() {
        guard !hasActiveWork, !readiness.isLoading else { return }
        if !whisperKitReady { previewTask = nil }
        refreshReadiness()
    }

    @discardableResult
    private func ensureReady() -> Bool {
        guard modelReady else { statusText = readinessStatus; return false }
        do { try transcriptionEngine.checkInstallation() }
        catch {
            let token = readiness.begin(engineID: transcriptionEngine.rawValue)
            readiness.complete(token, error: error.localizedDescription)
            statusText = readinessStatus
            return false
        }
        return true
    }

    func handleFnAction(_ action: PushToTalkAction) {
        switch action {
        case .none:
            break
        case .start, .compressStart:
            guard !isRecording, !operationInProgress else { return }
            guard ensureReady() else {
                blockedHUDVisible = true
                return
            }
            blockedHUDVisible = false
            recordingStartedByFn = true
            fnReleasedDuringStartup = false
            compressMode = action == .compressStart
            Task {
                await startRecording(triggeredByFn: true, forceMeetingAudio: false)
            }
        case .stop, .compressStop:
            blockedHUDVisible = false
            guard recordingStartedByFn else {
                return
            }
            if !isRecording {
                fnReleasedDuringStartup = true
            } else {
                stopRecording()
            }
        case .toggle:
            switch MeetingToggle.result(isRecording: isRecording || operationInProgress, startedByHold: recordingStartedByFn) {
            case .start:
                guard ensureReady() else { return }
                if operationInProgress {
                    statusText = "Still starting the previous recording…"
                    return
                }
                Task {
                    await startRecording(triggeredByFn: false, forceMeetingAudio: true)
                }
            case .latch:
                recordingStartedByFn = false
                fnReleasedDuringStartup = false
                statusText = "Recording microphone + Mac audio — Fn+R to stop"
            case .stop:
                stopRecording()
            }
        }
    }

    private func startRecording(triggeredByFn: Bool, forceMeetingAudio: Bool) async {
        guard !isRecording, !operationInProgress, ensureReady(), let archive else { return }
        let token = readiness.generation
        sessionEngine = transcriptionEngine
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
        guard readiness.generation == token, modelReady else {
            statusText = readinessStatus
            isBusy = false
            operationInProgress = false
            recordingStartedByFn = false
            return
        }

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
                if whisperKitReady {
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
                    streamingActive = true
                    } catch {
                        // Live preview is optional, even when its decoder was validated.
                        // A microphone/stream-start failure gets an independent WAV attempt.
                        try micRecorder.start(at: session.audioURL)
                        streamingActive = false
                        whisperKitReady = false
                    }
                } else {
                    // whisper.cpp / Qwen3 with no WhisperKit: record mic directly to WAV.
                    try micRecorder.start(at: session.audioURL)
                    streamingActive = false
                }
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

            let captureMeeting = meetingCaptureEnabled || forceMeetingAudio
            var captureStartLog: [String] = []
            if captureMeeting {
                let t0 = Date()
                if !systemAudioGranted {
                    systemAudioGranted = SystemAudioCapture.requestPermission()
                    captureStartLog.append(systemAudioGranted ? "permission-ok" : "permission-denied")
                }
                if systemAudioGranted {
                    var capture = SystemAudioCapture()
                    var started = false
                    for attempt in 0..<3 {
                        if attempt > 0 {
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            capture = SystemAudioCapture()
                        }
                        do {
                            try await capture.start()
                            systemAudioCapture = capture
                            captureStartLog.append("attempt\(attempt + 1)-ok+\(String(format: "%.2f", Date().timeIntervalSince(t0)))s")
                            started = true
                            break
                        } catch {
                            captureStartLog.append("attempt\(attempt + 1)-failed(\(error.localizedDescription))")
                        }
                    }
                    if !started {
                        // Another app (browser screen-share, Zoom, OBS) likely holds the
                        // ScreenCaptureKit session. Keep recording mic-only — never block.
                        systemAudioCapture = nil
                        transcriptionHUDTitle = "Mac audio busy in another app — microphone only"
                    }
                } else {
                    transcriptionHUDTitle = "Mac audio permission needed — microphone only"
                }
            }
            Logger(subsystem: "de.emin.DictateMac", category: "Meeting").notice("meeting start: \(captureMeeting) [\(captureStartLog.joined(separator: ","))]")

            currentSessionAutoPasteEnabled = autoPasteEnabled
            session.metadata.autoPasteEnabled = currentSessionAutoPasteEnabled
            session.metadata.meetingCaptureEnabled = captureMeeting
            session.metadata.systemAudioCaptured = systemAudioCapture != nil
            try archive.writeMetadata(for: session)
            currentSession = session
            isRecording = true
            if transcriptionHUDTitle == "Starting recording…" {
                transcriptionHUDTitle = streamingActive
                    ? "Recording — listening…"
                    : "Recording — live preview unavailable"
            }
            isLatchedRecordingPublished = !triggeredByFn
            isBusy = false
            operationInProgress = false
            if captureMeeting, systemAudioCapture != nil {
                statusText = triggeredByFn
                    ? "Recording microphone + Mac audio — release Fn to stop"
                    : "Recording microphone + Mac audio — Fn+R to stop"
            } else {
                statusText = triggeredByFn ? "Recording — release Fn to stop" : "Recording — Fn+R to stop"
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
        isLatchedRecordingPublished = false
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
            transcriptionHUDTitle = "Transcribing locally, please wait…"
            statusText = "Transcribing locally, please wait…"
            if streamingActive {
                _ = try await transcriber.stopStreamingAndSave(
                    to: session.audioURL,
                    systemAudio: systemAudio
                )
            } else {
                micRecorder.stop()
            }
            streamingActive = false
            // Full-file pass: pick the engine the user selected. Qwen3-ASR reads the
            // saved WAV directly; WhisperKit keeps its in-process samples path.
            let rawTranscript: String
            switch sessionEngine {
            case .qwen3ASR:
                let qwen = try await QwenASRService.transcribe(wavURL: session.audioURL)
                session.metadata.model = qwen.model
                rawTranscript = qwen.text
            case .whisperCpp:
                let wcpp = try await WhisperCppService.transcribe(wavURL: session.audioURL)
                session.metadata.model = wcpp.model
                rawTranscript = wcpp.text
            case .whisperKit:
                rawTranscript = try await transcriber.transcribe(wavURL: session.audioURL)
            }
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

            // Fn+A: compress to a minimal numbered list before delivering.
            var deliveredText = finalTranscript
            if compressMode {
                transcriptionHUDTitle = "Compressing locally"
                statusText = "Compressing — qwen3 via Ollama"
                if let compressed = try? await CompressService.compress(finalTranscript) {
                    deliveredText = compressed.compressed
                    latestTranscript = compressed.compressed
                    liveConfirmedText = compressed.compressed
                } else {
                    // Fallback: deliver the full transcript rather than nothing.
                    statusText = "Compression unavailable — full transcript delivered"
                }
            }
            compressMode = false
            latestTranscript = deliveredText
            usefulContext = enhancementResult.enhancement?.usefulContext ?? []
            liveConfirmedText = deliveredText
            liveProvisionalText = ""
            transcriptionHUDTitle = "Copying transcript"
            statusText = "Delivering final transcript"
            // Re-resolve the target at delivery time: paste into whatever the user
            // is working in NOW, not where the take started.
            let deliveryTarget = targetTracker.targetApplication() ?? targetApplication
            let delivery = await TranscriptDeliveryService.deliver(
                deliveredText,
                to: deliveryTarget,
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
            if sessionEngine == transcriptionEngine, !(error is DictationError) {
                let token = readiness.begin(engineID: transcriptionEngine.rawValue)
                readiness.complete(token, error: error.localizedDescription)
            }
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
        transcriptionHUDTitle = "Starting recording…"
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

private enum AudioConversionError: LocalizedError {
    case afconvertFailed(exit: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .afconvertFailed(let exit, let message):
            "Audio conversion failed (exit \(exit)): \(message)"
        }
    }
}
