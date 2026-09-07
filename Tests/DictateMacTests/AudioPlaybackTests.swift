import AVFAudio
import XCTest
@testable import DictateMac

final class AudioPlaybackTests: XCTestCase {
    /// Real mono PCM WAV: one second of silence, 8 kHz, signed 16-bit.
    /// Files live only in a unique temporary directory, never the user's library.
    private func fixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DICTATOR-player-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("silence.wav")
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func u32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        text("RIFF"); u32(36 + 16_000); text("WAVE")
        text("fmt "); u32(16); u16(1); u16(1)
        u32(8_000); u32(16_000); u16(2); u16(16)
        text("data"); u32(16_000)
        data.append(Data(repeating: 0, count: 16_000))
        try data.write(to: url)
        return url
    }

    @MainActor
    func testRealWAVPreparesReadsDurationAndSeeksWithoutPlayback() throws {
        let url = try fixture()
        let original = try Data(contentsOf: url)
        let realPlayer = try AVAudioPlayer(contentsOf: url)
        XCTAssertTrue(realPlayer.prepareToPlay())
        XCTAssertEqual(realPlayer.duration, 1, accuracy: 0.001)
        let model = AudioPlaybackModel(makePlayer: { _ in realPlayer })
        model.load(url)
        XCTAssertTrue(model.isLoaded)
        XCTAssertTrue(model.canPlay)
        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(realPlayer.isPlaying)
        XCTAssertEqual(model.duration, 1, accuracy: 0.001)
        model.seek(to: 0.5)
        XCTAssertEqual(model.elapsed, 0.5, accuracy: 0.001)
        XCTAssertEqual(realPlayer.currentTime, 0.5, accuracy: 0.001)
        model.stop()
        XCTAssertEqual(model.elapsed, 0)
        XCTAssertEqual(realPlayer.currentTime, 0, accuracy: 0.001)
        XCTAssertFalse(realPlayer.isPlaying)
        XCTAssertEqual(try Data(contentsOf: url), original)
        // Deliberately never call play/togglePlayback on a real player.
    }

    @MainActor
    func testNilMissingAndInvalidFilesHaveHonestStates() throws {
        let model = AudioPlaybackModel()
        model.load(nil)
        XCTAssertFalse(model.canPlay)
        XCTAssertEqual(model.statusText, "Keine Audiodatei verfügbar")
        let valid = try fixture()
        model.load(valid.deletingLastPathComponent().appendingPathComponent("missing.wav"))
        XCTAssertEqual(model.errorMessage, "Audiodatei nicht verfügbar")
        let invalid = valid.deletingLastPathComponent().appendingPathComponent("invalid.wav")
        try Data("not an audio file".utf8).write(to: invalid)
        model.load(invalid)
        XCTAssertEqual(model.errorMessage, "Audiodatei kann nicht gelesen werden")
        XCTAssertFalse(model.canPlay)
        XCTAssertEqual(model.duration, 0)
        model.togglePlayback()
        XCTAssertFalse(model.isPlaying)
    }

    @MainActor
    func testSilentTransportPlayPauseResumeAndStop() throws {
        let player = SilentPlayer()
        let model = AudioPlaybackModel(makePlayer: { _ in player })
        model.load(try fixture())
        XCTAssertEqual(player.playCalls, 0, "Loading must not autoplay")
        model.togglePlayback()
        XCTAssertTrue(model.isPlaying)
        player.currentTime = 0.4
        model.togglePlayback()
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.elapsed, 0.4)
        XCTAssertEqual(player.pauseCalls, 1)
        model.togglePlayback()
        XCTAssertTrue(model.isPlaying)
        XCTAssertEqual(player.currentTime, 0.4)
        model.stop()
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.elapsed, 0)
        XCTAssertFalse(player.isPlaying)
    }

    @MainActor
    func testDisabledImmediatelyStopsAndBlocksEveryActionWithoutResuming() throws {
        let player = SilentPlayer()
        let model = AudioPlaybackModel(makePlayer: { _ in player })
        model.load(try fixture())
        model.togglePlayback()
        model.seek(to: 0.5)
        model.setDisabled(true)
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.canPlay)
        XCTAssertEqual(model.elapsed, 0)
        model.seek(to: 0.75)
        model.togglePlayback()
        XCTAssertEqual(model.elapsed, 0)
        XCTAssertEqual(player.playCalls, 1)
        model.setDisabled(false)
        XCTAssertTrue(model.canPlay)
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(player.playCalls, 1)
    }

    @MainActor
    func testLoadingWhileDisabledDoesNotEnableTransport() throws {
        let player = SilentPlayer()
        let model = AudioPlaybackModel(makePlayer: { _ in player })
        model.setDisabled(true)
        model.load(try fixture())
        model.togglePlayback()
        model.seek(to: 0.5)
        XCTAssertTrue(model.isLoaded)
        XCTAssertFalse(model.canPlay)
        XCTAssertEqual(model.elapsed, 0)
        XCTAssertEqual(player.playCalls, 0)
    }

    @MainActor
    func testURLReplacementAndRemovalStopOldTransportAndReset() throws {
        let first = SilentPlayer()
        let second = SilentPlayer()
        var loads = 0
        let model = AudioPlaybackModel(makePlayer: { _ in
            loads += 1
            return loads == 1 ? first : second
        })
        model.load(try fixture())
        model.togglePlayback()
        model.seek(to: 0.7)
        model.load(try fixture())
        XCTAssertFalse(first.isPlaying)
        XCTAssertNil(first.delegate)
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.elapsed, 0)
        XCTAssertEqual(second.playCalls, 0)
        model.load(nil)
        XCTAssertFalse(model.isLoaded)
        XCTAssertEqual(model.duration, 0)
        XCTAssertNil(second.delegate)
    }

    @MainActor
    func testSeekClampsAndRejectsNonfiniteInput() throws {
        let player = SilentPlayer()
        let model = AudioPlaybackModel(makePlayer: { _ in player })
        model.load(try fixture())
        model.seek(to: -1)
        XCTAssertEqual(model.elapsed, 0)
        model.seek(to: 99)
        XCTAssertEqual(model.elapsed, 1)
        model.seek(to: .nan)
        model.seek(to: .infinity)
        XCTAssertEqual(model.elapsed, 1)
        XCTAssertEqual(player.playCalls, 0)
        model.togglePlayback()
        XCTAssertEqual(player.currentTime, 0, "Playing from the end restarts")
        model.stop()
    }

    @MainActor
    func testCompletionAndFailureResetPlayingState() throws {
        let player = SilentPlayer()
        let model = AudioPlaybackModel(makePlayer: { _ in player })
        model.load(try fixture())
        model.togglePlayback()
        model.playbackFinished(successfully: true)
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.elapsed, 0)
        XCTAssertNil(model.errorMessage)
        model.togglePlayback()
        model.playbackFinished(successfully: false)
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.errorMessage, "Wiedergabe wurde unterbrochen")
        XCTAssertFalse(model.canPlay)
    }

    @MainActor
    func testFailedPrepareAndFailedPlayAreNotReportedAsPlaying() throws {
        let url = try fixture()
        let player = SilentPlayer()
        player.prepareSucceeds = false
        let model = AudioPlaybackModel(makePlayer: { _ in player })
        model.load(url)
        XCTAssertFalse(model.isLoaded)
        XCTAssertNotNil(model.errorMessage)
        player.prepareSucceeds = true
        player.playSucceeds = false
        model.load(url)
        model.togglePlayback()
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.errorMessage, "Wiedergabe konnte nicht gestartet werden")
    }

    @MainActor
    func testActiveTimerDoesNotRetainModelAndDeinitStopsTransport() throws {
        let player = SilentPlayer()
        var model: AudioPlaybackModel? = AudioPlaybackModel(makePlayer: { _ in player })
        weak var weakModel = model
        model?.load(try fixture())
        model?.togglePlayback()
        XCTAssertTrue(player.isPlaying)
        model = nil
        XCTAssertNil(weakModel)
        XCTAssertFalse(player.isPlaying)
    }

    @MainActor
    func testSamePathFinalizationReloadsAfterIncompleteAudio() throws {
        let url = try fixture()
        let finalized = try Data(contentsOf: url)
        try Data("Incomplete WAV".utf8).write(to: url)
        let model = AudioPlaybackModel()
        model.load(url)
        XCTAssertFalse(model.isLoaded)
        XCTAssertNotNil(model.errorMessage)
        try finalized.write(to: url)
        // The view reloads on the finalized status/size/duration revision, not URL identity alone.
        model.load(url)
        XCTAssertTrue(model.isLoaded)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.duration, 1, accuracy: 0.001)
        XCTAssertFalse(model.isPlaying)
    }

    @MainActor
    func testCaptureNotificationSynchronouslyStopsAndDisablesBeforePostReturns() throws {
        let player = SilentPlayer()
        let model = AudioPlaybackModel(makePlayer: { _ in player })
        model.load(try fixture())
        model.togglePlayback()
        model.seek(to: 0.5)
        NotificationCenter.default.post(name: Notification.Name("DICTATORCaptureWillStart"), object: nil)
        // No await, timer tick or run-loop drain is permitted before assertions.
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(model.isPlaying)
        XCTAssertTrue(model.isDisabled)
        XCTAssertEqual(model.elapsed, 0)
        XCTAssertEqual(player.currentTime, 0)
        model.togglePlayback()
        model.seek(to: 0.5)
        XCTAssertEqual(player.playCalls, 1)
        XCTAssertEqual(model.elapsed, 0)
        NotificationCenter.default.post(name: Notification.Name("DICTATORCaptureStartupDidFinish"), object: true)
        XCTAssertTrue(model.isDisabled)
        // A denied/cancelled startup must unlock without needing a rendered binding transition.
        NotificationCenter.default.post(name: Notification.Name("DICTATORCaptureStartupDidFinish"), object: false)
        XCTAssertFalse(model.isDisabled)
        XCTAssertTrue(model.canPlay)
        XCTAssertFalse(model.isPlaying)
    }

    @MainActor
    func testTimeLabels() {
        XCTAssertEqual(AudioPlaybackModel.timeLabel(0), "0:00")
        XCTAssertEqual(AudioPlaybackModel.timeLabel(65.9), "1:05")
        XCTAssertEqual(AudioPlaybackModel.timeLabel(3_661), "1:01:01")
        XCTAssertEqual(AudioPlaybackModel.timeLabel(.nan), "0:00")
        XCTAssertEqual(AudioPlaybackModel.timeLabel(-1), "0:00")
    }
}

/// Pure silent transport: no device, session, microphone or play() on AVAudioPlayer.
private final class SilentPlayer: AudioPlaybackControlling {
    let duration: TimeInterval = 1
    var currentTime: TimeInterval = 0
    private(set) var isPlaying = false
    weak var delegate: (any AVAudioPlayerDelegate)?
    var prepareSucceeds = true
    var playSucceeds = true
    private(set) var playCalls = 0
    private(set) var pauseCalls = 0
    func prepareToPlay() -> Bool { prepareSucceeds }
    func play() -> Bool {
        playCalls += 1
        isPlaying = playSucceeds
        return playSucceeds
    }
    func pause() { pauseCalls += 1; isPlaying = false }
    func stop() { isPlaying = false }
}
