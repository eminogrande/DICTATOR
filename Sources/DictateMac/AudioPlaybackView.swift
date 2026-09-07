import AVFAudio
import Combine
import SwiftUI

/// Small read-only player for saved audio. Capture owners must set `disabled`
/// before starting recording; toggling it off never resumes playback.
@MainActor
struct AudioPlaybackView: View {
    let url: URL?
    let disabled: Bool
    var revision: String = ""
    @StateObject private var model = AudioPlaybackModel()

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.togglePlayback()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(disabled || !model.canPlay)
            .accessibilityLabel(model.isPlaying ? "Wiedergabe pausieren" : "Audio abspielen")
            .accessibilityIdentifier("audioPlayback.playPause")
            .help(model.isPlaying ? "Wiedergabe pausieren" : "Audio abspielen")

            VStack(alignment: .leading, spacing: 2) {
                Slider(value: Binding(
                    get: { model.elapsed },
                    set: { value in
                        model.seek(to: value)
                    }
                ), in: 0...max(model.duration, 0.001))
                .disabled(disabled || !model.canPlay)
                .accessibilityLabel("Wiedergabeposition")
                .accessibilityValue("\(AudioPlaybackModel.timeLabel(model.elapsed)) von \(AudioPlaybackModel.timeLabel(model.duration))")
                .accessibilityIdentifier("audioPlayback.seek")

                Text(disabled ? "Während der Aufnahme gesperrt" : model.statusText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(disabled ? "Während der Aufnahme gesperrt" : model.statusText)
                    .accessibilityIdentifier("audioPlayback.status")
            }

            Text("\(AudioPlaybackModel.timeLabel(model.elapsed)) / \(AudioPlaybackModel.timeLabel(model.duration))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
                .accessibilityLabel("Abgelaufen \(AudioPlaybackModel.timeLabel(model.elapsed)), Gesamtdauer \(AudioPlaybackModel.timeLabel(model.duration))")
                .accessibilityIdentifier("audioPlayback.time")
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("audioPlayback")
        .onAppear {
            model.setDisabled(disabled)
            model.load(disabled ? nil : url)
        }
        .onChange(of: url) { _, newURL in
            model.setDisabled(disabled)
            model.load(disabled ? nil : newURL)
        }
        .onChange(of: revision) { _, _ in
            if !disabled { model.load(url) }
        }
        .onChange(of: disabled) { _, newValue in
            model.setDisabled(newValue)
            model.load(newValue ? nil : url)
        }
        .onDisappear { model.stop() }
    }
}

/// Injectable only to test transport decisions without activating audio output.
protocol AudioPlaybackControlling: AnyObject {
    var duration: TimeInterval { get }
    var currentTime: TimeInterval { get set }
    var isPlaying: Bool { get }
    var delegate: (any AVAudioPlayerDelegate)? { get set }
    func prepareToPlay() -> Bool
    func play() -> Bool
    func pause()
    func stop()
}

extension AVAudioPlayer: AudioPlaybackControlling {}

@MainActor
final class AudioPlaybackModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isDisabled = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoaded = false

    private var player: (any AudioPlaybackControlling)?
    private var progressTimer: AnyCancellable?
    private var captureObserver: NSObjectProtocol?
    private var captureFinishedObserver: NSObjectProtocol?
    private let makePlayer: (URL) throws -> any AudioPlaybackControlling

    init(makePlayer: @escaping (URL) throws -> any AudioPlaybackControlling = {
        try AVAudioPlayer(contentsOf: $0)
    }) {
        self.makePlayer = makePlayer
        super.init()
        // The capture owner posts synchronously on MainActor before opening any
        // input. No Task or receive(on:) hop: sound is stopped before post returns.
        captureObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("DICTATORCaptureWillStart"), object: nil, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.setDisabled(true) }
        }
        captureFinishedObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("DICTATORCaptureStartupDidFinish"), object: nil, queue: nil
        ) { [weak self] notification in
            let isRecording = notification.object as? Bool ?? true
            MainActor.assumeIsolated { self?.setDisabled(isRecording) }
        }
    }

    deinit {
        if let captureObserver { NotificationCenter.default.removeObserver(captureObserver) }
        if let captureFinishedObserver { NotificationCenter.default.removeObserver(captureFinishedObserver) }
        progressTimer?.cancel()
        player?.stop()
    }

    var canPlay: Bool { isLoaded && !isDisabled && errorMessage == nil }
    var statusText: String {
        if isDisabled { return "Während der Aufnahme gesperrt" }
        if let errorMessage { return errorMessage }
        if !isLoaded { return "Keine Audiodatei verfügbar" }
        return isPlaying ? "Wiedergabe läuft" : "Bereit zur Wiedergabe"
    }

    func load(_ url: URL?) {
        stop()
        player?.delegate = nil
        player = nil
        isLoaded = false
        duration = 0
        errorMessage = nil
        guard let url else { return }
        guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path) else {
            errorMessage = "Audiodatei nicht verfügbar"
            return
        }
        do {
            let candidate = try makePlayer(url)
            guard candidate.duration.isFinite, candidate.duration > 0,
                  candidate.prepareToPlay() else {
                candidate.stop()
                errorMessage = "Audiodatei kann nicht wiedergegeben werden"
                return
            }
            candidate.delegate = self
            candidate.currentTime = 0
            player = candidate
            duration = candidate.duration
            isLoaded = true
        } catch {
            // Decoder errors can contain huge internal diagnostics and file paths.
            errorMessage = "Audiodatei kann nicht gelesen werden"
        }
    }

    func setDisabled(_ disabled: Bool) {
        isDisabled = disabled
        if disabled { stop() }
    }

    func togglePlayback() {
        guard canPlay, let player else { return }
        if isPlaying {
            player.pause()
            elapsed = min(max(player.currentTime, 0), duration)
            isPlaying = false
            cancelTimer()
        } else {
            if elapsed >= duration { seek(to: 0) }
            guard player.play() else {
                stop()
                errorMessage = "Wiedergabe konnte nicht gestartet werden"
                return
            }
            isPlaying = true
            // Combine owns the timer; its callback owns neither model nor player.
            progressTimer = Timer.publish(every: 0.1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.updateProgress() }
        }
    }

    func seek(to time: TimeInterval) {
        guard canPlay, time.isFinite, let player else { return }
        let target = min(max(time, 0), duration)
        player.currentTime = target
        elapsed = target
    }

    func stop() {
        cancelTimer()
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
        elapsed = 0
    }

    private func cancelTimer() {
        progressTimer?.cancel()
        progressTimer = nil
    }

    private func updateProgress() {
        guard !isDisabled, let player else { stop(); return }
        if !player.isPlaying {
            playbackFinished(successfully: true)
        } else {
            elapsed = min(max(player.currentTime, 0), duration)
        }
    }

    /// Shared completion path, internal for silent transport tests.
    func playbackFinished(successfully: Bool) {
        stop()
        if !successfully { errorMessage = "Wiedergabe wurde unterbrochen" }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.player,
                  ObjectIdentifier(current) == identity else { return }
            self.playbackFinished(successfully: flag)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.player,
                  ObjectIdentifier(current) == identity else { return }
            self.playbackFinished(successfully: false)
        }
    }

    static func timeLabel(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        // Avoid trapping on extreme metadata while supporting long recordings.
        let total = Int(min(seconds, 359_999))
        if total >= 3_600 {
            return String(format: "%d:%02d:%02d", total / 3_600, (total / 60) % 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
