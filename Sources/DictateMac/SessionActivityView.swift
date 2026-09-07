import AppKit
import Combine
import SwiftUI

@MainActor
enum SessionActivityPresentation {
    static func duration(_ interval: TimeInterval) -> String { SessionLibraryInfo.durationLabel(interval) }

    static func title(_ controller: DictationController, now: Date) -> String {
        let elapsed = controller.activityStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        switch controller.activityPhase {
        case "starting": return "STARTET"
        case "recording": return "REC \(duration(max(controller.recordingElapsed, elapsed)))"
        case "saving": return "SICHERN \(duration(elapsed))"
        case "transcribing": return "TXT \(duration(elapsed))"
        case "completed": return "FERTIG"
        case "failed": return "PRÜFEN"
        case "saved": return "GESPEICHERT"
        default: return "DICTATOR"
        }
    }

    static func color(_ phase: String) -> NSColor {
        switch phase {
        case "recording", "starting", "failed": return .systemRed
        case "transcribing", "saving", "saved": return .systemOrange
        case "completed": return .systemGreen
        default: return .labelColor
        }
    }

    static func status(_ raw: String) -> String {
        switch raw {
        case "recording": return "Aufnahme läuft"
        case "transcribing": return "Text wird erstellt"
        case "completed": return "Fertig"
        case "failed": return "Fehlgeschlagen"
        case "saved": return "Audio gespeichert"
        default: return raw.capitalized
        }
    }

    static func detail(_ controller: DictationController) -> String {
        switch controller.activityPhase {
        case "starting": return "Mikrofon wird vorbereitet."
        case "recording":
            let kind = controller.activeSessionID.flatMap { controller.libraryDetails[$0]?.kind }
            return kind == "Diktat" ? "Sprechen. Fn loslassen, um den Text zu übernehmen." : "Audio wird gesichert. Text folgt nach dem Stoppen."
        case "saving": return "Audio wird gesichert."
        case "transcribing": return "Text wird lokal erstellt. Du kannst andere Aufnahmen öffnen."
        case "completed": return "Transkript gespeichert."
        case "saved": return "Audio gesichert. Text kann später erstellt werden."
        case "failed": return "Aufnahme öffnen und den nächsten Schritt prüfen."
        default: return "Bereit für eine neue Aufnahme."
        }
    }

    static func partial(_ controller: DictationController) -> String {
        if controller.isRecording {
            return [controller.liveConfirmedText, controller.liveProvisionalText].filter { !$0.isEmpty }.joined(separator: " ")
        }
        return controller.filePartialText
    }

    static func level(_ value: Float) -> Double { value.isFinite ? min(1, max(0, Double(value))) : 0 }

    static func sourceStatus(_ status: String) -> String {
        switch status {
        case "Receiving audio": return "Signal da"
        case "No audio yet": return "Noch kein Signal"
        case "Quiet": return "Leise"
        case "Not recording": return "Inaktiv"
        case "Off", "Not requested": return "Aus"
        case "Starting…": return "Startet"
        default: return status
        }
    }
}

/// Small persistent activity strip; actual text lives in the reading pane, not duplicated here.
struct SessionActivityView: View {
    @ObservedObject var controller: DictationController
    @State private var now = Date()
    private let clock = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Label(SessionActivityPresentation.title(controller, now: now), systemImage: controller.isRecording ? "record.circle" : "waveform")
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Color(nsColor: SessionActivityPresentation.color(controller.activityPhase)))
                    .accessibilityIdentifier("session-activity-status")
                Text(SessionActivityPresentation.detail(controller))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("session-activity-detail")
            }
            Spacer(minLength: 0)
            if controller.isRecording {
                meter("Mikrofon", status: controller.microphoneStatus, value: controller.microphoneLevel)
                meter("Mac-Audio", status: controller.systemAudioStatus, value: controller.systemAudioLevel)
            } else if controller.activityPhase == "transcribing" || controller.activityPhase == "saving" {
                ProgressView().controlSize(.small)
            }
            if controller.canCancelTranscription {
                Button("Anhalten") { controller.cancelFileTranscription() }
                    .help("Die Audioaufnahme bleibt gespeichert.")
                    .accessibilityIdentifier("cancel-transcription")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .onReceive(clock) { now = $0 }
    }

    private func meter(_ name: String, status: String, value: Float) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            ProgressView(value: SessionActivityPresentation.level(value))
                .progressViewStyle(.linear).tint(.red)
                .accessibilityLabel("\(name): \(SessionActivityPresentation.sourceStatus(status))")
            Text(SessionActivityPresentation.sourceStatus(status)).font(.system(size: 11))
                .lineLimit(1).help(status)
        }
        .frame(width: 96)
    }
}
