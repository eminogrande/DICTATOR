import AVFoundation
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
        let text = String(decoding: stdout, as: UTF8.self)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !text.isEmpty else { throw WhisperCppError.noOutput }
        return Result(text: text, model: "whisper.cpp large-v3-turbo")
    }
}

/// Long-running whisper.cpp transcription with live progress + cancellation.
final class WhisperCppFileTask: @unchecked Sendable {
    struct Snapshot: Sendable {
        let fraction: Double      // 0...1
        let text: String          // full transcript so far
    }

    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let duration: Double
    private let lock = NSLock()
    private var lines: [String] = []
    private var cancelled = false

    init(wavURL: URL) throws {
        let file = try AVAudioFile(forReading: wavURL)
        duration = Double(file.length) / file.fileFormat.sampleRate
        process.executableURL = TranscriptionEngine.wcppURL
        process.arguments = [
            "-m", TranscriptionEngine.wcppModelURL.path,
            "-f", wavURL.path,
            "-l", "auto",
            "-t", "8", "-p", "4", "-fa",
        ]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        process.terminate()
    }

    private var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }; return cancelled
    }

    /// Runs whisper.cpp, emitting progress snapshots as segment lines stream in.
    /// Returns the joined transcript, or throws on error/cancellation.
    func run(onSnapshot: @escaping @Sendable (Snapshot) -> Void) async throws -> String {
        // Drain stderr so the process never blocks on a full pipe.
        let stderrDrain = Task.detached(priority: .utility) {
            _ = self.stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }
        try process.run()

        var text = ""
        for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
            guard !isCancelled else {
                process.terminate()
                throw WhisperCppError.cancelled
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("[") else { continue }
            // "[00:00:01.980 --> 00:00:03.140]   text"
            guard let close = trimmed.firstIndex(of: "]") else { continue }
            let tsRange = trimmed.index(after: trimmed.startIndex)..<close
            let ts = String(trimmed[tsRange])
            let parts = ts.components(separatedBy: "-->")
            let segmentText: String
            if let bodyStart = trimmed.index(close, offsetBy: 1, limitedBy: trimmed.endIndex) {
                segmentText = String(trimmed[bodyStart...]).trimmingCharacters(in: .whitespaces)
            } else {
                segmentText = ""
            }
            if parts.count == 2, let end = Self.timestamp(parts[1]) {
                let fraction = duration > 0 ? min(1.0, end / duration) : 0
                lock.lock()
                if !segmentText.isEmpty { lines.append(segmentText) }
                text = lines.joined(separator: " ")
                lock.unlock()
                onSnapshot(Snapshot(fraction: fraction, text: text))
            } else if !segmentText.isEmpty {
                lock.lock(); lines.append(segmentText); text = lines.joined(separator: " "); lock.unlock()
                onSnapshot(Snapshot(fraction: 0, text: text))
            }
        }

        process.waitUntilExit()
        _ = await stderrDrain.value
        if isCancelled {
            throw WhisperCppError.cancelled
        }
        guard process.terminationStatus == 0 else {
            throw WhisperCppError.processFailed(exit: process.terminationStatus)
        }
        lock.lock(); let final = lines.joined(separator: " "); lock.unlock()
        guard !final.isEmpty else { throw WhisperCppError.noOutput }
        return final
    }

    private static func timestamp(_ raw: String) -> Double? {
        let clean = raw.trimmingCharacters(in: .whitespaces)
        let comps = clean.split(separator: ":").map(String.init)
        guard comps.count >= 2 else { return nil }
        if comps.count == 3, let h = Double(comps[0]), let m = Double(comps[1]), let s = Double(comps[2]) {
            return h * 3600 + m * 60 + s
        }
        if comps.count == 2, let m = Double(comps[0]), let s = Double(comps[1]) {
            return m * 60 + s
        }
        return nil
    }
}

private enum WhisperCppError: LocalizedError {
    case processFailed(exit: Int32)
    case noOutput
    case cancelled

    var errorDescription: String? {
        switch self {
        case .processFailed(let exit): "whisper.cpp exited with code \(exit)."
        case .noOutput: "whisper.cpp produced no transcript."
        case .cancelled: "Transcription cancelled."
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
