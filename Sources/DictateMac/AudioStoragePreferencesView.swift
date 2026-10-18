import SwiftUI
import DictateMacCore

/// Reusable confirmed cleanup, without touching failed or active recordings.
struct AudioStoragePreferencesView: View {
    @ObservedObject var controller: DictationController
    var offerAutomatically = false
    @AppStorage("transcribedAudioCleanupOfferedV1") private var offered = false
    @State private var summary: AudioCleanupSummary?
    @State private var showConfirmation = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !offerAutomatically {
                Text("Gespeicherte Aufnahmen: AAC/M4A, Ziel 128 kbit/s. Nach erfolgreicher Transkription wird das Audio automatisch gelöscht. Der Text bleibt erhalten.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Button("Bereits transkribiertes Audio löschen …") { prepare() }
                    .disabled(controller.hasActiveWork || controller.isMeetingStarting)
                    .accessibilityIdentifier("cleanup-transcribed-audio")
            }
            if let message {
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("audio-cleanup-result")
            }
        }
        .onAppear { offerIfNeeded() }
        .onChange(of: controller.hasActiveWork) { _, _ in offerIfNeeded() }
        .onChange(of: controller.isMeetingStarting) { _, _ in offerIfNeeded() }
        .alert("Transkribiertes Audio löschen?", isPresented: $showConfirmation) {
            Button("Behalten", role: .cancel) { summary = nil }
            Button("Audio löschen", role: .destructive) { clean() }
                .disabled(controller.hasActiveWork || controller.isMeetingStarting)
        } message: {
            if let summary {
                Text("\(summary.fileCount) Audiodateien aus \(summary.sessionCount) fertigen Aufnahmen (\(ByteCountFormatter.string(fromByteCount: summary.bytes, countStyle: .file))). Transkripte bleiben erhalten. Nicht transkribierte und fehlgeschlagene Aufnahmen werden nicht gelöscht.")
            }
        }
    }

    private func offerIfNeeded() {
        guard offerAutomatically, !offered, !controller.hasActiveWork, !controller.isMeetingStarting else { return }
        do {
            let candidate = try controller.completedAudioCleanupSummary()
            offered = true
            if candidate.fileCount > 0 {
                summary = candidate
                showConfirmation = true
            }
        } catch {
            // A failed scan is not consent. The repeatable settings action shows errors.
        }
    }

    private func prepare() {
        do {
            let candidate = try controller.completedAudioCleanupSummary()
            if candidate.fileCount == 0 {
                message = "Kein löschbares Audio vorhanden. Alle Transkripte bleiben erhalten."
            } else {
                summary = candidate
                showConfirmation = true
                message = nil
            }
        } catch { message = error.localizedDescription }
    }

    private func clean() {
        do {
            let current = try controller.completedAudioCleanupSummary()
            guard current == summary else {
                summary = current
                showConfirmation = current.fileCount > 0
                message = "Die Auswahl hat sich geändert. Bitte erneut bestätigen."
                return
            }
            let result = try controller.deleteCompletedAudio()
            message = "\(result.fileCount) Audiodateien gelöscht, \(ByteCountFormatter.string(fromByteCount: result.bytes, countStyle: .file)) freigegeben. Transkripte unverändert."
        } catch { message = "Audio konnte nicht vollständig gelöscht werden: " + error.localizedDescription }
        summary = nil
    }
}
