import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: DictationController
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
        .frame(width: 520, height: 600)
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
