import DictateMacCore
import Foundation

/// Full-file transcription engines the user can pick in Settings.
enum TranscriptionEngine: String, CaseIterable, Identifiable {
    /// WhisperKit large-v3_turbo — fast, in-process, default.
    case whisperKit
    /// mlx-qwen3-asr sidecar — best German accuracy, runs via a bundled Python venv.
    case qwen3ASR

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisperKit: "WhisperKit (fast)"
        case .qwen3ASR: "Qwen3-ASR (best German)"
        }
    }

    /// The Python venv installed under Application Support (not bundled in the app).
    static var qwenURL: URL {
        (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ))?
            .appendingPathComponent("DictateMac/Tools/asr/bin/mlx-qwen3-asr", isDirectory: false)
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/DictateMac/Tools/asr/bin/mlx-qwen3-asr")
    }

    var isAvailable: Bool {
        switch self {
        case .whisperKit: true
        case .qwen3ASR: FileManager.default.isExecutableFile(atPath: Self.qwenURL.path)
        }
    }
}

/// Transcribes a finished WAV via the mlx-qwen3-asr CLI sidecar.
enum QwenASRService {
    struct Result: Sendable {
        let text: String
        let model: String
    }

    /// Transcribe `wavURL`; language is auto-detected by the model (no forced translation).
    static func transcribe(wavURL: URL) async throws -> Result {
        let process = Process()
        process.executableURL = TranscriptionEngine.qwenURL
        process.arguments = [
            wavURL.path,
            "--output-format", "txt",
            "--output-dir", NSTemporaryDirectory(),
            "--no-progress",
        ]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()

        // Drain both pipes on background threads while the process runs.
        let drain: (Pipe) -> Data = { pipe in
            pipe.fileHandleForReading.readDataToEndOfFile()
        }
        async let stdoutData = Task.detached(priority: .utility) { drain(out) }.value
        async let stderrData = Task.detached(priority: .utility) { drain(err) }.value

        let exitCode = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
            process.terminationHandler = { proc in continuation.resume(returning: proc.terminationStatus) }
        }
        let stdout = try await stdoutData
        _ = try await stderrData
        _ = stdout

        guard exitCode == 0 else {
            throw QwenASRError.processFailed(exit: exitCode)
        }
        // mlx-qwen3-asr writes <stem>.txt into --output-dir; stdout carries only chatter.
        let expected = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(wavURL.deletingPathExtension().lastPathComponent + ".txt")
        guard let fromFile = try? String(contentsOf: expected, encoding: .utf8) else {
            throw QwenASRError.noOutput
        }
        let text = fromFile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw QwenASRError.noOutput }
        return Result(text: text, model: "qwen3-asr-0.6b")
    }
}

private enum QwenASRError: LocalizedError {
    case processFailed(exit: Int32)
    case noOutput

    var errorDescription: String? {
        switch self {
        case .processFailed(let exit): "Qwen3-ASR exited with code \(exit)."
        case .noOutput: "Qwen3-ASR produced no transcript."
        }
    }
}
