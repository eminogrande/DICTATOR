import AppKit
import SwiftUI

@main
struct DictateMacApp: App {
    @StateObject private var controller = DictationController()

    var body: some Scene {
        MenuBarExtra {
            DictationMenu(controller: controller)
        } label: {
            Image(systemName: controller.isRecording ? "waveform.circle.fill" : "waveform.circle")
        }
        .menuBarExtraStyle(.window)
    }
}

private struct DictationMenu: View {
    @ObservedObject var controller: DictationController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if controller.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(controller.statusText)
                    .font(.headline)
            }

            Button(controller.recordButtonTitle) {
                controller.toggleRecording()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(!controller.canToggleRecording)

            Text("Hold Fn to record · release to paste")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !controller.latestTranscript.isEmpty {
                Divider()
                Text("Latest transcript")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(controller.latestTranscript)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 140)
            }

            Divider()

            Button("Open Archive") {
                controller.openArchive()
            }

            Button(controller.accessibilityButtonTitle) {
                controller.requestAccessibilityPermission()
            }
            .disabled(controller.accessibilityGranted)

            Button("Quit DictateMac") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear {
            controller.refreshAccessibilityPermission()
        }
    }
}
