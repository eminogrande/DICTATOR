import DictateMacCore
import Foundation

/// Full-file transcription engines the user can pick in Settings.
enum TranscriptionEngine: String, CaseIterable, Identifiable {
    /// whisper.cpp large-v3-turbo sidecar — fastest, Metal, exact language detect.
    case whisperCpp
    /// WhisperKit large-v3_turbo — in-process fallback, also powers live preview.
    case whisperKit
    /// mlx-qwen3-asr sidecar — best German accuracy, runs via a bundled Python venv.
    case qwen3ASR

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisperCpp: "whisper.cpp (fastest)"
        case .whisperKit: "WhisperKit (built-in)"
        case .qwen3ASR: "Qwen3-ASR (best German)"
        }
    }

    /// The whisper.cpp sidecar installed under Application Support.
    static var wcppURL: URL {
        Self.toolsURL.appendingPathComponent("wcpp/bin/whisper-cli", isDirectory: false)
    }

    static var wcppModelURL: URL {
        Self.toolsURL.appendingPathComponent("wcpp/models/ggml-large-v3-turbo-q5_0.bin", isDirectory: false)
    }

    /// The mlx-qwen3-asr venv under Application Support.
    static var qwenURL: URL {
        Self.toolsURL.appendingPathComponent("asr/bin/mlx-qwen3-asr", isDirectory: false)
    }

    static var toolsURL: URL {
        (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ))?
            .appendingPathComponent("DictateMac/Tools", isDirectory: true)
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/DictateMac/Tools", isDirectory: true)
    }

    var isAvailable: Bool {
        switch self {
        case .whisperKit: true
        case .whisperCpp:
            FileManager.default.isExecutableFile(atPath: Self.wcppURL.path)
                && FileManager.default.isReadableFile(atPath: Self.wcppModelURL.path)
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

/// Transcribes a finished WAV via the whisper.cpp sidecar (Metal, language auto-detect).
enum WhisperCppService {
    struct Result: Sendable {
        let text: String
        let model: String
    }

    static func transcribe(wavURL: URL) async throws -> Result {
        let process = Process()
        process.executableURL = TranscriptionEngine.wcppURL
        process.arguments = [
            "-m", TranscriptionEngine.wcppModelURL.path,
            "-f", wavURL.path,
            "-l", "auto",
            "-t", "8", "-p", "4", "-fa",
            "-np", "-nt",
            "-otxt", "-of", wavURL.deletingPathExtension().path,
        ]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()

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

        guard exitCode == 0 else {
            throw WhisperCppError.processFailed(exit: exitCode)
        }
        // -np -nt: stdout is the plain transcript, one line per segment.
        let text = String(decoding: stdout, as: UTF8.self)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !text.isEmpty else { throw WhisperCppError.noOutput }
        return Result(text: text, model: "whisper.cpp large-v3-turbo")
    }
}

private enum WhisperCppError: LocalizedError {
    case processFailed(exit: Int32)
    case noOutput

    var errorDescription: String? {
        switch self {
        case .processFailed(let exit): "whisper.cpp exited with code \(exit)."
        case .noOutput: "whisper.cpp produced no transcript."
        }
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
