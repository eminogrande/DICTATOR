import AppKit
import Combine
import DictateMacCore
import SwiftUI

@MainActor
final class TranscriptionHUDController {
    private let panel: NSPanel
    private let model = TranscriptionHUDModel()
    private var cancellable: AnyCancellable?

    init(controller: DictationController) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 116),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: TranscriptionHUDView(model: model))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false

        cancellable = controller.$isTranscribing
            .combineLatest(controller.$transcriptionPreview)
            .map(TranscriptionHUDPresentation.make)
            .removeDuplicates()
            .sink { [weak self] presentation in
                self?.update(presentation)
            }
    }

    private func update(_ presentation: TranscriptionHUDPresentation?) {
        guard let presentation else {
            panel.orderOut(nil)
            return
        }
        model.presentation = presentation
        positionPanel()
        panel.orderFrontRegardless()
    }

    private func positionPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.maxY - panel.frame.height - 18
        ))
    }
}

@MainActor
private final class TranscriptionHUDModel: ObservableObject {
    @Published var presentation = TranscriptionHUDPresentation(
        title: "Transcribing locally",
        detail: "..."
    )
}

private struct TranscriptionHUDView: View {
    @ObservedObject var model: TranscriptionHUDModel

    var body: some View {
        HStack(spacing: 14) {
            ProgressView()
                .controlSize(.small)
                .tint(.purple)

            VStack(alignment: .leading, spacing: 5) {
                Text(model.presentation.title)
                    .font(.headline)
                Text(model.presentation.detail)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .contentTransition(.numericText())
                Text("Activity preview — final transcript follows")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 440, height: 116)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Transcribing locally")
    }
}
