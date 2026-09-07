import AVFoundation
import Foundation

@MainActor
final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var stoppedElapsed: TimeInterval = 0

    var isRecording: Bool { recorder?.isRecording == true }
    var elapsed: TimeInterval { recorder?.currentTime ?? stoppedElapsed }

    /// Linear RMS amplitude, measured by AVAudioRecorder (not an animation).
    var level: Float {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        let decibels = recorder.averagePower(forChannel: 0)
        guard decibels.isFinite else { return 0 }
        return min(1, max(0, pow(10, decibels / 20)))
    }

    static var isAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    func start(at url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        stoppedElapsed = 0
        guard recorder.prepareToRecord(), recorder.record() else {
            throw AudioRecorderError.couldNotStart
        }
        self.recorder = recorder
    }

    func stop() {
        stoppedElapsed = recorder?.currentTime ?? stoppedElapsed
        recorder?.stop()
        recorder = nil
    }
}

private enum AudioRecorderError: LocalizedError {
    case couldNotStart

    var errorDescription: String? {
        "The microphone recording could not be started."
    }
}
