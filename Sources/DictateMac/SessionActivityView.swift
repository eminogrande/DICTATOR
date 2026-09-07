import AppKit
import Combine
import SwiftUI

/// One vocabulary and clock for the menu bar, open menu, and main window.
@MainActor
enum SessionActivityPresentation {
    static func duration(_ interval: TimeInterval) -> String {
        let seconds = Int(max(0, interval.isFinite ? interval : 0))
        if seconds >= 3_600 {
            return String(format: "%d:%02d:%02d", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    static func title(_ controller: DictationController, now: Date) -> String {
        let elapsed = controller.activityStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        switch controller.activityPhase {
        case "starting": return "STARTING"
        case "recording": return "REC \(duration(max(controller.recordingElapsed, elapsed)))"
        case "saving": return "SAVING \(duration(elapsed))"
        case "transcribing": return "TXT \(duration(elapsed))"
        case "completed": return "DONE"
        case "failed": return "FAILED"
        case "saved": return "SAVED"
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
        case "recording": return "Recording"
        case "transcribing": return "Transcribing"
        case "completed": return "Done"
        case "failed": return "Failed"
        case "saved": return "Saved · ready to transcribe"
        default: return raw.capitalized
        }
    }

    static func detail(_ controller: DictationController) -> String {
        controller.activityPhase == "idle" ? "Ready to record · transcription optional" : controller.statusText
    }

    static func partial(_ controller: DictationController) -> String {
        if controller.isRecording {
            return [controller.liveConfirmedText, controller.liveProvisionalText]
                .filter { !$0.isEmpty }.joined(separator: " ")
        }
        return controller.filePartialText
    }

    static func level(_ value: Float) -> Double {
        value.isFinite ? min(1, max(0, Double(value))) : 0
    }
}

struct SessionActivityView: View {
    @ObservedObject var controller: DictationController
    @State private var now = Date()
    private let clock = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(SessionActivityPresentation.title(controller, now: now))
                    .foregroundStyle(Color(nsColor: SessionActivityPresentation.color(controller.activityPhase)))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .accessibilityIdentifier("session-activity-status")
                Spacer(minLength: 8)
                if controller.canCancelTranscription {
                    Button("Cancel", role: .destructive) { controller.cancelFileTranscription() }
                }
            }
            if controller.isRecording {
                meter("Mic", status: controller.microphoneStatus, value: controller.microphoneLevel)
                meter("Mac", status: controller.systemAudioStatus, value: controller.systemAudioLevel)
            }
            Text(SessionActivityPresentation.detail(controller))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityIdentifier("session-activity-detail")
            if controller.activityPhase == "transcribing" {
                if controller.fileProgress > 0 {
                    ProgressView(value: min(1, controller.fileProgress)).progressViewStyle(.linear)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            let partial = SessionActivityPresentation.partial(controller)
            if !partial.isEmpty {
                ScrollView(.vertical) {
                    Text(partial)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 140)
                .accessibilityIdentifier("session-live-text")
            }
        }
        .font(.system(size: 17, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(clock) { now = $0 }
    }

    private func meter(_ name: String, status: String, value: Float) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(name) · \(status)")
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: SessionActivityPresentation.level(value))
                .progressViewStyle(.linear)
                .tint(.red)
                .accessibilityLabel("\(name) input level")
        }
    }
}
