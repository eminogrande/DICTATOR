import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var controller: DictationController
    @State private var apiKeyDraft = ""
    @State private var showAISettings = false
    @State private var showFilePicker = false

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

                // Primary actions: record (mic) + transcribe a file.
                HStack(spacing: 10) {
                    Button(controller.recordButtonTitle) {
                        controller.toggleRecording()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!controller.canToggleRecording)

                    Button("Transcribe Audio File…") {
                        showFilePicker = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(controller.isRecording)
                }

                Text("Record = microphone (release Fn to stop). File = pick an audio file to transcribe.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)

                if controller.isTranscribingFile {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: controller.fileProgress)
                            .progressViewStyle(.linear)
                        Text(controller.filePartialText.isEmpty ? "Transcribing…" : controller.filePartialText)
                            .font(.system(size: 15))
                            .lineLimit(4)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button("Stop", role: .destructive) {
                            controller.cancelFileTranscription()
                        }
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }

                Divider()

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

                Picker("Transcription engine", selection: $controller.transcriptionEngine) {
                    ForEach(TranscriptionEngine.allCases) { engine in
                        Text(engine.displayName)
                            .tag(engine)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(engineHint)
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)

                Divider()

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

                if !recentTranscripts.isEmpty {
                    Divider()
                    Text("Recent transcripts")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                    ForEach(recentTranscripts, id: \.id) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.headline)
                                .font(.system(size: 15))
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 8)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.text, forType: .string)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
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
            }
            .padding(16)
        }
        .font(.system(size: 17))
        .frame(width: 520, height: 640)
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

    private var engineHint: String {
        switch controller.transcriptionEngine {
        case .whisperCpp:
            controller.transcriptionEngine.isAvailable
                ? "Whisper large-v3-turbo via whisper.cpp (Metal). Fastest full-file pass, German + English."
                : "Not installed — run the Tools installer, falling back to WhisperKit."
        case .whisperKit:
            "Built-in WhisperKit large-v3_turbo. Always available."
        case .qwen3ASR:
            controller.transcriptionEngine.isAvailable
                ? "Best German accuracy (Qwen3-ASR 0.6B via local MLX). Slowest of the three."
                : "Not installed — run the Tools installer, falling back to WhisperKit."
        }
    }

    private var recentTranscripts: [(id: String, headline: String, text: String)] {
        controller.recentTranscriptsForMenu(limit: 8).map { entry in
            (id: entry.displayTitle, headline: entry.displayTitle, text: entry.text)
        }
    }
}
