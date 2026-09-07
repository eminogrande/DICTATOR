import XCTest
import AVFAudio
import CryptoKit
@testable import DictateMacCore

final class PCMRecordingRecoveryTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pcm-recovery-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func put32(_ value: UInt32, at offset: Int, in data: inout Data) {
        for i in 0..<4 { data[offset + i] = UInt8(truncatingIfNeeded: value >> (i * 8)) }
    }

    /// AVAudioRecorder's observed 4096-byte native layout, with one second of PCM.
    private func nativeWAV(checkpoint: UInt32 = 0, finalized: Bool = false) -> Data {
        var data = Data(repeating: 0, count: 4096)
        for (offset, text) in [(0, "RIFF"), (8, "WAVE"), (12, "JUNK"), (48, "fmt "), (72, "FLLR"), (4088, "data")] {
            data.replaceSubrange(offset..<(offset + 4), with: text.utf8)
        }
        put32(28, at: 16, in: &data)
        put32(16, at: 52, in: &data)
        data[56] = 1; data[58] = 1
        put32(16_000, at: 60, in: &data)
        put32(32_000, at: 64, in: &data)
        data[68] = 2; data[70] = 16
        put32(4008, at: 76, in: &data)
        let declared: UInt32 = finalized ? 32_000 : checkpoint
        put32(4088 + declared, at: 4, in: &data)
        put32(declared, at: 4092, in: &data)
        // Nonzero deterministic samples; byte-level assertions detect any payload damage.
        for frame in 0..<16_000 {
            let sample = UInt16(bitPattern: Int16(frame % 200 - 100))
            data.append(UInt8(truncatingIfNeeded: sample))
            data.append(UInt8(truncatingIfNeeded: sample >> 8))
        }
        return data
    }

    func testNativeZeroLengthRecoveryDecodesAndPreservesOriginalAndPCM() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source.wav")
        let destination = root.appendingPathComponent("recovered.wav")
        let original = nativeWAV()
        try original.write(to: source)
        let digest = SHA256.hash(data: original)
        XCTAssertTrue(try PCMRecordingRecovery.recover(source: source, destination: destination))
        let sourceAfter = try Data(contentsOf: source)
        XCTAssertEqual(sourceAfter, original)
        XCTAssertEqual(SHA256.hash(data: sourceAfter), digest)
        let recovered = try Data(contentsOf: destination)
        XCTAssertEqual(recovered.count, original.count)
        XCTAssertEqual(recovered.dropFirst(4096), original.dropFirst(4096))
        for index in original.indices where !(4..<8).contains(index) && !(4092..<4096).contains(index) {
            XCTAssertEqual(original[index], recovered[index])
        }
        let file = try AVAudioFile(forReading: destination, commonFormat: .pcmFormatFloat32, interleaved: false)
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertEqual(file.length, 16_000)
        XCTAssertEqual(Double(file.length) / file.fileFormat.sampleRate, 1, accuracy: 0.0001)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_000))
        try file.read(into: buffer)
        XCTAssertEqual(buffer.frameLength, 16_000)
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        XCTAssertEqual(samples[0], Float(-100) / 32_768, accuracy: 0.000001)
        XCTAssertEqual(samples[199], Float(99) / 32_768, accuracy: 0.000001)
    }

    func testStaleCheckpointAndZeroRIFFRecover() throws {
        let root = try temporaryDirectory()
        for (index, checkpoint) in [UInt32(3200), UInt32(0)].enumerated() {
            var bytes = nativeWAV(checkpoint: checkpoint)
            if index == 1 { put32(0, at: 4, in: &bytes) }
            let source = root.appendingPathComponent("source-\(index).wav")
            let destination = root.appendingPathComponent("derived-\(index).wav")
            try bytes.write(to: source)
            XCTAssertTrue(try PCMRecordingRecovery.recover(source: source, destination: destination))
            XCTAssertEqual(try Data(contentsOf: source), bytes)
            XCTAssertEqual(try AVAudioFile(forReading: destination).length, 16_000)
        }
    }

    func testValidFilesAreNoOpAndRecoveredCopyIsIdempotent() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source.wav")
        let derived = root.appendingPathComponent("derived.wav")
        try nativeWAV(finalized: true).write(to: source)
        XCTAssertFalse(try PCMRecordingRecovery.recover(source: source, destination: derived))
        XCTAssertFalse(FileManager.default.fileExists(atPath: derived.path))
        try nativeWAV().write(to: source)
        XCTAssertTrue(try PCMRecordingRecovery.recover(source: source, destination: derived))
        let second = root.appendingPathComponent("second.wav")
        XCTAssertFalse(try PCMRecordingRecovery.recover(source: derived, destination: second))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
    }

    func testRejectsUnsupportedTruncatedInvalidAndAmbiguousFiles() throws {
        let root = try temporaryDirectory()
        var cases = [Data("not a WAV".utf8), Data(nativeWAV().prefix(4095))]
        var wrongRate = nativeWAV(); put32(44_100, at: 60, in: &wrongRate); cases.append(wrongRate)
        var stereo = nativeWAV(); stereo[58] = 2; cases.append(stereo)
        var floating = nativeWAV(); floating[56] = 3; cases.append(floating)
        var odd = nativeWAV(); odd.append(1); cases.append(odd)
        var oversized = nativeWAV(); put32(UInt32.max, at: 16, in: &oversized); cases.append(oversized)
        var dataTooLong = nativeWAV(); put32(64_000, at: 4092, in: &dataTooLong); cases.append(dataTooLong)
        var mismatch = nativeWAV(); put32(5000, at: 4, in: &mismatch); cases.append(mismatch)
        var foreign = nativeWAV(); foreign.replaceSubrange(72..<76, with: "JUNK".utf8); cases.append(foreign)
        var trailingChunk = nativeWAV(checkpoint: 3200)
        trailingChunk.replaceSubrange(7296..<7300, with: "LIST".utf8); cases.append(trailingChunk)
        var empty = Data(nativeWAV().prefix(4096)); put32(0, at: 4, in: &empty); cases.append(empty)
        for (index, bytes) in cases.enumerated() {
            let source = root.appendingPathComponent("invalid-\(index).wav")
            let destination = root.appendingPathComponent("derived-\(index).wav")
            try bytes.write(to: source)
            XCTAssertThrowsError(try PCMRecordingRecovery.recover(source: source, destination: destination), "case \(index)")
            XCTAssertEqual(try Data(contentsOf: source), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testExistingDestinationIsNeverOverwritten() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source.wav")
        let destination = root.appendingPathComponent("existing.wav")
        let original = nativeWAV()
        let sentinel = Data("existing bytes".utf8)
        try original.write(to: source)
        try sentinel.write(to: destination)
        XCTAssertThrowsError(try PCMRecordingRecovery.recover(source: source, destination: destination))
        XCTAssertEqual(try Data(contentsOf: destination), sentinel)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertThrowsError(try PCMRecordingRecovery.recover(source: source, destination: source))
    }

    func testArchiveIntegrationPreservesSourcesWarningsMixAndStaleCallIdempotence() throws {
        let root = try temporaryDirectory()
        let archive = try ArchiveStore(rootURL: root)
        var session = try archive.startSession(sourceApplication: "Meeting")
        session.metadata.status = .saved
        session.metadata.captureWarning = "Mac audio unavailable."
        session.metadata.transcriptionAudioFilename = "existing-mix.wav"
        try archive.writeMetadata(for: session)
        let original = nativeWAV()
        try original.write(to: session.audioURL)
        let recovered = try archive.recoverMicrophone(for: session)
        XCTAssertEqual(recovered.audioURL, session.audioURL)
        XCTAssertEqual(recovered.metadata.audioFilename, session.metadata.audioFilename)
        XCTAssertEqual(recovered.metadata.transcriptionAudioFilename, "existing-mix.wav")
        XCTAssertTrue(try XCTUnwrap(recovered.metadata.captureWarning).hasPrefix("Mac audio unavailable."))
        XCTAssertNotNil(recovered.metadata.recoveredAudioFilename)
        let metadataBytes = try Data(contentsOf: session.metadataURL)
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        let again = try archive.recoverMicrophone(for: session) // deliberately stale input
        XCTAssertEqual(again.metadata.recoveredAudioFilename, recovered.metadata.recoveredAudioFilename)
        XCTAssertEqual(try Data(contentsOf: session.metadataURL), metadataBytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), files)
        XCTAssertEqual(try Data(contentsOf: session.audioURL), original)
        XCTAssertEqual(try MetadataCodec.decode(metadataBytes).recoveredAudioFilename, recovered.metadata.recoveredAudioFilename)
    }

    func testArchiveValidAndImportedNoOpAndActiveRefusal() throws {
        let archive = try ArchiveStore(rootURL: temporaryDirectory())
        var session = try archive.startSession(sourceApplication: "Meeting")
        try nativeWAV(finalized: true).write(to: session.audioURL)
        XCTAssertThrowsError(try archive.recoverMicrophone(for: session))
        session.metadata.status = .saved
        try archive.writeMetadata(for: session)
        let before = try Data(contentsOf: session.metadataURL)
        XCTAssertNil(try archive.recoverMicrophone(for: session).metadata.recoveredAudioFilename)
        XCTAssertEqual(try Data(contentsOf: session.metadataURL), before)
        session.metadata.sourceApplication = "Imported"
        session.metadata.recordingKind = "import"
        try nativeWAV().write(to: session.audioURL)
        XCTAssertNil(try archive.recoverMicrophone(for: session).metadata.recoveredAudioFilename)
        XCTAssertEqual(try Data(contentsOf: session.metadataURL), before)
        XCTAssertNil(try MetadataCodec.decode(before).recoveredAudioFilename)
    }

    func testInterruptedInvalidDoesNotPreventOtherSessionRecovery() throws {
        let archive = try ArchiveStore(rootURL: temporaryDirectory())
        var invalid = try archive.startSession(sourceApplication: "Meeting")
        invalid.metadata.captureWarning = "Existing warning."
        try archive.writeMetadata(for: invalid)
        try Data("fake WAV".utf8).write(to: invalid.audioURL)
        var valid = try archive.startSession(sourceApplication: nil)
        valid.metadata.recordingKind = "dictation"
        valid.metadata.status = .transcribing
        try archive.writeMetadata(for: valid)
        try nativeWAV().write(to: valid.audioURL)
        try archive.recoverInterruptedSessions()
        let sessions = archive.sessions()
        XCTAssertEqual(sessions.count, 2)
        XCTAssertTrue(sessions.allSatisfy { $0.metadata.status == .saved })
        let failedRecovery = try XCTUnwrap(sessions.first { $0.metadata.sessionID == invalid.metadata.sessionID })
        XCTAssertNil(failedRecovery.metadata.recoveredAudioFilename)
        XCTAssertTrue(try XCTUnwrap(failedRecovery.metadata.captureWarning).hasPrefix("Existing warning."))
        XCTAssertNotNil(sessions.first { $0.metadata.sessionID == valid.metadata.sessionID }?.metadata.recoveredAudioFilename)
        XCTAssertEqual(try Data(contentsOf: invalid.audioURL), Data("fake WAV".utf8))
        XCTAssertEqual(try Data(contentsOf: valid.audioURL), nativeWAV())
    }
}
