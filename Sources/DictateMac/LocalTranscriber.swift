import Foundation
import WhisperKit

@MainActor
final class LocalTranscriber {
    private var whisperKit: WhisperKit?

    func loadModel() async throws {
        guard whisperKit == nil else {
            return
        }

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

        let config = WhisperKitConfig(
            model: "large-v3_turbo",
            downloadBase: modelDirectory,
            verbose: false,
            prewarm: false,
            load: true,
            useBackgroundDownloadSession: false
        )
        whisperKit = try await WhisperKit(config)
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: nil,
            usePrefillPrompt: false,
            skipSpecialTokens: true
        )
        let results = try await whisperKit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        )
        return results.map(\.text).joined(separator: " ")
    }
}

private enum TranscriptionError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        "The WhisperKit model is not loaded."
    }
}
