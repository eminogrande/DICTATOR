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
        // A new idle state clears any user dismissal so the next take shows the HUD again.
        if !controller.isRecording && !controller.isTranscribing {
            model.isHiddenByUser = false
        }
        let presentation = TranscriptionHUDPresentation.make(
            isVisible: controller.isTranscribing || controller.isRecording || controller.blockedHUDVisible,
            isRecording: controller.isRecording,
            title: controller.blockedHUDVisible ? controller.readinessStatus : controller.transcriptionHUDTitle,
            confirmed: controller.liveConfirmedText,
            provisional: controller.liveProvisionalText,
            audio: controller.liveAudioProgress
        )
        guard let presentation else { panel?.orderOut(nil); return }
        guard !model.isHiddenByUser else {
            panel?.orderOut(nil)
            return
        }

        let panel = panel ?? makePanel()
        self.panel = panel
        let latched = controller.isLatchedRecording
        let layout = desiredLayout(for: presentation, isRecording: controller.isRecording, isLatched: latched)
        model.height = layout.panelHeight
        model.textViewportHeight = layout.textViewportHeight
        model.shouldFollowBottom = layout.textOverflows
        model.showPhaseProgress = !controller.isRecording && !presentation.title.isEmpty
        model.isLatchedRecording = latched
        model.isRecording = controller.isRecording
        model.onStop = { [weak controller] in controller?.toggleRecording() }
        model.presentation = presentation
        panel.setContentSize(NSSize(width: 220, height: layout.panelHeight))
        // Clickable whenever a footer button exists (recording Stop or wait-phase Hide).
        panel.ignoresMouseEvents = !(latched || model.showPhaseProgress)
        position(panel)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 34),
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
            y: visibleFrame.maxY - panel.frame.height - 4
        ))
    }

    private func desiredLayout(for presentation: TranscriptionHUDPresentation, isRecording: Bool, isLatched: Bool) -> TranscriptionHUDLayoutResult {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        let measure: (String) -> CGFloat = { text in
            guard !text.isEmpty else { return 0 }
            return ceil((text as NSString).boundingRect(
                with: NSSize(width: 200, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font, .paragraphStyle: paragraph]
            ).height)
        }
        let confirmedHeight = measure(presentation.confirmed)
        let provisionalHeight = measure(presentation.provisional)
        let transcriptSpacing: CGFloat = confirmedHeight > 0 && provisionalHeight > 0 ? 6 : 0
        let textHeight = confirmedHeight + provisionalHeight + transcriptSpacing

        let hasHeader = presentation.audio.audioDuration > 0
        let hasFooter = isLatched || (!isRecording && !presentation.title.isEmpty) || (isRecording && !hasHeader)
        let screenHeight = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.height ?? 900
        return TranscriptionHUDLayout.make(
            textHeight: textHeight > 0 ? textHeight + 4 : 0,
            hasHeader: hasHeader,
            hasFooter: hasFooter,
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
    @Published var height: CGFloat = 56
    @Published var textViewportHeight: CGFloat = 0
    @Published var shouldFollowBottom = false
    @Published var showPhaseProgress = false
    @Published var isLatchedRecording = false
    @Published var isRecording = false
    @Published var isHiddenByUser = false
    var onStop: (() -> Void)?
}

private struct TranscriptionHUDView: View {
    @ObservedObject var model: TranscriptionHUDModel

    var body: some View {
        let hasWaveform = model.presentation.audio.audioDuration > 0
        VStack(alignment: .leading, spacing: TranscriptionHUDLayout.sectionSpacing) {
            if hasWaveform {
                LiveAudioWaveform(progress: model.presentation.audio, showRecordingDot: model.isRecording)
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

            if model.isLatchedRecording {
                HStack(spacing: 6) {
                    if !hasWaveform {
                        Circle().fill(Color.red).frame(width: 7, height: 7)
                    }
                    Text("Fn stops")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button {
                        model.isHiddenByUser = true
                    } label: {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Hide overlay — recording continues, stop via menu bar icon")
                    Button("Stop") {
                        model.onStop?()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .tint(.red)
                }
                .frame(height: TranscriptionHUDLayout.footerHeight, alignment: .leading)
            } else if model.isRecording && !hasWaveform {
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 7, height: 7)
                    Text(model.presentation.title)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .frame(height: TranscriptionHUDLayout.footerHeight, alignment: .leading)
            } else if model.showPhaseProgress {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                    Text(model.presentation.title)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Button {
                        model.isHiddenByUser = true
                    } label: {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Hide — transcription continues in the background; copy from the DICTATOR menu when done")
                }
                .frame(height: TranscriptionHUDLayout.footerHeight, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 220, height: model.height, alignment: .topLeading)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live transcript")
    }
}

private struct LiveAudioWaveform: View {
    let progress: LiveAudioProgress
    let showRecordingDot: Bool
    private let meterSlots = 24

    private var isLiveMeterOnly: Bool {
        progress.audioDuration > 0 && progress.transcribedPosition >= progress.audioDuration
    }

    private var timeLabel: String {
        if isLiveMeterOnly {
            let seconds = max(0, Int(progress.audioDuration.rounded(.down)))
            let hours = seconds / 3_600
            let minutes = (seconds % 3_600) / 60
            let remainder = seconds % 60
            return hours > 0
                ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
                : String(format: "%02d:%02d", minutes, remainder)
        }
        return progress.timecode
    }

    var body: some View {
        HStack(spacing: 6) {
            if showRecordingDot {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
            }

            Canvas { context, size in
                guard !progress.waveform.isEmpty else { return }
                let middle = size.height / 2
                if isLiveMeterOnly {
                    let count = meterSlots
                    let samples = progress.waveform.suffix(count)
                    let step = size.width / CGFloat(max(1, count))
                    let offset = count - samples.count
                    var quietPath = Path()
                    var activePath = Path()
                    for (i, sample) in samples.enumerated() {
                        let x = (CGFloat(offset + i) + 0.5) * step
                        if sample <= 0.01 {
                            quietPath.move(to: CGPoint(x: x, y: middle - 1))
                            quietPath.addLine(to: CGPoint(x: x, y: middle + 1))
                        } else {
                            let halfHeight = max(2.5, CGFloat(sample) * (middle - 1))
                            activePath.move(to: CGPoint(x: x, y: middle - halfHeight))
                            activePath.addLine(to: CGPoint(x: x, y: middle + halfHeight))
                        }
                    }
                    context.stroke(
                        quietPath,
                        with: .color(.white.opacity(0.22)),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    context.stroke(
                        activePath,
                        with: .color(.white),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                } else {
                    let spacing = progress.waveform.count > 1
                        ? size.width / CGFloat(progress.waveform.count - 1)
                        : 0
                    var waveform = Path()
                    for (index, sample) in progress.waveform.enumerated() {
                        let x = CGFloat(index) * spacing
                        let halfHeight = max(1.5, CGFloat(sample) * (middle - 1))
                        waveform.move(to: CGPoint(x: x, y: middle - halfHeight))
                        waveform.addLine(to: CGPoint(x: x, y: middle + halfHeight))
                    }
                    context.stroke(
                        waveform,
                        with: .color(.white.opacity(0.8)),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
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
            }

            Text(timeLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(timeLabel)
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
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .lineSpacing(2)
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
