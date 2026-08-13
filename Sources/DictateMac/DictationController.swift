import AppKit
import Combine
import DictateMacCore
import Foundation

@MainActor
final class DictationController: ObservableObject {
    @Published private(set) var statusText = "Loading/downloading large-v3-turbo…"
    @Published private(set) var latestTranscript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var isBusy = true
    @Published private(set) var accessibilityGranted = TranscriptDeliveryService.isAccessibilityGranted

    private let recorder = AudioRecorder()
    private let transcriber = LocalTranscriber()
    private let targetTracker = TargetApplicationTracker()
    private var archive: ArchiveStore?
    private var currentSession: DictationSession?
    private var targetApplication: NSRunningApplication?
    private var modelReady = false
    private var operationInProgress = false
    private var fnKeyMonitor: FnKeyMonitor?
    private var recordingStartedByFn = false
    private var fnReleasedDuringStartup = false

    var recordButtonTitle: String {
        isRecording ? "Stop" : "Record"
    }

    var canToggleRecording: Bool {
        isRecording || (modelReady && !operationInProgress)
    }

    var accessibilityButtonTitle: String {
        accessibilityGranted ? "Accessibility Granted" : "Enable Accessibility…"
    }

    init() {
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
            statusText = "Microphone denied — allow it in System Settings"
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
            do {
                try recorder.start(at: session.audioURL)
            } catch {
                session.metadata.status = .failed
                session.metadata.completedAt = Date()
                session.metadata.error = error.localizedDescription
                try? archive.writeMetadata(for: session)
                throw error
            }

            currentSession = session
            targetApplication = target
            isRecording = true
            isBusy = false
            operationInProgress = false
            statusText = triggeredByFn ? "Recording… release Fn to stop" : "Recording…"
            if triggeredByFn && fnReleasedDuringStartup {
                fnReleasedDuringStartup = false
                stopRecording()
            }
        } catch {
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
        recorder.stop()
        recordingStartedByFn = false
        fnReleasedDuringStartup = false
        isRecording = false
        isBusy = true
        operationInProgress = true
        statusText = "Transcribing locally…"

        Task {
            await finishDictation()
        }
    }

    private func finishDictation() async {
        guard var session = currentSession, let archive else {
            statusText = "Session unavailable"
            isBusy = false
            operationInProgress = false
            return
        }

        session.metadata.status = .transcribing
        try? archive.writeMetadata(for: session)

        do {
            let rawTranscript = try await transcriber.transcribe(audioURL: session.audioURL)
            let transcript = TranscriptCleaner.clean(rawTranscript)
            guard !transcript.isEmpty else {
                throw DictationError.emptyTranscript
            }

            try archive.writeTranscript(transcript, for: session)
            latestTranscript = transcript
            let delivery = await TranscriptDeliveryService.deliver(
                transcript,
                to: targetApplication
            )

            session.metadata.status = .completed
            session.metadata.completedAt = Date()
            session.metadata.delivery = delivery
            session.metadata.error = nil
            try archive.writeMetadata(for: session)

            refreshAccessibilityPermission()
            switch delivery {
            case .pasted:
                statusText = "Pasted into \(targetApplication?.localizedName ?? "target app")"
            case .copied:
                statusText = accessibilityGranted
                    ? "Copied — target app unavailable"
                    : "Copied — enable Accessibility to auto-paste"
            }
        } catch {
            session.metadata.status = .failed
            session.metadata.completedAt = Date()
            session.metadata.error = error.localizedDescription
            try? archive.writeMetadata(for: session)
            statusText = "Transcription failed: \(error.localizedDescription)"
        }

        currentSession = nil
        targetApplication = nil
        isBusy = false
        operationInProgress = false
    }
}

private enum DictationError: LocalizedError {
    case emptyTranscript

    var errorDescription: String? {
        "No speech was recognized."
    }
}
