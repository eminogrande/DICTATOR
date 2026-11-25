import XCTest
import DictateMacCore

/// Transcript-only audio retention regressions. Every test uses an isolated
/// temporary archive; no real recordings are ever touched.
final class AudioRetentionTests: XCTestCase {
    private func fixture() throws -> (store: ArchiveStore, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (try ArchiveStore(rootURL: root), root)
    }

    private func cleanup(_ root: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func makeSession(
        in store: ArchiveStore,
        status: DictationStatus,
        transcript: String? = "A verified transcript body.",
        primary: Data? = Data([1, 2, 3, 4]),
        duration: Double? = nil
    ) throws -> DictationSession {
        var session = try store.startSession(sourceApplication: "test")
        if let primary { try primary.write(to: session.audioURL) }
        if let transcript { try store.writeTranscript(transcript, for: session) }
        session.metadata.status = status
        session.metadata.completedAt = status == .completed ? Date() : nil
        session.metadata.durationSeconds = duration
        try store.writeMetadata(for: session)
        return session
    }

    @discardableResult
    private func addFile(_ name: String, _ data: Data, in store: ArchiveStore) throws -> URL {
        let url = store.rootURL.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func persisted(_ session: DictationSession) throws -> DictationMetadata {
        try MetadataCodec.decode(Data(contentsOf: session.metadataURL))
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    // MARK: - Completed cleanup

    func testCompletedCleanupRemovesEveryAudioVariantAndKeepsLineage() throws {
        let (store, root) = try fixture()
        defer { cleanup(root) }
        var session = try makeSession(in: store, status: .completed, duration: 95.5)
        let variants: [(String, Data, WritableKeyPath<DictationMetadata, String?>)] = [
            ("variant-recovered.wav", Data([1, 2, 3, 4, 5]), \.recoveredAudioFilename),
            ("variant-system.wav", Data([1, 2, 3, 4, 5, 6]), \.systemAudioFilename),
            ("variant-mix.wav", Data([1, 2, 3, 4, 5, 6, 7]), \.transcriptionAudioFilename),
            ("variant-compact.m4a", Data([1, 2, 3, 4, 5, 6, 7, 8]), \.compressedAudioFilename),
        ]
        var expectedBytes: Int64 = 4 // primary
        for (name, data, keyPath) in variants {
            try addFile(name, data, in: store)
            session.metadata[keyPath: keyPath] = name
            expectedBytes += Int64(data.count)
        }
        session.metadata.rawTranscriptFilename = "lineage.raw.txt"
        try addFile("lineage.raw.txt", Data("raw".utf8), in: store)
        try store.writeMetadata(for: session)
        let previous = try addFile("session.previous-abc123.txt", Data("older".utf8), in: store)
        let orphan = try addFile("orphan-unreferenced.wav", Data([42]), in: store)

        // Preview counts but deletes nothing and sets no marker.
        let preview = try store.completedAudioCleanupSummary()
        XCTAssertEqual(preview, AudioCleanupSummary(sessionCount: 1, fileCount: 5, bytes: expectedBytes))
        XCTAssertTrue(exists(session.audioURL))
        XCTAssertNil(try persisted(session).audioDeletedAt)

        let summary = try store.deleteCompletedAudio()
        XCTAssertEqual(summary, AudioCleanupSummary(sessionCount: 1, fileCount: 5, bytes: expectedBytes))
        XCTAssertFalse(exists(session.audioURL))
        for (name, _, _) in variants { XCTAssertFalse(exists(store.rootURL.appendingPathComponent(name))) }

        // Text, metadata, derived graph and unreferenced files stay.
        XCTAssertEqual(try String(contentsOf: session.transcriptURL), "A verified transcript body.")
        XCTAssertTrue(exists(session.metadataURL))
        XCTAssertTrue(exists(store.rootURL.appendingPathComponent("lineage.raw.txt")))
        XCTAssertTrue(exists(previous))
        XCTAssertTrue(exists(orphan))
        XCTAssertTrue(exists(store.rootURL.appendingPathComponent("graph.json")))
        XCTAssertTrue(exists(store.rootURL.appendingPathComponent("INDEX.md")))

        // Marker set, references and duration retained for lineage.
        let metadata = try persisted(session)
        XCTAssertNotNil(metadata.audioDeletedAt)
        XCTAssertEqual(metadata.status, .completed)
        XCTAssertEqual(metadata.durationSeconds, 95.5)
        XCTAssertEqual(metadata.audioFilename, session.metadata.audioFilename)
        XCTAssertEqual(metadata.compressedAudioFilename, "variant-compact.m4a")
        XCTAssertNil(metadata.error)
    }

    func testSaveTranscriptAutomaticallyRemovesAudioAfterDurableSuccess() throws {
        let (store, root) = try fixture()
        defer { cleanup(root) }
        let session = try makeSession(in: store, status: .transcribing, transcript: nil)
        let saved = try store.saveTranscript("Retry produced a full transcript.", model: "test", for: session)
        XCTAssertEqual(saved.metadata.status, .completed)
        XCTAssertFalse(exists(session.audioURL))
        XCTAssertEqual(try String(contentsOf: session.transcriptURL), "Retry produced a full transcript.")
        XCTAssertNotNil(try persisted(session).audioDeletedAt)
    }

    func testSaveTranscriptFailureRetainsAudio() throws {
        let (store, root) = try fixture()
        defer { cleanup(root) }
        let session = try makeSession(in: store, status: .saved, transcript: nil)
        XCTAssertThrowsError(try store.saveTranscript("   ", model: "test", for: session))
        XCTAssertTrue(exists(session.audioURL))
        XCTAssertEqual(try persisted(session).status, .saved)
        XCTAssertNil(try persisted(session).audioDeletedAt)
    }

    func testCompleteAutomaticallyRemovesAudioAfterDurableSuccess() throws {
        let (store, root) = try fixture()
        defer { cleanup(root) }
        let session = try makeSession(in: store, status: .completed)
        try store.complete(session)
        XCTAssertFalse(exists(session.audioURL))
        XCTAssertNotNil(try persisted(session).audioDeletedAt)
    }

    func testNonCompletedStatusesRetainAudio() throws {
        let (store, root) = try fixture()
        defer { cleanup(root) }
        var sessions: [DictationSession] = []
        for status in [DictationStatus.recording, .saved, .transcribing, .failed] {
            sessions.append(try makeSession(in: store, status: status))
        }
        XCTAssertEqual(try store.deleteCompletedAudio(), .zero)
        XCTAssertEqual(try store.completedAudioCleanupSummary(), .zero)
        for session in sessions {
            XCTAssertTrue(exists(session.audioURL))
            XCTAssertNil(try persisted(session).audioDeletedAt)
            XCTAssertEqual(try store.removeCompletedAudio(for: session), .zero)
            XCTAssertTrue(exists(session.audioURL))
        }
    }

    func testEmptyWhitespaceOrMissingTranscriptRetainsAudio() throws {
        let (store, root) = try fixture()
        defer { cleanup(root) }
        let blank = try makeSession(in: store, status: .completed, transcript: "  \n\t ")
        let missing = try makeSession(in: store, status: .completed)
        try FileManager.default.removeItem(at: missing.transcriptURL)
        XCTAssertEqual(try store.deleteCompletedAudio(), .zero)
        XCTAssertTrue(exists(blank.audioURL))
        XCTAssertTrue(exists(missing.audioURL))
        XCTAssertNil(try persisted(blank).audioDeletedAt)
    }

    // MARK: - Conservative aborts

    func testUnparseableMetadataAbortsAllCleanup() throws {
        let (store, root) = try fixture()
        defer { cleanup(root) }
        let session = try makeSession(in: store, status: .completed)
        try Data("not json at all".utf8).write(to: store.rootURL.appendingPathComponent("broken.json"))
        XCTAssertThrowsError(try store.completedAudioCleanupSummary()) {
            XCTAssertEqual($0 as? AudioRetentionError, .unreadableMetadata("broken.json"))
        }
        XCTAssertThrowsError(try store.deleteCompletedAudio())
        XCTAssertThrowsError(try store.removeCompletedAudio(for: session))
        // Nothing was deleted and the completed status was never downgraded.
        XCTAssertTrue(exists(session.audioURL))
        XCTAssertEqual(try persisted(session).status, .completed)
        XCTAssertNil(try persisted(session).audioDeletedAt)
    }

    func testSymlinkMetadataAbortsAllCleanup() throws {
        let (store, root) = try fixture()
        defer { cleanup(root) }
        let session = try makeSession(in: store, status: .completed)
        let alias = root.appendingPathComponent("alias.json")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: session.metadataURL)
        XCTAssertThrowsError(try store.completedAudioCleanupSummary())
        XCTAssertThrowsError(try store.deleteCompletedAudio())
        XCTAssertTrue(exists(session.audioURL))
    }

    func testBrokenMetadataSymlinkAbortsAllCleanup() throws {
        let (store, root) = try fixture()
        defer { cleanup(root) }
        let session = try makeSession(in: store, status: .completed)
        let alias = root.appendingPathComponent("broken.json")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root.appendingPathComponent("missing"))
        XCTAssertThrowsError(try store.completedAudioCleanupSummary())
        XCTAssertThrowsError(try store.deleteCompletedAudio())
        XCTAssertTrue(exists(session.audioURL))
    }

    func testPathTraversalReferencesAreSkipped() throws {
        let (store, root) = try fixture()
        defer { cleanup(root) }
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).wav")
        try Data([9, 9]).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }

