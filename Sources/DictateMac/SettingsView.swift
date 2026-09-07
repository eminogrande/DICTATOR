import SwiftUI
import DictateMacCore
import UniformTypeIdentifiers

/// The recording library. Window sizing and presentation belong to AppDelegate.
struct SettingsView: View {
    @ObservedObject var controller: DictationController
    @State private var selectedID: String?
    @State private var search = ""
    @State private var filter: LibraryFilter = .all
    @State private var showFilePicker = false
    @State private var showPreferences = false
    @State private var showRename = false
    @State private var titleDraft = ""
    @State private var renameID: String?
    @State private var actionError: String?
    @State private var lastSelectedActiveID: String?

    private enum LibraryFilter: String, CaseIterable, Identifiable {
        case all = "Alle"
        case audio = "Nur Audio"
        case finished = "Fertig"
        var id: String { rawValue }
    }

    private var sortedSessions: [DictationSession] {
        controller.sessions.sorted { $0.metadata.startedAt > $1.metadata.startedAt }
    }

    private var visibleSessions: [DictationSession] {
        sortedSessions.filter { session in
            let info = controller.libraryDetails[session.metadata.sessionID]
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .audio:
                matchesFilter = info?.audioURL != nil && (info?.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            case .finished: matchesFilter = session.metadata.status == .completed
            }
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            let searchable = [info?.title ?? "", info?.transcript ?? "", info?.kind ?? "",
                              dateLabel(session), statusLabel(session.metadata.status)]
            return matchesFilter && (query.isEmpty || searchable.contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    private var selectedSession: DictationSession? {
        controller.sessions.first { $0.metadata.sessionID == selectedID }
    }

    var body: some View {
        VStack(spacing: 0) {
            workspaceToolbar
            Divider()
            if controller.hasActiveWork || controller.isMeetingStarting {
                activeBanner
                Divider()
            }
            HSplitView {
                libraryPane
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
                detailPane
                    .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .font(.system(size: 13))
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("recording-library-workspace")
        .onAppear {
            controller.refreshSessions()
            selectInitialSession()
            revealRequestedSession()
            selectActiveSessionIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DICTATORShowPreferences"))) { _ in showPreferences = true }
        .onChange(of: controller.selectedLibrarySessionID) { _, _ in revealRequestedSession() }
        .onChange(of: controller.sessions.map { $0.metadata.sessionID }) { _, _ in
            selectInitialSession()
            selectActiveSessionIfNeeded()
        }
        .onChange(of: controller.activeSessionID) { _, _ in selectActiveSessionIfNeeded() }
        .onChange(of: controller.isRecording) { _, _ in selectActiveSessionIfNeeded() }
        .sheet(isPresented: $showPreferences) {
            RecordingPreferencesView(controller: controller)
        }
        .alert("Aufnahme umbenennen", isPresented: $showRename) {
            TextField("Titel", text: $titleDraft)
                .accessibilityIdentifier("session-title-input")
            Button("Abbrechen", role: .cancel) { renameID = nil }
            Button("Speichern") { saveTitle() }
                .disabled(titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || controller.hasActiveWork)
        } message: {
            Text("Audio und Transkript bleiben unverändert.")
        }
        .alert("Aktion nicht möglich", isPresented: Binding(
            get: { actionError != nil }, set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.audio, .movie, .audiovisualContent],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { controller.transcribeAudioFile(url) }
            case .failure(let error): actionError = error.localizedDescription
            }
        }
    }

    private var workspaceToolbar: some View {
        HStack(spacing: 12) {
            Text("DICTATOR").font(.system(size: 13, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Divider().frame(height: 18)
            Button(action: controller.toggleRecording) {
                Label(controller.isRecording ? "Stopp" : controller.isMeetingStarting ? "Start abbrechen" : "Neue Aufnahme",
                      systemImage: controller.isRecording || controller.isMeetingStarting ? "stop.fill" : "mic.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(controller.isRecording || controller.isMeetingStarting ? .red : .accentColor)
            .disabled(!controller.canToggleRecording)
            .help(controller.isRecording ? "Aufnahme beenden und Audio sichern" : "Neue Aufnahme starten (Fn + R)")
            .accessibilityIdentifier("record-or-stop")
            Button { showFilePicker = true } label: {
                Label("Importieren", systemImage: "square.and.arrow.down")
            }
            .disabled(!controller.canTranscribeFile)
            .help("Audio- oder Videodatei importieren und transkribieren")
            .accessibilityIdentifier("import-recording")
            Spacer(minLength: 8)
            Button { showPreferences = true } label: {
                Label("Einstellungen", systemImage: "gearshape")
            }
            .help("Aufnahme, Transkription und Berechtigungen")
            .accessibilityIdentifier("open-recording-preferences")
        }
        .controlSize(.regular)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var activeBanner: some View {
        HStack(spacing: 0) {
            SessionActivityView(controller: controller)
            if let id = controller.activeSessionID {
                Button("Anzeigen") { selectedID = id; filter = .all; search = "" }
                    .buttonStyle(.borderless).padding(.trailing, 18)
                    .help("Zur aktiven Aufnahme wechseln")
                    .accessibilityIdentifier("show-active-session")
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityIdentifier("active-session-banner")
    }

    private var libraryPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Aufnahmen").fontWeight(.semibold).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("\(controller.sessions.count)").foregroundStyle(.secondary)
                }
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Aufnahmen durchsuchen", text: $search)
                        .textFieldStyle(.plain)
                        .accessibilityLabel("Aufnahmen durchsuchen")
                        .accessibilityIdentifier("library-search")
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Suche löschen")
                            .accessibilityLabel("Suche löschen")
                    }
                }
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                Picker("Aufnahmen filtern", selection: $filter) {
                    ForEach(LibraryFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Aufnahmen filtern")
                .accessibilityIdentifier("library-filter")
            }
            .padding(16)
            Divider()
            if visibleSessions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(controller.sessions.isEmpty ? "Noch keine Aufnahmen" : "Keine Treffer").fontWeight(.medium)
                    Text(controller.sessions.isEmpty ? "Starte eine Aufnahme oder importiere eine Datei." : "Ändere die Suche oder wähle „Alle“.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                Spacer()
            } else {
                List(selection: $selectedID) {
                    ForEach(visibleSessions, id: \.metadata.sessionID) { session in
                        sessionRow(session).tag(session.metadata.sessionID)
                    }
                }
                .listStyle(.sidebar)
                .accessibilityLabel("Aufnahmen")
                .accessibilityIdentifier("all-sessions")
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func sessionRow(_ session: DictationSession) -> some View {
        let info = controller.libraryDetails[session.metadata.sessionID]
        return VStack(alignment: .leading, spacing: 6) {
            Text(info?.title ?? "—")
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1).help(info?.title ?? "")
            Text(dateLabel(session)).font(.system(size: 12)).foregroundStyle(.secondary)
            HStack(spacing: 7) {
                Text(info?.durationLabel ?? "—")
                Text("·")
                Text(info.map { "\($0.wordCount) Wörter" } ?? "— Wörter")
                Spacer(minLength: 0)
                statusBadge(session.metadata.status)
            }
            .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("session-\(session.metadata.sessionID)")
    }

    @ViewBuilder private var detailPane: some View {
        if let session = selectedSession {
            sessionDetail(session)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.text").font(.system(size: 28)).foregroundStyle(.secondary)
                Text("Deine Aufnahmen. Dein Text.").font(.system(size: 18, weight: .medium))
                Text("Wähle links eine Aufnahme aus.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("library-empty-detail")
        }
    }

    private func sessionDetail(_ session: DictationSession) -> some View {
        let id = session.metadata.sessionID
        let info = controller.libraryDetails[id]
        let transcript = info?.transcript ?? ""
        let hasText = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Text(info?.title ?? "—")
                        .font(.system(size: 22, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("selected-session-title")
                    Spacer(minLength: 0)
                    Button {
                        renameID = id
                        titleDraft = info?.title ?? ""
                        showRename = true
                    } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless)
                    .disabled(controller.hasActiveWork || info == nil)
                    .help("Aufnahme umbenennen")
                    .accessibilityLabel("Aufnahme umbenennen")
                    .accessibilityIdentifier("rename-session")
                }
                Text("\(dateLabel(session)) · \(info?.kind ?? "—")")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack(spacing: 12) {
                    statusBadge(session.metadata.status)
                    Label(info?.durationLabel ?? "—", systemImage: "clock")
                    Text(info.map { "\($0.wordCount) Wörter" } ?? "— Wörter")
                    Text(info?.sizeLabel ?? "—")
                }
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .accessibilityIdentifier("selected-session-metadata")
                AudioPlaybackView(url: info?.audioURL,
                    disabled: controller.isRecording || controller.isMeetingStarting || ["starting", "saving"].contains(controller.activityPhase),
                    revision: "\(session.metadata.status.rawValue):\(info?.audioBytes ?? 0):\(info?.durationSeconds ?? 0)")
            }
            .padding(24)
            Divider()
            HStack(spacing: 12) {
                Text("Transkript").fontWeight(.semibold).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { controller.copySessionTranscript(id) } label: { Label("Kopieren", systemImage: "doc.on.doc") }
                    .disabled(!hasText)
                    .help("Gespeichertes Transkript kopieren")
                    .accessibilityIdentifier("copy-session-transcript")
                Button { controller.exportSessionTranscript(id) } label: { Label("Exportieren", systemImage: "square.and.arrow.up") }
                    .disabled(!hasText)
                    .help("Transkript als Textdatei speichern")
                    .accessibilityIdentifier("export-session-transcript")
                Menu {
                    Button("Audio im Finder zeigen") { controller.revealAudioInFolder(id) }
                        .disabled(info?.audioURL == nil)
                    Button("Transkript öffnen") { controller.openTranscript(id) }
                        .disabled(!hasText)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Weitere Aktionen")
                .accessibilityLabel("Weitere Aktionen für diese Aufnahme")
            }
            .controlSize(.small)
            .padding(.horizontal, 24).padding(.vertical, 12)
            Divider()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    if let warning = session.metadata.captureWarning, !warning.isEmpty {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange).textSelection(.enabled)
                    }
                    if let error = session.metadata.error, !error.isEmpty, !error.hasPrefix("Audio saved. Loading ") {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(info?.audioURL != nil ? "Audiodatei vorhanden. Der Text konnte nicht erstellt werden." : "Die Audiodatei wurde nicht gefunden.", systemImage: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                            DisclosureGroup("Fehlerdetails") {
                                Text(error).font(.system(size: 12)).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityIdentifier("session-error")
                    }
                    if hasText {
                        Text(transcript)
                            .font(.system(size: 15))
                            .lineSpacing(5)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("session-transcript")
                        if id == activeWorkingID {
                            transcriptPlaceholder(session)
                        }
                    } else {
                        transcriptPlaceholder(session)
                    }
                    if (session.metadata.status != .completed || !hasText) && session.metadata.sessionID != activeWorkingID {
                        Button(session.metadata.status == .saved ? "Transkript erstellen" : "Erneut versuchen") {
                            controller.retryTranscription(id)
                        }
                        .disabled(!controller.canRetryTranscription || info?.audioURL == nil)
                        .help("Gespeichertes Audio erneut transkribieren")
                        .accessibilityIdentifier("retry-session-transcription")
                        if !controller.canRetryTranscription && !controller.hasActiveWork {
                            Button("Transkription einrichten …") { showPreferences = true }
                                .buttonStyle(.link)
                                .help("Einstellungen für die lokale Transkription öffnen")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .accessibilityIdentifier("transcript-scroll-pane")
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var activeWorkingID: String? {
        controller.hasActiveWork ? controller.activeSessionID : nil
    }

    private func transcriptPlaceholder(_ session: DictationSession) -> some View {
        let isActive = session.metadata.sessionID == activeWorkingID
        let partial = isActive ? SessionActivityPresentation.partial(controller) : ""
        return VStack(alignment: .leading, spacing: 12) {
            Text(emptyTranscriptMessage(session.metadata.status, isActive: isActive))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("session-transcript-state")
            if !partial.isEmpty {
                Text("Live-Vorschau · noch nicht abgeschlossen").font(.system(size: 12)).foregroundStyle(.secondary)
                Text(partial).font(.system(size: 15)).lineSpacing(5).textSelection(.enabled)
                    .accessibilityIdentifier("session-live-text")
            }
        }
    }

    private func emptyTranscriptMessage(_ status: DictationStatus, isActive: Bool) -> String {
        if isActive && controller.isRecording { return "Aufnahme läuft. Das Transkript entsteht nach dem Stoppen." }
        if isActive { return "Das Transkript wird erstellt. Dein Audio bleibt erhalten." }
        switch status {
        case .completed: return "Für diese Aufnahme ist kein Transkript vorhanden."
        case .failed: return "Die Transkription wurde nicht abgeschlossen. Versuche es erneut."
        case .saved: return "Audio gespeichert. Du kannst jetzt ein Transkript erstellen."
        case .recording, .transcribing: return "Für diese Aufnahme liegt noch kein fertiges Transkript vor."
        }
    }

    private func statusBadge(_ status: DictationStatus) -> some View {
        let color: Color = status == .recording ? .red : status == .failed ? .orange : status == .completed ? .green : .secondary
        return Text(statusLabel(status))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.09), in: Capsule())
    }

    private func statusLabel(_ status: DictationStatus) -> String {
        switch status {
        case .recording: return "Aufnahme"
        case .saved: return "Audio gespeichert"
        case .transcribing: return "Wird transkribiert"
        case .completed: return "Fertig"
        case .failed: return "Nicht abgeschlossen"
        }
    }

    private func dateLabel(_ session: DictationSession) -> String {
        session.metadata.startedAt.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "de_DE")))
    }

    private func revealRequestedSession() {
        guard let id = controller.selectedLibrarySessionID,
              controller.sessions.contains(where: { $0.metadata.sessionID == id }) else { return }
        selectedID = id
        filter = .all
        search = ""
        controller.selectedLibrarySessionID = nil
    }

    private func selectInitialSession() {
        // Do not respond to metadata/timer refreshes by replacing a user's selection.
        if selectedID == nil { selectedID = sortedSessions.first?.metadata.sessionID }
    }

    private func selectActiveSessionIfNeeded() {
        guard controller.hasActiveWork || controller.isMeetingStarting,
              let id = controller.activeSessionID, id != lastSelectedActiveID,
              controller.sessions.contains(where: { $0.metadata.sessionID == id }) else { return }
        selectedID = id
        lastSelectedActiveID = id
        filter = .all
        search = ""
    }

    private func saveTitle() {
        guard let id = renameID, !controller.hasActiveWork else { return }
        do { try controller.renameSession(id, title: titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)) }
        catch { actionError = error.localizedDescription }
        renameID = nil
    }
}
