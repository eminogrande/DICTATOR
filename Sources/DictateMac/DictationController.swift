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
    @Published private(set) var sessions: [DictationSession] = []
    @Published private(set) var activityPhase = "idle"
    @Published private(set) var activityStartedAt: Date?
    @Published private(set) var recordingElapsed: TimeInterval = 0
    @Published private(set) var microphoneLevel: Float = 0
    @Published private(set) var systemAudioLevel: Float = 0
    @Published private(set) var microphoneStatus = "Off"
    @Published private(set) var systemAudioStatus = "Off"
    @Published private(set) var activeSessionID: String?
    @Published private(set) var canCancelTranscription = false
    private var activityTimer: Timer?
    private var meetingSession = false
    private var meetingSystemTask: Task<Void, Never>?
    private var fileTranscriber: ((URL) async throws -> String)?
    private var pendingFnStart: Task<Void, Never>?
    private var meetingAfterStartup = false
    private var meetingAfterTranscription = false
    @Published private(set) var isMeetingStarting = false
    private var meetingStartupCancelled = false
    private var meetingPermission: (() async -> Bool)?

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
    var canTranscribeFile: Bool { !hasActiveWork }
    var canStartDictation: Bool { modelReady && !hasActiveWork }
    var canRetryTranscription: Bool { (modelReady || fileTranscriber != nil) && !hasActiveWork }
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
        isMeetingStarting ? "Cancel start" : (isRecording ? "Stop" : "Record")
    }

    var canToggleRecording: Bool {
        isRecording || isMeetingStarting || !operationInProgress || canCancelTranscription
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
         readinessValidator: ((TranscriptionEngine) async throws -> Void)? = nil,
         archiveStore: ArchiveStore? = nil,
         fileTranscriber: ((URL) async throws -> String)? = nil,
         meetingPermission: (() async -> Bool)? = nil) {
        self.meetingPermission = meetingPermission
        self.archive = archiveStore
        self.fileTranscriber = fileTranscriber
        self.settings = defaults
        self.readinessValidator = readinessValidator
        autoPasteEnabled = defaults.object(forKey: Self.autoPasteDefaultsKey) == nil
            ? true
            : defaults.bool(forKey: Self.autoPasteDefaultsKey)
        aiEnhancementEnabled = defaults.bool(forKey: Self.aiEnhancementDefaultsKey)
        meetingCaptureEnabled = defaults.object(forKey: Self.meetingCaptureDefaultsKey) == nil ? true : defaults.bool(forKey: Self.meetingCaptureDefaultsKey)
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
        guard startServices else { isBusy = false; refreshSessions(); return }
        hasOpenRouterAPIKey = ((try? keyStore.read()) ?? nil) != nil

        do {
            archive = try ArchiveStore()
            try archive?.recoverInterruptedSessions()
            refreshSessions()
            if let latest = sessions.first, latest.metadata.status != .completed {
                activityPhase = latest.metadata.status == .failed ? "failed" : "saved"
                statusText = latest.metadata.status == .failed ? "Transcription failed — audio saved" : "Audio saved — ready to transcribe"
            }
        } catch {
            statusText = "Archive unavailable: \(error.localizedDescription)"
            isBusy = false
            return
        }

        isBusy = false
        refreshReadiness()
        preparePreview()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateAudioActivity() }
        }
        RunLoop.main.add(timer, forMode: .common)
        activityTimer = timer

        fnKeyMonitor = FnKeyMonitor { [weak self] action in
            self?.handleFnAction(action)
        }
        fnKeyMonitor?.start()
        if !accessibilityGranted {
            TranscriptDeliveryService.requestAccessibilityPermission()
        }
    }

    func toggleRecording() {
        if isMeetingStarting { stopRecording(); return }
        if canCancelTranscription && !isRecording {
            meetingAfterTranscription = true
            cancelFileTranscription()
            return
        }
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

    /// Import first, then transcribe. A missing model must not hide the saved audio.
    func transcribeAudioFile(_ url: URL) {
        guard !hasActiveWork, let archive else { return }
        operationInProgress = true
        isBusy = true
        activityPhase = "saving"
        activityStartedAt = Date()
        statusText = "Saving audio…"
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var imported: DictationSession?
            do {
                var session = try archive.startSession(sourceApplication: "Audio File")
                imported = session
                activeSessionID = session.metadata.sessionID
                refreshSessions()
                let destination = session.audioURL
                try await Task.detached(priority: .utility) {
                    try Self.convertToWav16kMono(url, to: destination)
                }.value
                session.metadata.status = .saved
                session.metadata.durationSeconds = Self.audioDuration(destination)
                try archive.writeMetadata(for: session)
                refreshSessions()
                await transcribeSavedSession(session)
            } catch {
                if let imported { persistFailure(imported, error: error) }
                else { activityPhase = "failed"; statusText = error.localizedDescription }
            }
            finishBackgroundWork()
        }
    }

    func cancelFileTranscription() {
        guard canCancelTranscription else { return }
        activeFileTask?.cancel()
        statusText = "Stopping transcription — audio retained"
    }

    func refreshSessions() { sessions = archive?.sessions() ?? [] }

    func retryTranscription(_ id: String) {
        guard !hasActiveWork, let session = archive?.sessions().first(where: { $0.metadata.sessionID == id }) else { return }
        guard session.metadata.status != .completed else { return }
        operationInProgress = true
        isBusy = true
        activeSessionID = id
        Task {
            await transcribeSavedSession(session)
            finishBackgroundWork()
        }
    }

    func revealAudioInFolder(_ id: String) {
        guard let session = sessions.first(where: { $0.metadata.sessionID == id }) else { return }
        var files = [session.audioURL]
        if let name = session.metadata.systemAudioFilename { files.append(session.folderURL.appendingPathComponent(name)) }
        NSWorkspace.shared.activateFileViewerSelecting(files.filter { FileManager.default.fileExists(atPath: $0.path) })
    }

    func openTranscript(_ id: String) {
        guard let session = sessions.first(where: { $0.metadata.sessionID == id }) else { return }
        NSWorkspace.shared.open(session.transcriptURL)
    }

    func copySessionTranscript(_ id: String) {
        guard let session = sessions.first(where: { $0.metadata.sessionID == id }),
              let text = try? String(contentsOf: session.transcriptURL, encoding: .utf8), !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func transcribeSavedSession(_ original: DictationSession) async {
        guard let archive else { return }
        var session = original
        activeSessionID = session.metadata.sessionID
        activityStartedAt = Date()
        fileProgress = 0
        filePartialText = ""
        do {
            // Meetings/retries can outlive readiness startup. Never wait for a stuck preview.
            if fileTranscriber == nil && !modelReady {
                session.metadata.status = .saved
                session.metadata.error = nil
                try archive.writeMetadata(for: session)
                activityPhase = "saved"
                statusText = "Audio saved — ready to transcribe later"
                refreshSessions()
                return
            }
            session.metadata.status = .transcribing
            session.metadata.error = nil
            try archive.writeMetadata(for: session)
            refreshSessions()
            activityPhase = "transcribing"
            isTranscribingFile = true
            statusText = "Transcribing locally, please wait…"
            // Interrupted/mix-failed recordings still retain both source tracks for retry.
            if session.metadata.transcriptionAudioFilename == nil,
               let name = session.metadata.systemAudioFilename,
               FileManager.default.fileExists(atPath: session.folderURL.appendingPathComponent(name).path),
               (Self.audioDuration(session.folderURL.appendingPathComponent(name)) ?? 0) > 0 {
                let mic = session.audioURL
                let system = session.folderURL.appendingPathComponent(name)
                let mixed = mic.deletingPathExtension().appendingPathExtension("mixed-" + UUID().uuidString + ".wav")
                let offset = session.metadata.systemAudioOffset ?? 0
                try await Task.detached(priority: .utility) {
                    try MeetingAudioFile.mix(microphone: mic, system: system, destination: mixed, offset: offset)
                }.value
                session.metadata.transcriptionAudioFilename = mixed.lastPathComponent
                try archive.writeMetadata(for: session)
            }
            let audio = session.folderURL.appendingPathComponent(session.metadata.transcriptionAudioFilename ?? session.metadata.audioFilename)
            let text: String
            let engine = transcriptionEngine
            if let fileTranscriber {
                text = try await fileTranscriber(audio)
            } else {
                switch engine {
                case .whisperCpp:
                    let task = try WhisperCppFileTask(wavURL: audio)
                    activeFileTask = task
                    canCancelTranscription = true
                    text = try await task.run { [weak self] snapshot in
                        Task { @MainActor in
                            guard self?.activeSessionID == original.metadata.sessionID,
                                  self?.activityPhase == "transcribing" else { return }
                            self?.fileProgress = snapshot.fraction
                            self?.filePartialText = snapshot.text
                        }
                    }
                case .qwen3ASR:
                    text = try await QwenASRService.transcribe(wavURL: audio).text
                case .whisperKit:
                    text = try await transcriber.transcribe(wavURL: audio)
                }
            }
            let transcript = TranscriptCleaner.clean(text)
            guard !transcript.isEmpty else { throw DictationError.emptyTranscript }
            _ = try archive.saveTranscript(transcript, model: engine.rawValue, for: session)
            latestTranscript = transcript
            filePartialText = transcript
            fileProgress = 1
            activityPhase = "completed"
            statusText = "Transcript ready"
            // Background meeting/import/retry NEVER pastes into an unrelated application.
        } catch {
            if let error = error as? WhisperCppError, case .cancelled = error {
                session.metadata.status = .saved
                session.metadata.error = "Transcription stopped — audio retained"
                do { try archive.writeMetadata(for: session) }
                catch { statusText = "Could not save session status: " + error.localizedDescription }
                activityPhase = "saved"
                statusText = "Audio saved — transcription stopped"
            } else { persistFailure(session, error: error) }
        }
        refreshSessions()
    }

    private func persistFailure(_ original: DictationSession, error: Error) {
        var session = original
        session.metadata.status = .failed
        session.metadata.error = error.localizedDescription
        session.metadata.completedAt = Date()
        activityPhase = "failed"
        statusText = "Failed — audio retained. " + error.localizedDescription
        do { try archive?.writeMetadata(for: session) }
        catch { statusText += " Status save failed: " + error.localizedDescription }
        refreshSessions()
    }

    private func finishBackgroundWork() {
        isBusy = false
        operationInProgress = false
        isTranscribingFile = false
        activeFileTask = nil
        canCancelTranscription = false
        activeSessionID = nil
        refreshSessions()
        if meetingAfterTranscription {
            meetingAfterTranscription = false
            Task { await startMeeting(includeSystemAudio: meetingCaptureEnabled) }
        }
    }

    nonisolated private static func audioDuration(_ url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
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
        if !hasActiveWork && activityPhase == "idle" { statusText = readinessStatus }
        // A stuck optional/Built-in load must not delay a newly selected sidecar.
        // Generation tokens reject superseded probe results.
        readinessTask = Task { [weak self] in
            guard let self, self.readiness.generation == token else { return }
            let deadline = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 180_000_000_000)
                guard !Task.isCancelled, let self else { return }
                self.readiness.complete(token, error: "Loading timed out. Retry or choose another quality.")
                if !self.hasActiveWork && self.activityPhase == "idle" { self.statusText = self.readinessStatus }
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
            if self.readiness.generation == token && !self.hasActiveWork && self.activityPhase == "idle" {
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
            pendingFnStart?.cancel()
            pendingFnStart = Task {
                // Give Fn+R a short chord window before allocating a quick-take recorder.
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled, !fnReleasedDuringStartup else { return }
                await startRecording(triggeredByFn: true, forceMeetingAudio: false)
            }
        case .stop, .compressStop:
            blockedHUDVisible = false
            if meetingAfterStartup { return }
            guard recordingStartedByFn else {
                return
            }
            if !isRecording {
                fnReleasedDuringStartup = true
            } else {
                stopRecording()
            }
        case .toggle:
            if canCancelTranscription && !isRecording {
                meetingAfterTranscription = true
                cancelFileTranscription()
                return
            }
            if !operationInProgress { pendingFnStart?.cancel() }
            pendingFnStart = nil
            blockedHUDVisible = false
            switch MeetingToggle.result(isRecording: isRecording || operationInProgress, startedByHold: recordingStartedByFn) {
            case .start:
                if operationInProgress {
                    statusText = "Still starting the previous recording…"
                    return
                }
                Task {
                    await startRecording(triggeredByFn: false, forceMeetingAudio: true)
                }
            case .latch:
                // Preserve an already-started quick take, then switch to durable meeting capture.
                guard isRecording else { meetingAfterStartup = true; return }
                recordingStartedByFn = false
                fnReleasedDuringStartup = false
                isRecording = false
                operationInProgress = true
                Task { await saveQuickTakeAndStartMeeting() }
            case .stop:
                stopRecording()
            }
        }
    }

    private func startRecording(triggeredByFn: Bool, forceMeetingAudio: Bool) async {
        if !triggeredByFn {
            await startMeeting(includeSystemAudio: meetingCaptureEnabled || forceMeetingAudio)
            return
        }
        guard !isRecording, !operationInProgress, ensureReady(), let archive else { return }
        meetingSession = false
        activityPhase = "starting"
        activityStartedAt = Date()
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

            // Quick Fn is microphone-only: no Mac audio startup or meeting resources.
            let captureMeeting = false

            currentSessionAutoPasteEnabled = autoPasteEnabled
            session.metadata.autoPasteEnabled = currentSessionAutoPasteEnabled
            session.metadata.meetingCaptureEnabled = captureMeeting
            session.metadata.systemAudioCaptured = systemAudioCapture != nil
            try archive.writeMetadata(for: session)
            currentSession = session
            activeSessionID = session.metadata.sessionID
            refreshSessions()
            isRecording = true
            activityPhase = "recording"
            activityStartedAt = microphoneStartedAt
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
            if meetingAfterStartup {
                meetingAfterStartup = false
                isRecording = false
                operationInProgress = true
                await saveQuickTakeAndStartMeeting()
                return
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
        if isMeetingStarting {
            meetingStartupCancelled = true
            statusText = "Cancelling recording start…"
            return
        }
        if meetingSession { stopMeeting(); return }
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
        activityPhase = "saving"
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
            activityPhase = "transcribing"
            activityStartedAt = Date()
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
            activityPhase = "completed"
            refreshSessions()

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
            activityPhase = "failed"
            refreshSessions()
            statusText = "Transcription failed: \(error.localizedDescription)"
            if sessionEngine == transcriptionEngine, !(error is DictationError) {
                let token = readiness.begin(engineID: transcriptionEngine.rawValue)
                readiness.complete(token, error: error.localizedDescription)
            }
        }

        stopLivePresentation()
        currentSession = nil
        targetApplication = nil
        activeSessionID = nil
        isBusy = false
        operationInProgress = false
        refreshSessions()
    }

    private func updateAudioActivity() {
        guard isRecording else { return }
        recordingElapsed = max(0, Date().timeIntervalSince(microphoneStartedAt ?? Date()))
        microphoneLevel = streamingActive ? (liveAudioProgress.waveform.last ?? 0) : micRecorder.level
        microphoneStatus = (!streamingActive && !micRecorder.isRecording) ? "Not recording" : (microphoneLevel > 0.01 ? "Receiving audio" : "Quiet")
        if let capture = systemAudioCapture {
            systemAudioLevel = capture.level
            if let error = capture.captureError { systemAudioStatus = error }
            else if capture.hasReceivedAudio { systemAudioStatus = systemAudioLevel > 0.01 ? "Receiving audio" : "Quiet" }
        }
    }

    private func startMeeting(includeSystemAudio: Bool) async {
        guard !hasActiveWork, let archive else { return }
        isMeetingStarting = true
        meetingStartupCancelled = false
        defer { isMeetingStarting = false }
        operationInProgress = true
        isBusy = true
        activityPhase = "starting"
        activityStartedAt = Date()
        blockedHUDVisible = false
        statusText = "Starting microphone…"
        let granted: Bool
        if let meetingPermission { granted = await meetingPermission() }
        else { granted = await AudioRecorder.requestPermission() }
        guard !meetingStartupCancelled else {
            activityPhase = "idle"
            statusText = "Recording start cancelled"
            finishBackgroundWork()
            return
        }
        guard granted else {
            microphoneGranted = false
            activityPhase = "failed"
            statusText = "Microphone denied — allow it in System Settings"
            finishBackgroundWork()
            return
        }
        microphoneGranted = true
        do {
            var session = try archive.startSession(sourceApplication: "Meeting")
            session.metadata.autoPasteEnabled = false
            session.metadata.meetingCaptureEnabled = includeSystemAudio
            session.metadata.systemAudioCaptured = false
            try archive.writeMetadata(for: session)
            currentSession = session
            activeSessionID = session.metadata.sessionID
            refreshSessions()
            try micRecorder.start(at: session.audioURL)
            // From this point audio is on disk. No ML or SCK wait can block Stop/UI.
            microphoneStartedAt = Date()
            activityStartedAt = microphoneStartedAt
            recordingElapsed = 0
            microphoneLevel = 0
            systemAudioLevel = 0
            microphoneStatus = "Listening"
            systemAudioStatus = includeSystemAudio ? "Starting…" : "Off"
            recordingStartedByFn = false
            fnReleasedDuringStartup = false
            compressMode = false
            meetingSession = true
            streamingActive = false
            isRecording = true
            isLatchedRecordingPublished = true
            operationInProgress = false
            isBusy = false
            activityPhase = "recording"
            statusText = "Recording meeting — audio saved to disk"
            if includeSystemAudio { startMeetingSystemAudio(for: session) }
        } catch {
            micRecorder.stop()
            if let session = currentSession { persistFailure(session, error: error) }
            else { activityPhase = "failed"; statusText = error.localizedDescription }
            currentSession = nil
            finishBackgroundWork()
        }
    }

    private func startMeetingSystemAudio(for session: DictationSession) {
        let id = session.metadata.sessionID
        meetingSystemTask = Task {
            guard !Task.isCancelled, isRecording, currentSession?.metadata.sessionID == id else { return }
            guard SystemAudioCapture.isAuthorized else {
                systemAudioStatus = "Unavailable — allow computer audio"
                return
            }
            let audioURL = session.audioURL.deletingPathExtension().appendingPathExtension("system.wav")
            let capture = SystemAudioCapture()
            systemAudioCapture = capture
            let start = Date()
            do {
                // Persist the side-track path before capture begins so relaunch can find it.
                if var current = currentSession, current.metadata.sessionID == id {
                    current.metadata.systemAudioFilename = audioURL.lastPathComponent
                    current.metadata.systemAudioOffset = max(0, start.timeIntervalSince(microphoneStartedAt ?? start))
                    try archive?.writeMetadata(for: current)
                    currentSession = current
                    refreshSessions()
                }
                try await capture.start(at: audioURL)
                guard isRecording, currentSession?.metadata.sessionID == id, !Task.isCancelled else {
                    await capture.stopToFile()
                    return
                }
                systemAudioStatus = "Listening"
            } catch {
                guard isRecording, currentSession?.metadata.sessionID == id else { return }
                systemAudioStatus = "Unavailable — microphone only"
                statusText = "Recording microphone — Mac audio unavailable: " + error.localizedDescription
            }
        }
    }

    private func stopMeeting() {
        guard isRecording, let session = currentSession else { return }
        recordingElapsed = max(0, Date().timeIntervalSince(microphoneStartedAt ?? Date()))
        micRecorder.stop() // finalize primary WAV immediately, before ANY asynchronous work
        isRecording = false
        isLatchedRecordingPublished = false
        operationInProgress = true
        isBusy = true
        activityPhase = "saving"
        activityStartedAt = Date()
        statusText = "Saving meeting audio…"
        meetingSystemTask?.cancel()
        Task {
            var saved = session
            if let capture = systemAudioCapture {
                await capture.stopToFile()
                saved.metadata.systemAudioCaptured = capture.hasReceivedAudio
                saved.metadata.captureWarning = capture.captureError
                if !capture.hasReceivedAudio { saved.metadata.captureWarning = "No Mac audio received — microphone recording retained" }
                if let started = microphoneStartedAt { saved.metadata.systemAudioOffset = capture.offset(relativeTo: started) }
            }
            await meetingSystemTask?.value
            meetingSystemTask = nil
            systemAudioCapture = nil
            microphoneStartedAt = nil
            if saved.metadata.meetingCaptureEnabled == true && saved.metadata.systemAudioCaptured != true {
                saved.metadata.captureWarning = "Mac audio unavailable — microphone recording retained"
            }
            saved.metadata.durationSeconds = Self.audioDuration(saved.audioURL) ?? recordingElapsed
            saved.metadata.status = .saved
            do {
                try archive?.writeMetadata(for: saved)
                refreshSessions()
                // Mix a separate derived file. Mic and Mac source tracks are never overwritten.
                if saved.metadata.systemAudioCaptured == true, let name = saved.metadata.systemAudioFilename {
                    let mic = saved.audioURL
                    let system = saved.folderURL.appendingPathComponent(name)
                    let mixed = mic.deletingPathExtension().appendingPathExtension("mixed.wav")
                    let offset = saved.metadata.systemAudioOffset ?? 0
                    try await Task.detached(priority: .utility) {
                        try MeetingAudioFile.mix(microphone: mic, system: system, destination: mixed, offset: offset)
                    }.value
                    saved.metadata.transcriptionAudioFilename = mixed.lastPathComponent
                    try archive?.writeMetadata(for: saved)
                }
                currentSession = nil
                meetingSession = false
                await transcribeSavedSession(saved)
            } catch {
                persistFailure(saved, error: error)
            }
            currentSession = nil
            meetingSession = false
            finishBackgroundWork()
        }
    }

    /// Fn+R after a quick take already started: retain that take before switching capture.
    private func saveQuickTakeAndStartMeeting() async {
        guard var session = currentSession else { operationInProgress = false; return }
        do {
            let system: CapturedSystemAudio?
            if let capture = systemAudioCapture, let started = microphoneStartedAt {
                system = await capture.stop(relativeTo: started)
            } else { system = nil }
            if streamingActive { _ = try await transcriber.stopStreamingAndSave(to: session.audioURL, systemAudio: system) }
            else { micRecorder.stop() }
            session.metadata.status = .saved
            session.metadata.durationSeconds = Self.audioDuration(session.audioURL)
            try archive?.writeMetadata(for: session)
        } catch { persistFailure(session, error: error) }
        streamingActive = false
        systemAudioCapture = nil
        currentSession = nil
        microphoneStartedAt = nil
        stopLivePresentation()
        operationInProgress = false
        refreshSessions()
        await startMeeting(includeSystemAudio: true)
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
