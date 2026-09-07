import SwiftUI

/// Technical controls stay out of the everyday recording workspace.
struct RecordingPreferencesView: View {
    @ObservedObject var controller: DictationController
    let openBrain: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var apiKeyDraft = ""
    @State private var keySaved = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Einstellungen").font(.system(size: 18, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("close-recording-preferences")
            }
            .padding(20)
            Divider()
            Form {
                Section("Aufnahme") {
                    Toggle("Mac-Audio mit aufnehmen", isOn: $controller.meetingCaptureEnabled)
                        .disabled(controller.hasActiveWork)
                        .help("Zusätzlich zum Mikrofon den Ton des Mac aufnehmen")
                        .accessibilityIdentifier("include-computer-audio")
                        .onChange(of: controller.meetingCaptureEnabled) { _, enabled in
                            if enabled && !controller.systemAudioGranted { controller.requestSystemAudioPermission() }
                        }
                    Toggle("Text automatisch einfügen", isOn: $controller.autoPasteEnabled)
                        .help("Fertige Diktate in die zuvor aktive App einfügen")
                        .accessibilityIdentifier("auto-paste-enabled")
                    Text("Aufnahmen sind auch ohne eingerichtete Transkription möglich.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Section("Transkription") {
                    Picker("Qualität", selection: $controller.transcriptionEngine) {
                        ForEach(TranscriptionEngine.allCases) { engine in
                            Text(engineLabel(engine)).tag(engine)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(controller.hasActiveWork)
                    .accessibilityIdentifier("transcription-quality")
                    HStack {
                        if controller.readiness.isLoading { ProgressView().controlSize(.small) }
                        Text(controller.readiness.isLoading ? "Wird vorbereitet …" : controller.readiness.error != nil ? "Einrichtung erforderlich" : "Bereit · zum Diktieren Fn gedrückt halten")
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("engine-readiness-status")
                    }
                    if let error = controller.readiness.error {
                        DisclosureGroup("Details zur Einrichtung") {
                            Text(error).font(.system(size: 12))
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        Button("Einrichtung erneut versuchen") { controller.retryReadiness() }
                            .disabled(controller.hasActiveWork)
                            .accessibilityIdentifier("retry-transcription-setup")
                    }
                }
                Section("Weitere Funktionen") {
                    Button("Aufnahmeordner öffnen") { controller.openArchive() }
                        .accessibilityIdentifier("open-recording-folder")
                    Button("Wissensarchiv öffnen") {
                        dismiss()
                        openBrain()
                    }
                    .accessibilityIdentifier("open-knowledge-archive")
                }
                Section("Tastenkürzel") {
                    LabeledContent("Diktieren", value: "Fn gedrückt halten")
                    LabeledContent("Kurz zusammenfassen", value: "Fn + A")
                    LabeledContent("Aufnahme starten / stoppen", value: "Fn + R")
                }
                Section("Text verbessern") {
                    Toggle("Namen mit KI korrigieren", isOn: $controller.aiEnhancementEnabled)
                        .help("Optionale Online-Nachbearbeitung des lokal erstellten Transkripts")
                        .accessibilityIdentifier("ai-enhancement-enabled")
                    Text("Optional mit OpenRouter. Die Transkription selbst bleibt lokal.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack {
                        SecureField("OpenRouter-API-Schlüssel", text: $apiKeyDraft)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(saveKey)
                            .onChange(of: apiKeyDraft) { _, value in if !value.isEmpty { keySaved = false } }
                            .accessibilityIdentifier("ai-api-key")
                        Button("Speichern", action: saveKey)
                            .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .help("API-Schlüssel im Schlüsselbund speichern")
                            .accessibilityIdentifier("save-ai-api-key")
                    }
                    if keySaved || controller.hasOpenRouterAPIKey {
                        Text("API-Schlüssel hinterlegt").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                Section("Berechtigungen") {
                    permissionRow("Mikrofon", granted: controller.microphoneGranted,
                                  identifier: "microphone-permission", action: controller.requestMicrophonePermission)
                    permissionRow("Mac-Audio", granted: controller.systemAudioGranted,
                                  identifier: "system-audio-permission", action: controller.requestSystemAudioPermission)
                    permissionRow("Automatisches Einfügen", granted: controller.accessibilityGranted,
                                  identifier: "accessibility-permission", action: controller.requestAccessibilityPermission)
                    Button("Berechtigungen aktualisieren") {
                        controller.refreshAccessibilityPermission()
                        controller.refreshRecordingPermissions()
                    }
                    .help("Aktuellen Freigabestatus in macOS prüfen")
                    .accessibilityIdentifier("refresh-permissions")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .font(.system(size: 13))
        .frame(width: 540, height: 640)
        .accessibilityIdentifier("recording-preferences")
        .onAppear {
            controller.refreshAccessibilityPermission()
            controller.refreshRecordingPermissions()
        }
    }

    private func permissionRow(_ title: String, granted: Bool, identifier: String,
                               action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if granted {
                Label("Erlaubt", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary).font(.system(size: 12))
            } else {
                Button("Erlauben", action: action)
                    .help("macOS-Freigabe für \(title) öffnen")
                    .accessibilityLabel("\(title) erlauben")
            }
        }
        .accessibilityIdentifier(identifier)
    }

    private func engineLabel(_ engine: TranscriptionEngine) -> String {
        switch engine {
        case .whisperCpp: return "Schnell"
        case .whisperKit: return "Integriert"
        case .qwen3ASR: return "Beste Qualität"
        }
    }

    private func saveKey() {
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        controller.saveOpenRouterAPIKey(key)
        apiKeyDraft = ""
        keySaved = controller.hasOpenRouterAPIKey
    }
}
