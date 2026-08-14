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

    @discardableResult
    static func requestPermission() -> Bool {
        isAuthorized || CGRequestScreenCaptureAccess()
    }

    private let sampleRate = 16_000.0
    private let captureQueue = DispatchQueue(label: "de.emin.DictateMac.system-audio")
    private var samples: [Float] = []
    private var stream: SCStream?
    private var startedAt: Date?

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        guard let display = content.displays.first else {
            throw SystemAudioCaptureError.noDisplay
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )
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
        self.stream = stream
        samples = []
        try await stream.startCapture()
        startedAt = Date()
    }

    func stop(relativeTo microphoneStartedAt: Date) async -> CapturedSystemAudio {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        let offset = max(0, startedAt?.timeIntervalSince(microphoneStartedAt) ?? 0)
        startedAt = nil
        return captureQueue.sync {
            CapturedSystemAudio(
                samples: samples,
                offsetSamples: Int((offset * sampleRate).rounded())
            )
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio,
              sampleBuffer.isValid,
              CMSampleBufferDataIsReady(sampleBuffer),
              let converted = Self.floatSamples(from: sampleBuffer, sampleRate: sampleRate) else {
            return
        }
        samples.append(contentsOf: converted)
    }

    private static func floatSamples(
        from sampleBuffer: CMSampleBuffer,
        sampleRate: Double
    ) -> [Float]? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let inputFormat = AVAudioFormat(streamDescription: streamDescription) else {
            return nil
        }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0,
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else {
            return nil
        }
        inputBuffer.frameLength = frameCount
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: inputBuffer.mutableAudioBufferList
        ) == noErr else {
            return nil
        }

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        let outputBuffer: AVAudioPCMBuffer
        if inputFormat == targetFormat {
            outputBuffer = inputBuffer
        } else {
            guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                return nil
            }
            let capacity = AVAudioFrameCount(
                ceil(Double(frameCount) * targetFormat.sampleRate / inputFormat.sampleRate)
            ) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
                return nil
            }
            var supplied = false
            var conversionError: NSError?
            let status = converter.convert(to: converted, error: &conversionError) { _, inputStatus in
                if supplied {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                supplied = true
                inputStatus.pointee = .haveData
                return inputBuffer
            }
            guard status != .error, conversionError == nil else { return nil }
            outputBuffer = converted
        }

        guard let channel = outputBuffer.floatChannelData?.pointee else { return nil }
        return Array(UnsafeBufferPointer(start: channel, count: Int(outputBuffer.frameLength)))
    }
}

private enum SystemAudioCaptureError: LocalizedError {
    case noDisplay

    var errorDescription: String? {
        "No display is available for Mac audio capture."
    }
}
