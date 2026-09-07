import SwiftUI
import DictateMacCore
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var controller: DictationController
    @State private var apiKeyDraft = ""
    @State private var showAdvanced = false
    @State private var showFilePicker = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                SessionActivityView(controller: controller)
                HStack {
                    Text(controller.readinessStatus).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("engine-readiness-status")
                    if controller.readiness.error != nil {
                        Button("Retry setup") { controller.retryReadiness() }.disabled(controller.hasActiveWork)
                    }
                }

                Button(action: { controller.toggleRecording() }) {
                    Label(controller.recordButtonTitle, systemImage: controller.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(controller.isRecording ? .red : .accentColor)
                .disabled(!controller.canToggleRecording)
                .accessibilityIdentifier("record-or-stop")

                Button(action: { showFilePicker = true }) {
                    Label("Transcribe file", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(!controller.canTranscribeFile)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Sessions").fontWeight(.semibold)
                    if controller.sessions.isEmpty {
                        Text("Your recordings will appear here.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(controller.sessions.sorted { $0.metadata.startedAt > $1.metadata.startedAt }, id: \.metadata.sessionID) { session in
                            sessionRow(session)
                            Divider()
                        }
                    }
                }
                .accessibilityIdentifier("all-sessions")

                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Recording works without a transcription model.")
                            .fixedSize(horizontal: false, vertical: true)
                        Text(controller.readinessStatus)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("engine-readiness-status")
                        if controller.readiness.isLoading { ProgressView().controlSize(.small) }
                        if let error = controller.readiness.error {
                            Text(error).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            Button("Retry transcription setup") { controller.retryReadiness() }
                                .disabled(controller.hasActiveWork)
                        }
                        Toggle("Paste automatically", isOn: $controller.autoPasteEnabled)
                            .toggleStyle(.switch)
                        Toggle("Include computer audio", isOn: $controller.meetingCaptureEnabled)
                            .toggleStyle(.switch)
                            .disabled(controller.hasActiveWork)
                            .onChange(of: controller.meetingCaptureEnabled) { _, enabled in
                                if enabled, !controller.systemAudioGranted {
                                    controller.requestSystemAudioPermission()
                                }
                            }
                        Picker("Quality", selection: $controller.transcriptionEngine) {
                            ForEach(TranscriptionEngine.allCases) { engine in
                                Text(engine.displayName).tag(engine)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(controller.hasActiveWork)
                        Toggle("Correct names", isOn: $controller.aiEnhancementEnabled)
                            .toggleStyle(.switch)
                        SecureField("AI key", text: $apiKeyDraft)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(saveKey)
                        if !controller.microphoneGranted {
                            Button("Allow microphone") { controller.requestMicrophonePermission() }
                        }
                        if !controller.systemAudioGranted {
                            Button("Allow computer audio") { controller.requestSystemAudioPermission() }
                        }
                        if !controller.accessibilityGranted {
                            Button("Allow paste") { controller.requestAccessibilityPermission() }
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .font(.system(size: 17, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(width: 440, height: 620)
        .onAppear {
            controller.refreshSessions()
            controller.refreshAccessibilityPermission()
            controller.refreshRecordingPermissions()
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio, .movie, .audiovisualContent],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                controller.transcribeAudioFile(url)
            }
        }
    }

    private func sessionRow(_ session: DictationSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.metadata.headline?.isEmpty == false ? session.metadata.headline! : session.metadata.startedAt.formatted(date: .abbreviated, time: .shortened))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text(session.metadata.startedAt.formatted(date: .abbreviated, time: .shortened) + (session.metadata.durationSeconds.map { " · " + SessionActivityPresentation.duration($0) } ?? ""))
                .foregroundStyle(.secondary)
            Text(SessionActivityPresentation.status(session.metadata.status.rawValue))
                .foregroundStyle(Color(nsColor: SessionActivityPresentation.color(session.metadata.status.rawValue)))
                .fixedSize(horizontal: false, vertical: true)
            if let warning = session.metadata.captureWarning { Text(warning).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            if let error = session.metadata.error, !error.isEmpty, !error.hasPrefix("Audio saved. Loading ") {
                Text(error)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            // Separate short rows keep every action visible without horizontal scrolling.
            HStack(spacing: 14) {
                Button("Show audio") { controller.revealAudioInFolder(session.metadata.sessionID) }
                if session.metadata.status == .completed {
                    Button("Copy") { controller.copySessionTranscript(session.metadata.sessionID) }
                    Button("Open") { controller.openTranscript(session.metadata.sessionID) }
                }
            }
            .buttonStyle(.borderless)
            if session.metadata.status != .completed {
                Button(session.metadata.status == .saved ? "Transcribe" : "Retry transcription") {
                    controller.retryTranscription(session.metadata.sessionID)
                }
                .disabled(!controller.canRetryTranscription)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("session-\(session.metadata.sessionID)")
    }

    private func saveKey() {
        controller.saveOpenRouterAPIKey(apiKeyDraft)
        apiKeyDraft = ""
    }
}
