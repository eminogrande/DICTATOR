import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

struct CapturedSystemAudio: Sendable {
    let samples: [Float]
    let offsetSamples: Int
}

final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    static var isAuthorized: Bool { CGPreflightScreenCaptureAccess() }
    @discardableResult static func requestPermission() -> Bool {
        isAuthorized || CGRequestScreenCaptureAccess()
    }

    private let sampleRate = 16_000.0
    private let captureQueue = DispatchQueue(label: "de.emin.DictateMac.system-audio")
    // Everything below is confined to captureQueue, including reader access.
    private var samples: [Float] = [] // Fn compatibility ONLY; never used for file capture.
    private var writer: MeetingPCMWriter?
    private var stream: SCStream?
    private var generation: UUID?
    private var accepting = false
    private var firstPTS: Double?
    private var firstSampleDate: Date?
    private var clockDate = Date()
    private var clockPTS = 0.0
    private var writtenFrames: Int64 = 0
    private var measuredLevel: Float = 0
    private var lastAudioUptime = 0.0
    private var received = false
    private var errorMessage: String?
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    var level: Float {
        captureQueue.sync {
            ProcessInfo.processInfo.systemUptime - lastAudioUptime < 0.5 ? measuredLevel : 0
        }
    }
    var hasReceivedAudio: Bool { captureQueue.sync { received } }
    var captureError: String? { captureQueue.sync { errorMessage } }
    var firstSampleAt: Date? { captureQueue.sync { firstSampleDate } }

    func firstAudioOffset(relativeTo microphoneStartedAt: Date) -> TimeInterval {
        offset(relativeTo: microphoneStartedAt)
    }

    /// First actual audio PTS relative to the microphone start (not startCapture completion).
    /// Pass this to MeetingAudioFile.mix after stopToFile(). Silence gaps inside the
    /// system file are already aligned to the first PTS and must not be added twice.
    func offset(relativeTo microphoneStartedAt: Date) -> TimeInterval {
        captureQueue.sync { firstSampleDate?.timeIntervalSince(microphoneStartedAt) ?? 0 }
    }

    func start(at url: URL? = nil) async throws {
        let token = UUID()
        try captureQueue.sync {
            guard generation == nil else { throw SystemAudioCaptureError.alreadyRunning }
            // Open before requesting ScreenCaptureKit; the file survives all failures.
            writer = try url.map { try MeetingPCMWriter(url: $0) }
            samples = []
            generation = token
            accepting = false
            firstPTS = nil
            firstSampleDate = nil
            writtenFrames = 0
            received = false
            measuredLevel = 0
            errorMessage = nil
            converter = nil
            clockDate = Date()
            clockPTS = CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()))
        }
        do {
            let content = try await bounded(seconds: 5) {
                try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            }
            guard let display = content.displays.first else { throw SystemAudioCaptureError.noDisplay }
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = Int(sampleRate)
            configuration.channelCount = 1
            configuration.width = 2
            configuration.height = 2
            configuration.showsCursor = false
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: captureQueue)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
            let active = captureQueue.sync { () -> Bool in
                guard generation == token else { return false }
                self.stream = stream
                accepting = true
                return true
            }
            guard active else { throw CancellationError() }
            try await bounded(seconds: 5) { [self] in
                try await stream.startCapture()
                // A timed-out start can still complete. Stop that orphan instead of
                // letting a late completion reactivate a stopped or newer recording.
                if !captureQueue.sync(execute: { generation == token }) {
                    try? await stream.stopCapture()
                }
            }
        } catch {
            let failedStream = captureQueue.sync { () -> SCStream? in
                guard generation == token else { return nil }
                errorMessage = error.localizedDescription
                accepting = false
                generation = nil
                let old = stream
                stream = nil
                do { try writer?.close() } catch { errorMessage = error.localizedDescription }
                writer = nil
                return old
            }
            if let failedStream { Task { try? await failedStream.stopCapture() } }
            throw error
        }
    }

    /// Detaches/finalizes the file before waiting at most two seconds for SCK.
    /// Late samples are ignored; source files are never deleted, including on failure.
    func stopToFile() async {
        let old = captureQueue.sync { () -> SCStream? in
            accepting = false
            generation = nil
            let old = stream
            stream = nil
            measuredLevel = 0
            do { try writer?.close() } catch { errorMessage = error.localizedDescription }
            writer = nil
            converter = nil
            return old
        }
        if let old {
            do { try await bounded(seconds: 2) { try await old.stopCapture() } }
            catch { captureQueue.sync { errorMessage = error.localizedDescription } }
        }
    }

    /// In-memory compatibility for short Fn dictation. Meetings must use stopToFile.
    func stop(relativeTo microphoneStartedAt: Date) async -> CapturedSystemAudio {
        await stopToFile()
        return captureQueue.sync {
            let offset = max(0, firstSampleDate?.timeIntervalSince(microphoneStartedAt) ?? 0)
            let result = CapturedSystemAudio(samples: samples, offsetSamples: Int((offset * sampleRate).rounded()))
            samples = []
            return result
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        captureQueue.async { [self] in
            guard self.stream === stream else { return }
            accepting = false
            measuredLevel = 0
            errorMessage = error.localizedDescription
            do { try writer?.close() } catch { errorMessage = error.localizedDescription }
            writer = nil
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio, accepting, self.stream === stream,
              sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        do {
            let converted = try floatSamples(from: sampleBuffer)
            guard !converted.isEmpty else { return }
            let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            guard pts.isFinite else { throw SystemAudioCaptureError.invalidAudio }
            if firstPTS == nil {
                firstPTS = pts
                firstSampleDate = clockDate.addingTimeInterval(pts - clockPTS)
            }
            received = true
            measuredLevel = min(1, sqrt(converted.reduce(Float(0)) { $0 + $1 * $1 } / Float(converted.count)))
            lastAudioUptime = ProcessInfo.processInfo.systemUptime
            // Preserve gaps (device/screen changes) rather than compressing the timeline.
            let target = Int64(max(0, ((pts - (firstPTS ?? pts)) * sampleRate).rounded()))
            let gap = max(0, target - writtenFrames)
            let skip = Int(min(Int64(converted.count), max(0, writtenFrames - target)))
            if let writer {
                try writer.appendSilence(frames: gap)
                try writer.append(Array(converted.dropFirst(skip)))
            } else {
                samples.append(contentsOf: repeatElement(Float(0), count: Int(gap)))
                samples.append(contentsOf: converted.dropFirst(skip))
            }
            writtenFrames += gap + Int64(converted.count - skip)
        } catch {
            accepting = false
            measuredLevel = 0
            errorMessage = error.localizedDescription
            do { try writer?.close() } catch { errorMessage = error.localizedDescription }
            writer = nil
        }
    }

    private func floatSamples(from sampleBuffer: CMSampleBuffer) throws -> [Float] {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let inputFormat = AVAudioFormat(streamDescription: asbd) else { throw SystemAudioCaptureError.invalidAudio }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frames) else { return [] }
        input.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames), into: input.mutableAudioBufferList) == noErr else {
            throw SystemAudioCaptureError.invalidAudio
        }
        let output: AVAudioPCMBuffer
        if inputFormat == targetFormat {
            output = input
        } else {
            if converter?.inputFormat != inputFormat {
                converter = AVAudioConverter(from: inputFormat, to: targetFormat)
                converter?.primeMethod = .none
            }
            guard let converter else { throw SystemAudioCaptureError.invalidAudio }
            let capacity = AVAudioFrameCount(ceil(Double(frames) * sampleRate / inputFormat.sampleRate)) + 32
            guard let buffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
                throw SystemAudioCaptureError.invalidAudio
            }
            var supplied = false
            var conversionError: NSError?
            let status = converter.convert(to: buffer, error: &conversionError) { _, inputStatus in
                if supplied { inputStatus.pointee = .noDataNow; return nil }
                supplied = true
                inputStatus.pointee = .haveData
                return input
            }
            guard status != .error, conversionError == nil else { throw conversionError ?? SystemAudioCaptureError.invalidAudio as NSError }
            output = buffer
        }
        guard let channel = output.floatChannelData?.pointee else { throw SystemAudioCaptureError.invalidAudio }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}

/// An unstructured operation + one-shot continuation, deliberately NOT a task group:
/// structured concurrency waits for uncooperative children even after cancellation.
private func bounded<T>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let gate = AudioDeadlineGate(continuation)
        Task {
            do { gate.finish(.success(try await operation())) }
            catch { gate.finish(.failure(error)) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            gate.finish(.failure(SystemAudioCaptureError.timeout(seconds: seconds)))
        }
    }
}

private final class AudioDeadlineGate<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }
    func finish(_ result: Result<T, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

private enum SystemAudioCaptureError: LocalizedError {
    case noDisplay, alreadyRunning, invalidAudio
    case timeout(seconds: Double)
    var errorDescription: String? {
        switch self {
        case .noDisplay: return "No display is available for Mac audio capture."
        case .alreadyRunning: return "Mac audio is already recording."
        case .invalidAudio: return "Mac audio could not be converted to recording PCM."
        case .timeout(let seconds): return "Mac audio capture did not respond within \(Int(seconds))s."
        }
    }
}
