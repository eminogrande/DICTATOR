import AppKit
import SwiftUI

@main
struct DictateMacApp: App {
    @StateObject private var controller = DictationController()
    @StateObject private var brainController = BrainController()

    var body: some Scene {
        MenuBarExtra {
            DictationMenu(controller: controller)
        } label: {
            Image(nsImage: DictatorAssets.menuIcon)
        }
        .menuBarExtraStyle(.window)

        Window("DICTATOR Brain", id: "brain") {
            BrainView(controller: brainController)
        }
        .defaultSize(width: 980, height: 680)
    }
}

private enum DictatorAssets {
    static let menuIcon: NSImage = {
        let fallback = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "DICTATOR")!
        guard let url = Bundle.main.url(forResource: "DICTATOR-menu@2x", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return fallback
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()
}

private struct DictationMenu: View {
    @ObservedObject var controller: DictationController
    @Environment(\.openWindow) private var openWindow

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

            if !controller.transcriptionPreview.isEmpty {
                Text(controller.transcriptionPreview)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .contentTransition(.numericText())
            }

            Button(controller.recordButtonTitle) {
                controller.toggleRecording()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(!controller.canToggleRecording)

            Toggle("Auto-Paste", isOn: $controller.autoPasteEnabled)
                .toggleStyle(.switch)

            Text(controller.autoPasteEnabled
                 ? "Fn release: copy + paste at cursor"
                 : "Fn release: copy to clipboard only")
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

            Button("Open Brain…") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "brain")
            }

            Button("Open Archive") {
                controller.openArchive()
            }

            Button(controller.accessibilityButtonTitle) {
                controller.requestAccessibilityPermission()
            }
            .disabled(controller.accessibilityGranted)

            Button("Quit DICTATOR") {
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
