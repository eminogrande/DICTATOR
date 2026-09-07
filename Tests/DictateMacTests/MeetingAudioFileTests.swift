import AVFoundation
import XCTest
@testable import DictateMac

final class MeetingAudioFileTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func read(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: try XCTUnwrap(buffer.floatChannelData?[0]), count: Int(buffer.frameLength)))
    }

    func testWAVReadableDuringCaptureAndRetainedAfterClose() throws {
        let url = try temporaryDirectory().appendingPathComponent("system.wav")
        let writer = try MeetingPCMWriter(url: url)
        try writer.append([0.25, -0.25, 0])
        XCTAssertEqual(try read(url).count, 3, "Header must be usable before stop")
        try writer.appendSilence(frames: 16_000)
        try writer.close()
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.length, 16_003)
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
    }

    func testStreamingMixHonorsOffsetAndPreservesSources() throws {
        let directory = try temporaryDirectory()
        let mic = directory.appendingPathComponent("mic.wav")
        let mac = directory.appendingPathComponent("system.wav")
        let mix = directory.appendingPathComponent("mixed.wav")
        let micWriter = try MeetingPCMWriter(url: mic)
        try micWriter.append([Float](repeating: 0.25, count: 16_000))
        try micWriter.close()
        let macWriter = try MeetingPCMWriter(url: mac)
        try macWriter.append([Float](repeating: 0.5, count: 16_000))
        try macWriter.close()
        let originalMic = try Data(contentsOf: mic)
        let originalMac = try Data(contentsOf: mac)
        try MeetingAudioFile.mix(microphone: mic, system: mac, destination: mix, offset: 0.5)
        let samples = try read(mix)
        XCTAssertEqual(samples.count, 24_000)
        XCTAssertEqual(samples[0], 0.25, accuracy: 0.0001)
        XCTAssertEqual(samples[8_000], 0.75, accuracy: 0.0001)
        XCTAssertEqual(samples[16_000], 0.5, accuracy: 0.0001)
        XCTAssertEqual(try Data(contentsOf: mic), originalMic)
        XCTAssertEqual(try Data(contentsOf: mac), originalMac)
        XCTAssertThrowsError(try MeetingAudioFile.mix(microphone: mic, system: mac, destination: mic, offset: 0))
        XCTAssertThrowsError(try MeetingAudioFile.mix(microphone: mic, system: mac, destination: mix, offset: 0))
    }

    func testNegativeOffsetOnlyTrimsTheMixedCopy() throws {
        let directory = try temporaryDirectory()
        let mic = directory.appendingPathComponent("mic.wav")
        let mac = directory.appendingPathComponent("system.wav")
        let mix = directory.appendingPathComponent("mixed.wav")
        let micWriter = try MeetingPCMWriter(url: mic)
        try micWriter.appendSilence(frames: 16_000)
        try micWriter.close()
        let macWriter = try MeetingPCMWriter(url: mac)
        try macWriter.append([Float](repeating: 0.5, count: 16_000))
        try macWriter.close()
        try MeetingAudioFile.mix(microphone: mic, system: mac, destination: mix, offset: -0.5)
        let samples = try read(mix)
        XCTAssertEqual(samples.count, 16_000)
        XCTAssertEqual(samples[0], 0.5, accuracy: 0.0001)
        XCTAssertEqual(samples[8_000], 0, accuracy: 0.0001)
        XCTAssertEqual(try read(mac).count, 16_000)
    }
}
