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
        case .whisperCpp: "Fast"
        case .whisperKit: "Built-in"
        case .qwen3ASR: "Best quality"
        }
    }

    /// The whisper.cpp sidecar installed under Application Support.
    static var wcppURL: URL {
        Self.toolsURL.appendingPathComponent("wcpp/bin/whisper-cli", isDirectory: false)
    }

    static var wcppModelURL: URL {
        Self.toolsURL.appendingPathComponent("wcpp/models/ggml-large-v3-turbo-q5_0.bin", isDirectory: false)
    }

    static var wcppVADModelURL: URL {
        Self.toolsURL.appendingPathComponent("wcpp/models/ggml-silero-v6.2.0.bin", isDirectory: false)
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

    /// Presence is only a cheap invalidation check, NEVER a readiness proof.
    func checkInstallation(toolsURL: URL = Self.toolsURL) throws {
        let executable: URL
        let models: [URL]
        switch self {
        case .whisperKit: return // A validated in-memory model needs no sidecar.
        case .whisperCpp:
            executable = toolsURL.appendingPathComponent("wcpp/bin/whisper-cli")
            models = ["ggml-large-v3-turbo-q5_0.bin", "ggml-silero-v6.2.0.bin"].map {
                toolsURL.appendingPathComponent("wcpp/models/" + $0)
            }
        case .qwen3ASR:
            executable = toolsURL.appendingPathComponent("asr/bin/mlx-qwen3-asr")
            models = [] // Offline inference validates the actual cached weights/tokenizer.
        }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw EngineValidationError("Local engine is missing: \(executable.path)")
        }
        for model in models where !FileManager.default.isReadableFile(atPath: model.path) {
            throw EngineValidationError("Model is missing: \(model.path)")
        }
    }

    static var localEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Installed dylibs sit beside whisper-cli; some builds retain /tmp rpaths.
        env["DYLD_LIBRARY_PATH"] = wcppURL.deletingLastPathComponent().path
        env["HF_HUB_OFFLINE"] = "1"
        env["TRANSFORMERS_OFFLINE"] = "1"
        return env
    }
}

struct EngineValidationError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum EngineValidation {
    static var fixtureURL: URL {
        // SwiftPM's generated accessor searches the executable bundle root, not
        // Contents/Resources in a packaged .app. Never depend on a developer's .build.
        if let resources = Bundle.main.resourceURL,
           let bundled = Bundle(url: resources.appendingPathComponent("DictateMac_DictateMac.bundle")),
           let fixture = bundled.url(forResource: "readiness", withExtension: "wav") {
            return fixture
        }
        return Bundle.module.url(forResource: "readiness", withExtension: "wav")!
    }

    /// Real speech exercises decoder inference AND Silero VAD (silence may skip
    /// decoding entirely). No user audio, archive writes or network downloads.
    static func validateSidecar(_ engine: TranscriptionEngine) async throws {
        try engine.checkInstallation()
        switch engine {
        case .whisperCpp: _ = try await WhisperCppService.transcribe(wavURL: fixtureURL, timeout: 120)
        case .qwen3ASR: _ = try await QwenASRService.transcribe(wavURL: fixtureURL, timeout: 180)
        case .whisperKit: throw EngineValidationError("Built-in must validate its loaded model.")
        }
    }

    static func checkedText(_ result: CapturedSubprocessResult, output: URL) throws -> String {
        guard result.terminationStatus == 0 else {
            throw EngineValidationError("Local engine exited with code \(result.terminationStatus).\n" + String(decoding: result.stderr, as: UTF8.self))
        }
        let text = TranscriptCleaner.clean(try String(contentsOf: output, encoding: .utf8))
        guard !text.isEmpty else { throw EngineValidationError("Local engine produced no transcript.") }
        return text
    }

    static func temporaryOutputDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dictator-asr-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        return directory
    }
}

/// Transcribes a finished WAV via the same offline pipeline used for readiness.
enum QwenASRService {
    struct Result: Sendable {
        let text: String
        let model: String
    }

    static func transcribe(wavURL: URL, timeout: TimeInterval? = nil) async throws -> Result {
        let directory = try EngineValidation.temporaryOutputDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try await SubprocessCapture.run(
            executableURL: TranscriptionEngine.qwenURL,
            arguments: [wavURL.path, "--model", "Qwen/Qwen3-ASR-0.6B",
                        "--output-format", "txt", "--output-dir", directory.path, "--no-progress"],
            environment: TranscriptionEngine.localEnvironment, timeout: timeout)
        let output = directory.appendingPathComponent(wavURL.deletingPathExtension().lastPathComponent + ".txt")
        return Result(text: try EngineValidation.checkedText(result, output: output), model: "qwen3-asr-0.6b")
    }
}

/// Transcribes a finished WAV via whisper.cpp, including required Silero VAD.
enum WhisperCppService {
    struct Result: Sendable {
        let text: String
        let model: String
    }

    static func arguments(wavURL: URL) -> [String] {
        ["-m", TranscriptionEngine.wcppModelURL.path, "-f", wavURL.path,
         "-l", "auto", "-t", "8", "-p", "4", "-fa",
         "-vm", TranscriptionEngine.wcppVADModelURL.path, "--vad"]
    }

    static func transcribe(wavURL: URL, timeout: TimeInterval? = nil) async throws -> Result {
        let directory = try EngineValidation.temporaryOutputDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("transcript")
        let result = try await SubprocessCapture.run(
            executableURL: TranscriptionEngine.wcppURL,
            arguments: arguments(wavURL: wavURL) + ["-np", "-nt", "-otxt", "-of", output.path],
            environment: TranscriptionEngine.localEnvironment, timeout: timeout)
        return Result(text: try EngineValidation.checkedText(result, output: output.appendingPathExtension("txt")),
                      model: "whisper.cpp large-v3-turbo")
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
        process.arguments = WhisperCppService.arguments(wavURL: wavURL)
        process.environment = TranscriptionEngine.localEnvironment
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
