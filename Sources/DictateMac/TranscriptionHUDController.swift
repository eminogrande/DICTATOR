import AppKit
import Combine
import DictateMacCore
import SwiftUI

@MainActor
final class TranscriptionHUDController {
    private var panel: NSPanel?
    private let model = TranscriptionHUDModel()
    private var cancellable: AnyCancellable?

    init(controller: DictationController) {
        cancellable = controller.objectWillChange.sink { [weak self, weak controller] in
            DispatchQueue.main.async {
                guard let self, let controller else { return }
                self.update(from: controller)
            }
        }
        update(from: controller)
    }

    private func update(from controller: DictationController) {
        let presentation = TranscriptionHUDPresentation.make(
            isVisible: controller.isTranscribing,
            title: controller.transcriptionHUDTitle,
            confirmed: controller.liveConfirmedText,
            provisional: controller.liveProvisionalText,
            audio: controller.liveAudioProgress
        )
        guard let presentation else {
            panel?.orderOut(nil)
            return
        }

        let panel = panel ?? makePanel()
        self.panel = panel
        let layout = desiredLayout(for: presentation, isRecording: controller.isRecording)
        model.height = layout.panelHeight
        model.textViewportHeight = layout.textViewportHeight
        model.shouldFollowBottom = layout.textOverflows
        model.showPhaseProgress = !controller.isRecording && !presentation.title.isEmpty
        model.presentation = presentation
        panel.setContentSize(NSSize(width: 680, height: layout.panelHeight))
        position(panel)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 180),
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
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.maxY - panel.frame.height - 18
        ))
    }

    private func desiredLayout(for presentation: TranscriptionHUDPresentation, isRecording: Bool) -> TranscriptionHUDLayoutResult {
        let font = NSFont.systemFont(ofSize: 22)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        let measure: (String) -> CGFloat = { text in
            guard !text.isEmpty else { return 0 }
            return ceil((text as NSString).boundingRect(
                with: NSSize(width: 632, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font, .paragraphStyle: paragraph]
            ).height)
        }
        let confirmedHeight = measure(presentation.confirmed)
        let provisionalHeight = measure(presentation.provisional)
        let transcriptSpacing: CGFloat = confirmedHeight > 0 && provisionalHeight > 0 ? 8 : 0
        let textHeight = confirmedHeight + provisionalHeight + transcriptSpacing

        let screenHeight = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.height ?? 900
        return TranscriptionHUDLayout.make(
            textHeight: textHeight > 0 ? textHeight + 6 : 0,
            hasHeader: presentation.audio.audioDuration > 0,
            hasFooter: !isRecording && !presentation.title.isEmpty,
            screenHeight: screenHeight
        )
    }
}

@MainActor
private final class TranscriptionHUDModel: ObservableObject {
    @Published var presentation = TranscriptionHUDPresentation(
        title: "",
        confirmed: "",
        provisional: ""
    )
    @Published var height: CGFloat = 128
    @Published var textViewportHeight: CGFloat = 0
    @Published var shouldFollowBottom = false
    @Published var showPhaseProgress = false
}

private struct TranscriptionHUDView: View {
    @ObservedObject var model: TranscriptionHUDModel

    var body: some View {
        VStack(alignment: .leading, spacing: TranscriptionHUDLayout.sectionSpacing) {
            if model.presentation.audio.audioDuration > 0 {
                LiveAudioWaveform(progress: model.presentation.audio)
                .frame(height: TranscriptionHUDLayout.headerHeight)
            }

            if model.presentation.hasTranscript {
                LiveTranscriptContent(
                    confirmed: model.presentation.confirmed,
                    provisional: model.presentation.provisional,
                    shouldFollowBottom: model.shouldFollowBottom
                )
                .frame(height: model.textViewportHeight, alignment: .top)
                .clipped()
            }

            if model.showPhaseProgress {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    Text(model.presentation.title)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .frame(height: TranscriptionHUDLayout.footerHeight, alignment: .leading)
            }
        }
        .padding(24)
        .frame(width: 680, height: model.height, alignment: .topLeading)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live transcript")
    }
}

private struct LiveAudioWaveform: View {
    let progress: LiveAudioProgress

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Canvas { context, size in
                guard !progress.waveform.isEmpty else { return }
                let middle = size.height / 2
                let spacing = progress.waveform.count > 1
                    ? size.width / CGFloat(progress.waveform.count - 1)
                    : 0
                var waveform = Path()
                for (index, sample) in progress.waveform.enumerated() {
                    let x = CGFloat(index) * spacing
                    let halfHeight = max(1, CGFloat(sample) * (middle - 2))
                    waveform.move(to: CGPoint(x: x, y: middle - halfHeight))
                    waveform.addLine(to: CGPoint(x: x, y: middle + halfHeight))
                }
                context.stroke(
                    waveform,
                    with: .color(.white.opacity(0.72)),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round)
                )

                let markerX = size.width * progress.fractionTranscribed
                var marker = Path()
                marker.move(to: CGPoint(x: markerX, y: 0))
                marker.addLine(to: CGPoint(x: markerX, y: size.height))
                context.stroke(
                    marker,
                    with: .color(.white),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
            }

            Text(progress.timecode)
                .font(.system(size: 17, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(progress.timecode)
    }
}

private struct LiveTranscriptContent: View {
    let confirmed: String
    let provisional: String
    let shouldFollowBottom: Bool
    private let topID = "live-transcript-top"
    private let bottomID = "live-transcript-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id(topID)
                    if !confirmed.isEmpty {
                        Text(confirmed)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !provisional.isEmpty {
                        Text(provisional)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, confirmed.isEmpty ? 0 : 8)
                    }
                    Color.clear.frame(height: 0).id(bottomID)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 22, weight: .regular))
            .lineSpacing(5)
            .onAppear {
                proxy.scrollTo(
                    shouldFollowBottom ? bottomID : topID,
                    anchor: shouldFollowBottom ? .bottom : .top
                )
            }
            .onChange(of: confirmed + provisional) {
                proxy.scrollTo(
                    shouldFollowBottom ? bottomID : topID,
                    anchor: shouldFollowBottom ? .bottom : .top
                )
            }
            .onChange(of: shouldFollowBottom) {
                proxy.scrollTo(
                    shouldFollowBottom ? bottomID : topID,
                    anchor: shouldFollowBottom ? .bottom : .top
                )
            }
        }
    }
}
