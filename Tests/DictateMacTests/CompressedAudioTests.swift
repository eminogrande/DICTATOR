import AVFoundation
import XCTest
@testable import DictateMac

/// Native codec regression tests using real afconvert.
/// Tests synthetic valid WAV roundtrip, duration validation, bitrate targeting,
/// failure preservation, cancellation, and temp cleanup.
final class CompressedAudioTests: XCTestCase {

    private var scratchDir: URL!

    override func setUp() async throws {
        // App-appropriate native temp path — the shipped product and its tests must
        // never depend on a developer-machine directory.
        scratchDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictator-audio-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: scratchDir)
    }

    // MARK: - Helpers

    private func makeSyntheticWAV(duration: TimeInterval = 3.0, frequency: Float = 440.0) throws -> URL {
        let url = scratchDir.appendingPathComponent("test-\(UUID().uuidString).wav")
        let sampleRate: Double = 44100
        let frameCount = AVAudioFrameCount(duration * sampleRate)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw NSError(domain: "Test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Format creation failed"])
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "Test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Buffer creation failed"])
        }
        buffer.frameLength = frameCount

        // Generate sine wave
        guard let channelData = buffer.floatChannelData?[0] else {
            throw NSError(domain: "Test", code: -1, userInfo: [NSLocalizedDescriptionKey: "No channel data"])
        }
        for frame in 0..<Int(frameCount) {
            let time = Float(frame) / Float(sampleRate)
            channelData[frame] = sin(2.0 * .pi * frequency * time) * 0.5
        }

        try file.write(from: buffer)
        return url
    }

    private func audioDuration(_ url: URL) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.fileFormat.sampleRate
    }

    /// Private codec temp directories matching our prefixes left in the native temp dir.
    private func leftoverCodecTempDirs() -> [URL] {
        let temp = FileManager.default.temporaryDirectory
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: temp, includingPropertiesForKeys: nil)) ?? []
        return entries.filter {
            $0.lastPathComponent.hasPrefix("dictator-compress-")
                || $0.lastPathComponent.hasPrefix("dictator-decode-")
        }
    }

    // MARK: - Tests

    func testValidWAVRoundtripPreservesDuration() async throws {
        let source = try makeSyntheticWAV(duration: 3.0)
        let sourceDuration = try audioDuration(source)
        let destination = scratchDir.appendingPathComponent("compressed.m4a")

        let result = try await CompressedAudio.compress(source: source, destination: destination)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(result.duration, sourceDuration, accuracy: 0.1, "Duration must be preserved")
        XCTAssertGreaterThan(result.fileSize, 0)

        // Verify output is readable
        let outputDuration = try audioDuration(destination)
        XCTAssertEqual(outputDuration, sourceDuration, accuracy: 0.5)
    }

    func testBitrateTargeting() async throws {
        let source = try makeSyntheticWAV(duration: 2.0)
        let destination = scratchDir.appendingPathComponent("bitrate-test.m4a")

        // Use default 128k target
        let result = try await CompressedAudio.compress(source: source, destination: destination)

        // Rough size check: 128kbps ≈ 16KB/s, 2s ≈ 32KB minimum
        // With AAC overhead we expect reasonable compression
        XCTAssertGreaterThan(result.fileSize, 20_000, "128kbit AAC should be >20KB for 2s")
        XCTAssertLessThan(result.fileSize, 500_000, "Should be much smaller than WAV")
    }

    func testFailedEncodingPreservesOriginal() async throws {
        // Create invalid source (not a valid WAV)
        let invalidSource = scratchDir.appendingPathComponent("invalid.wav")
        try "not audio data".write(to: invalidSource, atomically: true, encoding: .utf8)

        let destination = scratchDir.appendingPathComponent("should-not-exist.m4a")

        do {
            _ = try await CompressedAudio.compress(source: invalidSource, destination: destination)
            XCTFail("Should have thrown for invalid source")
        } catch {
            // Expected: encoding failed
            XCTAssertTrue(error is CompressedAudio.CompressionError)
        }

        // Original must be preserved
        XCTAssertTrue(FileManager.default.fileExists(atPath: invalidSource.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(leftoverCodecTempDirs().isEmpty, "Failed compression must clean its temp dir")
    }

    func testCancelledCompressionPublishesNothingAndCleansUp() async throws {
        let source = try makeSyntheticWAV(duration: 2.0)
        let destination = scratchDir.appendingPathComponent("cancelled.m4a")

        // Cancel before the work starts: the cooperative check after the encode must
        // throw before the validated output is moved to the destination.
        let task = Task { try await CompressedAudio.compress(source: source, destination: destination) }
        task.cancel()
        let result = await task.result
        XCTAssertThrowsError(try result.get()) { error in
            XCTAssertTrue(error is CancellationError, "Expected CancellationError, got \(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(leftoverCodecTempDirs().isEmpty, "Cancelled compression must clean its temp dir")
    }

    func testRepeatedCompressionReplacesInterruptedDestination() async throws {
        let source = try makeSyntheticWAV(duration: 1.0)
        let destination = scratchDir.appendingPathComponent("retry.m4a")
        // Simulate an unreferenced leftover from an interrupted earlier attempt.
        try "partial".write(to: destination, atomically: true, encoding: .utf8)

        let result = try await CompressedAudio.compress(source: source, destination: destination)
        XCTAssertGreaterThan(result.fileSize, 1_000)
        XCTAssertEqual(try audioDuration(destination), 1.0, accuracy: 0.5)
    }

    func testTempWAVCleanupOnAllPaths() async throws {
        let source = try makeSyntheticWAV(duration: 1.0)
        let compressed = scratchDir.appendingPathComponent("temp-test.m4a")
        _ = try await CompressedAudio.compress(source: source, destination: compressed)

        // Decode to temp WAV
        let tempWAV = try await CompressedAudio.temporaryWAV16kMono(from: compressed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempWAV.path))

        // Verify it's 16k mono
        let file = try AVAudioFile(forReading: tempWAV)
        XCTAssertEqual(file.fileFormat.sampleRate, 16000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)

        // Cleanup
        CompressedAudio.cleanupTemporaryWAV(tempWAV)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempWAV.path))
        XCTAssertTrue(leftoverCodecTempDirs().isEmpty)
    }

    func testCancelledDecodeCleansTemporaryDirectory() async throws {
        let source = try makeSyntheticWAV(duration: 1.0)
        let compressed = scratchDir.appendingPathComponent("decode-cancel.m4a")
        _ = try await CompressedAudio.compress(source: source, destination: compressed)

        let task = Task { try await CompressedAudio.temporaryWAV16kMono(from: compressed) }
        task.cancel()
        let result = await task.result
        XCTAssertThrowsError(try result.get()) { error in
            XCTAssertTrue(error is CancellationError, "Expected CancellationError, got \(error)")
        }
        XCTAssertTrue(leftoverCodecTempDirs().isEmpty, "Cancelled decode must remove its temp dir")
    }

    func testFailedDecodeLeavesNoTemporaryDirectory() async throws {
        // Undecodable source fails validation before any temp dir exists.
        let invalid = scratchDir.appendingPathComponent("broken.m4a")
        try "not audio data".write(to: invalid, atomically: true, encoding: .utf8)
        await XCTAssertAsyncThrowsError(try await CompressedAudio.temporaryWAV16kMono(from: invalid))
        XCTAssertTrue(leftoverCodecTempDirs().isEmpty)
        // Source is only read, never modified or deleted.
        XCTAssertTrue(FileManager.default.fileExists(atPath: invalid.path))
    }

    func testValidateSourceRejectsEmptyFile() throws {
        let empty = scratchDir.appendingPathComponent("empty.wav")
        FileManager.default.createFile(atPath: empty.path, contents: Data())

        XCTAssertThrowsError(try CompressedAudio.validateSource(empty)) { error in
            guard case CompressedAudio.CompressionError.invalidSource = error else {
                XCTFail("Expected invalidSource, got \(error)")
                return
            }
        }
    }

    func testValidateSourceRejectsMissingFile() throws {
        let missing = scratchDir.appendingPathComponent("missing.wav")
        XCTAssertThrowsError(try CompressedAudio.validateSource(missing))
    }

    func testValidateSourceRejectsNonPositiveBitrate() async throws {
        let source = try makeSyntheticWAV(duration: 1.0)
        let destination = scratchDir.appendingPathComponent("bad-bitrate.m4a")
        await XCTAssertAsyncThrowsError(
            try await CompressedAudio.compress(source: source, destination: destination, bitrate: 0)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testIsCompressedFormatDetection() {
        XCTAssertTrue(CompressedAudio.isCompressedFormat(URL(fileURLWithPath: "/test.m4a")))
        XCTAssertTrue(CompressedAudio.isCompressedFormat(URL(fileURLWithPath: "/test.aac")))
        XCTAssertTrue(CompressedAudio.isCompressedFormat(URL(fileURLWithPath: "/test.mp4")))
        XCTAssertFalse(CompressedAudio.isCompressedFormat(URL(fileURLWithPath: "/test.wav")))
        XCTAssertFalse(CompressedAudio.isCompressedFormat(URL(fileURLWithPath: "/test.mp3")))
    }
}

/// Small async assert helper so throwing async calls read like XCTest assertions.
private func XCTAssertAsyncThrowsError<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
        // Expected
    }
}
