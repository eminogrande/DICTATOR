import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var controller: DictationController
    @State private var apiKeyDraft = ""
    @State private var showAdvanced = false
    @State private var showFilePicker = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        if controller.readiness.isLoading { ProgressView().controlSize(.small) }
                        Text(controller.hasActiveWork ? controller.statusText : controller.readinessStatus)
                            .font(.system(size: 17))
                            .accessibilityIdentifier("engine-readiness-status")
                        if controller.readiness.error != nil {
                            Button("Retry") { controller.retryReadiness() }
                                .disabled(controller.hasActiveWork)
                        }
                    }

                    // Record — the one thing that matters.
                    Button(action: { controller.toggleRecording() }) {
                        Label(controller.recordButtonTitle, systemImage: controller.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(controller.isRecording ? .red : .accentColor)
                    .disabled(!controller.canToggleRecording)

                    // Transcribe a file.
                    Button(action: { showFilePicker = true }) {
                        Label("Transcribe file", systemImage: "doc.badge.plus")
                            .font(.system(size: 17, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!controller.canTranscribeFile)

                    if controller.isTranscribingFile {
                        VStack(alignment: .leading, spacing: 10) {
                            ProgressView(value: controller.fileProgress)
                                .progressViewStyle(.linear)
                            HStack {
                                Text(controller.filePartialText.isEmpty ? "…" : controller.filePartialText)
                                    .font(.system(size: 15))
                                    .lineLimit(2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Stop", role: .destructive) { controller.cancelFileTranscription() }
                            }
                        }
                        .padding(14)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                    }

                    // Transcripts.
                    if !recentTranscripts.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(recentTranscripts, id: \.id) { entry in
                                HStack {
                                    Text(entry.headline)
                                        .font(.system(size: 16))
                                        .lineLimit(1)
                                    Spacer()
                                    Button {
                                        controller.revealTranscriptInFolder(entry.id)
                                    } label: {
                                        Image(systemName: "folder")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Show in Finder")
                                    Button("Copy") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(entry.text, forType: .string)
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.tint)
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }

                    // Everything technical, collapsed.
                    DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle("Paste automatically", isOn: $controller.autoPasteEnabled)
                                .toggleStyle(.switch)
                            Toggle("Include computer audio", isOn: $controller.meetingCaptureEnabled)
                                .toggleStyle(.switch)
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
                            .pickerStyle(.segmented)
                            .disabled(controller.hasActiveWork)
                            if let error = controller.readiness.error {
                                Text(error).font(.system(size: 17)).textSelection(.enabled)
                            }

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
                .padding(20)
            }
        }
        .frame(width: 420, height: 520)
        .onAppear {
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

    private func saveKey() {
        controller.saveOpenRouterAPIKey(apiKeyDraft)
        apiKeyDraft = ""
    }

    private var recentTranscripts: [(id: String, headline: String, text: String)] {
        controller.recentTranscriptsForMenu(limit: 6).map { entry in
            (id: entry.id, headline: entry.displayTitle, text: entry.text)
        }
    }
}
