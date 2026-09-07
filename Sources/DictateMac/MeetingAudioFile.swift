import AVFoundation
import Foundation

/// Streaming meeting mix. The original mic and system recordings are never changed.
enum MeetingAudioFile {
    static func mix(microphone: URL, system: URL, destination: URL, offset: TimeInterval) throws {
        let paths = [microphone, system, destination].map { $0.standardizedFileURL.resolvingSymlinksInPath().path }
        guard paths[2] != paths[0], paths[2] != paths[1], offset.isFinite else {
            throw MeetingAudioFileError.invalidDestination
        }
        let mic = try AVAudioFile(forReading: microphone, commonFormat: .pcmFormatFloat32, interleaved: false)
        let mac = try AVAudioFile(forReading: system, commonFormat: .pcmFormatFloat32, interleaved: false)
        // Both capture sources deliberately use this format; reject an unexpected source
        // rather than silently changing its playback speed or dropping channels.
        for file in [mic, mac] {
            guard file.processingFormat.sampleRate == 16_000, file.processingFormat.channelCount == 1 else {
                throw MeetingAudioFileError.unsupportedFormat
            }
        }
        guard abs(offset) < Double(Int64.max / 16_000) else { throw MeetingAudioFileError.invalidDestination }
        let systemStart = Int64((offset * 16_000).rounded())
        // A system stream which began before the microphone is trimmed only in the mix.
        let systemSkip = min(mac.length, max(0, -systemStart))
        mac.framePosition = systemSkip
        let systemPosition = max(0, systemStart)
        let total = max(mic.length, systemPosition + mac.length - systemSkip)
        let writer = try MeetingPCMWriter(url: destination)
        defer { try? writer.close() }
        let capacity: AVAudioFrameCount = 8_192
        guard let micBuffer = AVAudioPCMBuffer(pcmFormat: mic.processingFormat, frameCapacity: capacity),
              let macBuffer = AVAudioPCMBuffer(pcmFormat: mac.processingFormat, frameCapacity: capacity) else {
            throw MeetingAudioFileError.unsupportedFormat
        }
        var position: Int64 = 0
        while position < total {
            let count = Int(min(Int64(capacity), total - position))
            var mixed = [Float](repeating: 0, count: count)
            if position < mic.length {
                try mic.read(into: micBuffer, frameCount: AVAudioFrameCount(min(Int64(count), mic.length - position)))
                if let data = micBuffer.floatChannelData?[0] {
                    for index in 0..<Int(micBuffer.frameLength) { mixed[index] = data[index] }
                }
            }
            let begin = max(position, systemPosition)
            let end = min(position + Int64(count), systemPosition + mac.length - systemSkip)
            if begin < end {
                try mac.read(into: macBuffer, frameCount: AVAudioFrameCount(end - begin))
                if let data = macBuffer.floatChannelData?[0] {
                    let start = Int(begin - position)
                    for index in 0..<Int(macBuffer.frameLength) {
                        // Preserve a lone source's gain; clamp only where their sum clips.
                        mixed[start + index] += data[index]
                    }
                }
            }
            try writer.append(mixed)
            position += Int64(count)
        }
        try writer.close()
    }
}

enum MeetingAudioFileError: LocalizedError {
    case invalidDestination, unsupportedFormat, fileExists, tooLarge
    var errorDescription: String? {
        switch self {
        case .invalidDestination: return "The mixed recording must have its own destination and a valid audio offset."
        case .unsupportedFormat: return "Meeting audio must be mono, 16 kHz PCM."
        case .fileExists: return "The audio destination already exists; it will not be overwritten."
        case .tooLarge: return "The recording reached the WAV size limit; the audio already saved is retained."
        }
    }
}

/// PCM16 WAV with a valid header after every append, not only at clean shutdown.
/// Small writes go straight to disk; fsync checkpoints occur at least once a second
/// while data arrives. A process crash may lose the final in-flight checkpoint.
final class MeetingPCMWriter {
    private var handle: FileHandle?
    private(set) var frameCount: Int64 = 0
    private var lastSync = ProcessInfo.processInfo.systemUptime

    init(url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { throw MeetingAudioFileError.fileExists }
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: url)
        try updateHeader()
        try handle?.synchronize()
    }

    func append(_ samples: [Float]) throws {
        guard let handle else { throw CocoaError(.fileWriteUnknown) }
        guard frameCount + Int64(samples.count) <= Int64((UInt32.max - 36) / 2) else {
            throw MeetingAudioFileError.tooLarge
        }
        var bytes = Data(capacity: samples.count * 2)
        for sample in samples {
            let finite = sample.isFinite ? sample : 0
            let clipped = min(1, max(-1, finite))
            var value = Int16((clipped * 32_767).rounded()).littleEndian
            withUnsafeBytes(of: &value) { bytes.append(contentsOf: $0) }
        }
        try handle.seekToEnd()
        try handle.write(contentsOf: bytes)
        frameCount += Int64(samples.count)
        try updateHeader()
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastSync >= 1 {
            try handle.synchronize()
            lastSync = now
        }
    }

    func appendSilence(frames: Int64) throws {
        var remaining = frames
        while remaining > 0 {
            let count = Int(min(8_192, remaining))
            try append([Float](repeating: 0, count: count))
            remaining -= Int64(count)
        }
    }

    private func updateHeader() throws {
        guard let handle else { return }
        var header = Data()
        func text(_ value: String) { header.append(contentsOf: value.utf8) }
        func word<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { header.append(contentsOf: $0) }
        }
        let size = UInt32(frameCount * 2)
        text("RIFF"); word(size + 36); text("WAVEfmt "); word(UInt32(16))
        word(UInt16(1)); word(UInt16(1)); word(UInt32(16_000)); word(UInt32(32_000))
        word(UInt16(2)); word(UInt16(16)); text("data"); word(size)
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: header)
    }

    func close() throws {
        guard let handle else { return }
        try updateHeader()
        try handle.synchronize()
        try handle.close()
        self.handle = nil
    }

    deinit { try? close() }
}
