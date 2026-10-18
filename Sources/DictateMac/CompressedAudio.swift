import AVFoundation
import DictateMacCore
import Foundation

/// Native AAC M4A compression for finalized audio using afconvert.
/// Preserves crash-safe PCM during recording; compresses finalized audio before saved/deferred transcribe.
/// Subprocess output is spooled to private files (SubprocessCapture), never undrained Pipes.
public enum CompressedAudio {
    public static let targetBitrate = 128_000
    public static let sampleRate = 44_100

    public struct Result: Sendable {
        public let url: URL
        public let duration: TimeInterval
        public let fileSize: Int64
    }

    public enum CompressionError: LocalizedError {
        case invalidSource(String)
        case encodingFailed(String)
        case invalidOutput(String)
        case tempFileError(String)

        public var errorDescription: String? {
            switch self {
            case .invalidSource(let msg): "Invalid source audio: \(msg)"
            case .encodingFailed(let msg): "AAC encoding failed: \(msg)"
            case .invalidOutput(let msg): "Encoded output validation failed: \(msg)"
            case .tempFileError(let msg): "Temporary file error: \(msg)"
            }
        }
    }

    /// Check if source is a valid readable audio file with nonzero duration
    public static func validateSource(_ url: URL) throws -> TimeInterval {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CompressionError.invalidSource("File not found")
        }
        guard let file = try? AVAudioFile(forReading: url) else {
            throw CompressionError.invalidSource("Cannot decode audio")
        }
        let duration = Double(file.length) / file.fileFormat.sampleRate
        guard duration > 0 else {
            throw CompressionError.invalidSource("Zero duration")
        }
        return duration
    }

    /// Convert WAV to AAC M4A using native afconvert.
    /// Uses bounded disk I/O - no full-buffer loading.
    /// Validates decoded output duration matches source duration.
    /// The destination is replaced only by a fully validated new output, so a
    /// previously interrupted run cannot block retries with a stale partial file.
    public static func compress(
        source: URL,
        destination: URL,
        bitrate: Int = targetBitrate
    ) async throws -> Result {
        let sourceDuration = try validateSource(source)
        guard bitrate > 0 else {
            throw CompressionError.invalidSource("Bitrate must be positive")
        }

        // Private temp location with UUID to avoid collisions. The defer removes the
        // directory on every exit path — error, cancellation, and after the move out.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictator-compress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tempM4A = tempDir.appendingPathComponent("audio.m4a")

        try await runAfconvertToM4A(
            source: source,
            destination: tempM4A,
            bitrate: bitrate,
            sampleRate: sampleRate
        )
        // A cancelled caller must not publish output; the defer cleans the temp dir.
        try Task.checkCancellation()

        // Validate encoded output
        guard FileManager.default.fileExists(atPath: tempM4A.path) else {
            throw CompressionError.encodingFailed("No output produced")
        }

        let outputDuration: TimeInterval
        do {
            outputDuration = try validateSource(tempM4A)
        } catch {
            throw CompressionError.invalidOutput("Cannot decode encoded M4A: \(error.localizedDescription)")
        }

        // Duration must match source within tolerance (AAC padding allowed)
        let durationDelta = abs(outputDuration - sourceDuration)
        guard durationDelta < 0.5 else {
            throw CompressionError.invalidOutput(
                "Duration mismatch: source \(sourceDuration)s, output \(outputDuration)s"
            )
        }

        // Move validated temp file to destination, replacing an unreferenced
        // leftover from an interrupted earlier attempt.
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempM4A.path)[.size] as? Int64) ?? 0
        if FileManager.default.fileExists(atPath: destination.path),
           destination.standardizedFileURL != source.standardizedFileURL {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempM4A, to: destination)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        try handle.synchronize()

        return Result(url: destination, duration: outputDuration, fileSize: fileSize)
    }

    /// Decode M4A/AAC to temporary 16kHz mono WAV for transcription engines.
    /// Caller must defer cleanup. Returns temporary URL - original untouched.
    /// On ANY failure or cancellation the private decode directory is removed here.
    public static func temporaryWAV16kMono(from source: URL) async throws -> URL {
        _ = try validateSource(source)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictator-decode-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        let tempWAV = tempDir.appendingPathComponent("audio.wav")

        do {
            try await runAfconvertToWAV(source: source, destination: tempWAV)
            try Task.checkCancellation()

            guard FileManager.default.fileExists(atPath: tempWAV.path) else {
                throw CompressionError.invalidOutput("WAV decode produced no output")
            }

            // Validate decoded WAV is readable
            guard let file = try? AVAudioFile(forReading: tempWAV), file.length > 0 else {
                throw CompressionError.invalidOutput("Decoded WAV is invalid or empty")
            }

            return tempWAV
        } catch {
            // Errors and cooperative cancellation must never leak the decode dir.
            try? FileManager.default.removeItem(at: tempDir)
            throw error
        }
    }

    /// Clean up temporary WAV and its parent directory
    public static func cleanupTemporaryWAV(_ url: URL) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: dir)
    }

    /// Check if URL points to a compressed audio format we can decode
    public static func isCompressedFormat(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["m4a", "aac", "mp4", "caf"].contains(ext)
    }

    // MARK: - Private

    /// afconvert invocations share SubprocessCapture: stdout/stderr are spooled to
    /// private files and read after exit, so a verbose encoder can never deadlock
    /// on an undrained pipe.
    private static func runAfconvertToM4A(
        source: URL,
        destination: URL,
        bitrate: Int,
        sampleRate: Int
    ) async throws {
        let result = try await SubprocessCapture.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/afconvert"),
            arguments: [
                "-f", "m4af",
                "-d", "aac@\(sampleRate)",
                "-b", String(bitrate),
                "-s", "0",  // CBR strategy 0 - verified 127896bit/s on 3s tone
                source.path,
                destination.path,
            ]
        )
        guard result.terminationStatus == 0 else {
            let message = String(decoding: result.stderr, as: UTF8.self)
            throw CompressionError.encodingFailed("afconvert exit \(result.terminationStatus): \(message)")
        }
    }

    private static func runAfconvertToWAV(source: URL, destination: URL) async throws {
        let result = try await SubprocessCapture.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/afconvert"),
            arguments: [
                "-f", "WAVE",
                "-d", "LEI16@16000",
                "-c", "1",
                source.path,
                destination.path,
            ]
        )
        guard result.terminationStatus == 0 else {
            let message = String(decoding: result.stderr, as: UTF8.self)
            throw CompressionError.encodingFailed("afconvert WAV decode exit \(result.terminationStatus): \(message)")
        }
    }
}