        var traversal = try makeSession(in: store, status: .completed, primary: nil)
        traversal.metadata.audioFilename = "../\(outside.lastPathComponent)"
        try store.writeMetadata(for: traversal)
        var absolute = try makeSession(in: store, status: .completed, primary: nil)
        absolute.metadata.audioFilename = outside.path
        try store.writeMetadata(for: absolute)
        var nested = try makeSession(in: store, status: .completed, primary: nil)
        let nestedDir = store.rootURL.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        try Data([8]).write(to: nestedDir.appendingPathComponent("deep.wav"))
        nested.metadata.audioFilename = "nested/deep.wav"
        try store.writeMetadata(for: nested)

        XCTAssertEqual(try store.deleteCompletedAudio(), .zero)
        XCTAssertTrue(exists(outside))
        XCTAssertTrue(exists(store.rootURL.appendingPathComponent("nested/deep.wav")))
        XCTAssertNil(try persisted(traversal).audioDeletedAt)
        XCTAssertNil(try persisted(absolute).audioDeletedAt)
        XCTAssertNil(try persisted(nested).audioDeletedAt)
    }

    func testSymlinkAudioAndTranscriptAreNeverFollowed() throws {
        let (store, root) = try fixture()
        defer { cleanup(root) }
        let target = root.deletingLastPathComponent().appendingPathComponent("target-\(UUID().uuidString).wav")
        try Data([5, 5, 5]).write(to: target)
        defer { try? FileManager.default.removeItem(at: target) }

        // Audio path is a symlink: skipped, link and target survive.
        let linked = try makeSession(in: store, status: .completed, primary: nil)
        try FileManager.default.createSymbolicLink(atPath: linked.audioURL.path, withDestinationPath: target.path)
        // Transcript path is a symlink: transcript verification fails, audio retained.
        let fakeTranscript = try makeSession(in: store, status: .completed)
        try FileManager.default.removeItem(at: fakeTranscript.transcriptURL)
        try FileManager.default.createSymbolicLink(atPath: fakeTranscript.transcriptURL.path, withDestinationPath: target.path)

        XCTAssertEqual(try store.deleteCompletedAudio(), .zero)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: linked.audioURL.path), target.path)
        XCTAssertEqual(try Data(contentsOf: target), Data([5, 5, 5]))
        XCTAssertTrue(exists(fakeTranscript.audioURL))
        XCTAssertNil(try persisted(linked).audioDeletedAt)
        XCTAssertNil(try persisted(fakeTranscript).audioDeletedAt)
    }

    func testSharedAudioReferenceIsRetained() throws {
        let (store, root) = try fixture()
        defer { cleanup(root) }
        var first = try makeSession(in: store, status: .completed, primary: Data([1]))
        var second = try makeSession(in: store, status: .completed, primary: Data([2, 2]))
        let shared = try addFile("shared-mix.wav", Data([3, 3, 3]), in: store)
        first.metadata.systemAudioFilename = shared.lastPathComponent
        second.metadata.transcriptionAudioFilename = shared.lastPathComponent
        try store.writeMetadata(for: first)
        try store.writeMetadata(for: second)

        let summary = try store.deleteCompletedAudio()
        XCTAssertEqual(summary, AudioCleanupSummary(sessionCount: 2, fileCount: 2, bytes: 3))
        XCTAssertFalse(exists(first.audioURL))
        XCTAssertFalse(exists(second.audioURL))
        XCTAssertTrue(exists(shared))
    }

    // MARK: - Superseded (compressed) retention

    func testSupersededRemovesOriginalsAndKeepsCompressed() throws {
        let (store, root) = try fixture()
        defer { cleanup(root) }
        var session = try makeSession(in: store, status: .failed, primary: Data([1, 1, 1, 1]))
        let recovered = try addFile("s.recovered-x.wav", Data([2, 2]), in: store)
        let system = try addFile("s.system.wav", Data([3, 3, 3]), in: store)
        let mix = try addFile("s.mix.wav", Data([4]), in: store)
        let compressed = try addFile("s.compact.m4a", Data([9, 9, 9, 9, 9]), in: store)
        session.metadata.recoveredAudioFilename = recovered.lastPathComponent
        session.metadata.systemAudioFilename = system.lastPathComponent
        session.metadata.transcriptionAudioFilename = mix.lastPathComponent
        session.metadata.compressedAudioFilename = compressed.lastPathComponent
        try store.writeMetadata(for: session)

        let summary = try store.removeSupersededAudio(for: session)
        XCTAssertEqual(summary, AudioCleanupSummary(sessionCount: 1, fileCount: 4, bytes: 10))
        XCTAssertFalse(exists(session.audioURL))
        XCTAssertFalse(exists(recovered))
        XCTAssertFalse(exists(system))
        XCTAssertFalse(exists(mix))
        XCTAssertTrue(exists(compressed))
        let metadata = try persisted(session)
        XCTAssertNil(metadata.audioDeletedAt, "Compaction retains playable audio")
        XCTAssertEqual(metadata.status, .failed) // compaction never changes status
        XCTAssertEqual(metadata.compressedAudioFilename, compressed.lastPathComponent)
    }

    func testSupersededRequiresValidPersistedCompressedAudio() throws {
        let (store, root) = try fixture()
        defer { cleanup(root) }
        // No compressed reference at all.
        var session = try makeSession(in: store, status: .saved)
        XCTAssertEqual(try store.removeSupersededAudio(for: session), .zero)
        // Referenced compressed file is missing.
        session.metadata.compressedAudioFilename = "missing.m4a"
        try store.writeMetadata(for: session)
        XCTAssertEqual(try store.removeSupersededAudio(for: session), .zero)
        // Empty compressed file is not a verified encoding.
        let empty = try addFile("empty.m4a", Data(), in: store)
        session.metadata.compressedAudioFilename = empty.lastPathComponent
        try store.writeMetadata(for: session)
        XCTAssertEqual(try store.removeSupersededAudio(for: session), .zero)
        // In-memory-only references are ignored: persisted metadata has none.
        var volatile = session
        volatile.metadata.compressedAudioFilename = nil
        try store.writeMetadata(for: volatile)
        volatile.metadata.compressedAudioFilename = empty.lastPathComponent
        XCTAssertEqual(try store.removeSupersededAudio(for: volatile), .zero)
        XCTAssertTrue(exists(session.audioURL))
        XCTAssertNil(try persisted(session).audioDeletedAt)
    }

    func testSupersededSkipsForeignAndNonAudioReferences() throws {
        let (store, root) = try fixture()
        defer { cleanup(root) }
        var session = try makeSession(in: store, status: .saved, primary: Data([1]))
        let shared = try addFile("shared-source.wav", Data([2, 2]), in: store)
        let evidence = try addFile("evidence-named-like-audio.wav", Data([3, 3, 3]), in: store)
        let compressed = try addFile("ok.m4a", Data([9]), in: store)
        session.metadata.recoveredAudioFilename = shared.lastPathComponent
        session.metadata.systemAudioFilename = evidence.lastPathComponent
        session.metadata.compressedAudioFilename = compressed.lastPathComponent
        session.metadata.enhancementEvidencePaths = [evidence.lastPathComponent]
        try store.writeMetadata(for: session)
        var other = try makeSession(in: store, status: .saved, primary: nil)
        other.metadata.audioFilename = shared.lastPathComponent
        try store.writeMetadata(for: other)

        let summary = try store.removeSupersededAudio(for: session)
        XCTAssertEqual(summary, AudioCleanupSummary(sessionCount: 1, fileCount: 1, bytes: 1))
        XCTAssertFalse(exists(session.audioURL))
        XCTAssertTrue(exists(shared))     // referenced by another session
        XCTAssertTrue(exists(evidence))   // referenced by a non-audio field
        XCTAssertTrue(exists(compressed))
    }

    // MARK: - Robustness

    func testCleanupIsIdempotent() throws {
        let (store, root) = try fixture()
        defer { cleanup(root) }
        let session = try makeSession(in: store, status: .completed)
        XCTAssertEqual(try store.deleteCompletedAudio(), AudioCleanupSummary(sessionCount: 1, fileCount: 1, bytes: 4))
        let marker = try XCTUnwrap(persisted(session).audioDeletedAt)
        XCTAssertEqual(try store.deleteCompletedAudio(), .zero)
        XCTAssertEqual(try store.removeCompletedAudio(for: session), .zero)
        XCTAssertEqual(try persisted(session).audioDeletedAt, marker)
        XCTAssertEqual(try String(contentsOf: session.transcriptURL), "A verified transcript body.")
    }

    func testReadOnlyArchiveDeletesNothingAndKeepsStatus() throws {
        let (store, root) = try fixture()
        defer { cleanup(root) }
        let session = try makeSession(in: store, status: .completed)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        XCTAssertEqual(try store.deleteCompletedAudio(), .zero)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        XCTAssertTrue(exists(session.audioURL))
        XCTAssertEqual(try persisted(session).status, .completed)
        XCTAssertNil(try persisted(session).audioDeletedAt)
    }

    func testNameAndWriteTranscriptPreservesCompressedExtensionAndRefs() throws {
        let (store, root) = try fixture()
        defer { cleanup(root) }
        var session = try store.startSession(sourceApplication: "test")
        // Compressed worker flow: the source of record is now M4A, not WAV.
        let source = try addFile("capture-source.m4a", Data([9, 9, 9]), in: store)
        let recovered = try addFile("capture-source.recovered-deadbeef.wav", Data([7, 7]), in: store)
        session.audioURL = source
        session.metadata.audioFilename = source.lastPathComponent
        session.metadata.recoveredAudioFilename = recovered.lastPathComponent
        try store.writeMetadata(for: session)

        let renamed = try store.nameAndWriteTranscript("Rename keeps the real extension.", for: session)
        XCTAssertEqual(renamed.audioURL.pathExtension, "m4a")
        XCTAssertEqual(renamed.metadata.audioFilename, renamed.audioURL.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: renamed.audioURL), Data([9, 9, 9]))
        XCTAssertFalse(exists(source))
        // Other audio references and their files survive the rename untouched.
        XCTAssertEqual(renamed.metadata.recoveredAudioFilename, recovered.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: recovered), Data([7, 7]))
        let onDisk = try persisted(renamed)
        XCTAssertEqual(onDisk.audioFilename, renamed.audioURL.lastPathComponent)
        XCTAssertEqual(onDisk.recoveredAudioFilename, recovered.lastPathComponent)
    }
}
