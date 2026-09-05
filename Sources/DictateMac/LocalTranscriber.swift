import AVFoundation
import DictateMacCore
import Foundation
import WhisperKit

@MainActor
final class LocalTranscriber {
    private var whisperKit: WhisperKit?
    private var streamTranscriber: AudioStreamTranscriber?
    private var streamTask: Task<Void, Never>?
    private var streamError: Error?

    func loadModel() async throws {
        guard whisperKit == nil else { return }

        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let modelDirectory = applicationSupport
            .appendingPathComponent("DictateMac", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(
            at: modelDirectory,
            withIntermediateDirectories: true
        )

        let folder = modelDirectory.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3_turbo")
        guard FileManager.default.fileExists(atPath: folder.path) else {
            throw EngineValidationError("Built-in model is not installed. Choose Fast or install the local model.")
        }
        let config = WhisperKitConfig(
            model: "large-v3_turbo",
            downloadBase: modelDirectory,
            modelFolder: folder.path,
            verbose: false,
            prewarm: false,
            load: true,
            download: false,
            useBackgroundDownloadSession: false
        )
        // CoreML file loading/compilation must not occupy the main actor.
        whisperKit = try await Task.detached(priority: .utility) { try await WhisperKit(config) }.value
    }

    func startStreaming(
        onUpdate: @escaping @MainActor @Sendable (LiveTranscriptSnapshot) -> Void,
        onAudioUpdate: @escaping @MainActor @Sendable (LiveAudioProgress) -> Void
    ) async throws {
        guard let whisperKit else { throw TranscriptionError.modelNotLoaded }
        guard let tokenizer = whisperKit.tokenizer else { throw TranscriptionError.tokenizerUnavailable }
        guard streamTranscriber == nil else { return }

        streamError = nil
        let options = decodingOptions()
        let stream = AudioStreamTranscriber(
            audioEncoder: whisperKit.audioEncoder,
            featureExtractor: whisperKit.featureExtractor,
            segmentSeeker: whisperKit.segmentSeeker,
            textDecoder: whisperKit.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: whisperKit.audioProcessor,
            decodingOptions: options,
            requiredSegmentsForConfirmation: 2,
            useVAD: true
        ) { oldState, newState in
            let oldDecodedPosition = max(
                oldState.lastConfirmedSegmentEndSeconds,
                oldState.unconfirmedSegments.last?.end ?? 0
            )
            let newDecodedPosition = max(
                newState.lastConfirmedSegmentEndSeconds,
                newState.unconfirmedSegments.last?.end ?? 0
            )
            if oldState.bufferEnergy != newState.bufferEnergy
                || oldDecodedPosition != newDecodedPosition {
                let progress = LiveAudioProgress(
                    waveform: WaveformEnvelope.downsample(newState.bufferEnergy),
                    audioDuration: Double(newState.bufferEnergy.count) * 0.1,
                    transcribedPosition: Double(newDecodedPosition)
                )
                Task { @MainActor in onAudioUpdate(progress) }
            }

            guard oldState.currentText != newState.currentText
                    || oldState.unconfirmedSegments != newState.unconfirmedSegments
                    || oldState.confirmedSegments != newState.confirmedSegments else { return }
            let snapshot = LiveTranscriptText.make(
                confirmedSegments: newState.confirmedSegments.map(\.text),
                unconfirmedSegments: newState.unconfirmedSegments.map(\.text),
                currentText: newState.currentText
            )
            Task { @MainActor in onUpdate(snapshot) }
        }
        streamTranscriber = stream
        streamTask = Task { [weak self] in
            do {
                try await stream.startStreamTranscription()
            } catch {
                self?.streamError = error
            }
        }

        try await Task.sleep(nanoseconds: 180_000_000)
        if let streamError {
            await stream.stopStreamTranscription()
            clearStream()
            throw streamError
        }
    }

    func stopStreamingAndSave(
        to audioURL: URL,
        systemAudio: CapturedSystemAudio? = nil
    ) async throws -> [Float] {
        guard let whisperKit, let streamTranscriber else {
            throw TranscriptionError.streamNotRunning
        }
        await streamTranscriber.stopStreamTranscription()
        await streamTask?.value
        defer { clearStream() }
        // A preview decoder failure must not discard microphone samples; the
        // selected validated engine still gets the saved audio for its final pass.
        let microphone = Array(whisperKit.audioProcessor.audioSamples)
        guard !microphone.isEmpty else { throw TranscriptionError.emptyAudio }
        let samples = AudioSampleMixer.mix(
            microphone: microphone,
            system: systemAudio?.samples ?? [],
            systemOffset: systemAudio?.offsetSamples ?? 0
        )
        try Self.writeWAV(samples, to: audioURL)
        return microphone
    }

    func transcribe(wavURL: URL) async throws -> String {
        let samples = try await Task.detached(priority: .utility) {
            try AudioProcessor.loadAudioAsFloatArray(fromPath: wavURL.path)
        }.value
        return try await transcribe(samples: samples)
    }

    func transcribe(samples: [Float]) async throws -> String {
        guard let whisperKit else { throw TranscriptionError.modelNotLoaded }
        let detection = try await whisperKit.detectLangauge(audioArray: samples)
        let language = SpokenLanguage.locked(detected: detection.language, probabilities: detection.langProbs)
        let results = try await whisperKit.transcribe(
            audioArray: samples,
            decodeOptions: decodingOptions(language: language)
        )
        return results.map(\.text).joined(separator: " ")
    }

    private func decodingOptions(language: String? = nil) -> DecodingOptions {
        DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true
        )
    }

    private func clearStream() {
        streamTask?.cancel()
        streamTask = nil
        streamTranscriber = nil
        streamError = nil
    }

    private static func writeWAV(_ samples: [Float], to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Double(WhisperKit.sampleRate),
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        ), let channel = buffer.floatChannelData?.pointee else {
            throw TranscriptionError.couldNotWriteAudio
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        channel.update(from: samples, count: samples.count)
        try file.write(from: buffer)
    }
}

private enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case tokenizerUnavailable
    case streamNotRunning
    case emptyAudio
    case couldNotWriteAudio

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: "The WhisperKit model is not loaded."
        case .tokenizerUnavailable: "The WhisperKit tokenizer is unavailable."
        case .streamNotRunning: "Live transcription is not running."
        case .emptyAudio: "The recording contains no audio samples."
        case .couldNotWriteAudio: "The recording could not be written to WAV."
        }
    }
}
