import Foundation

/// Outcome of an audio cleanup pass. Counts reflect actual deletions (or, for the
/// preview, confirmed-deletable files); never speculative matches.
public struct AudioCleanupSummary: Equatable, Sendable {
    public let sessionCount: Int
    public let fileCount: Int
    public let bytes: Int64

    public init(sessionCount: Int, fileCount: Int, bytes: Int64) {
        self.sessionCount = sessionCount
        self.fileCount = fileCount
        self.bytes = bytes
    }

    public static let zero = AudioCleanupSummary(sessionCount: 0, fileCount: 0, bytes: 0)
}

/// Cleanup refuses to run when ownership cannot be proven from the full archive.
public enum AudioRetentionError: Error, Equatable {
    /// A metadata file in the archive could not be read or parsed; cleanup aborts
    /// conservatively because exclusive file ownership can no longer be verified.
    case unreadableMetadata(String)
    /// The on-disk metadata no longer belongs to the caller's in-memory session.
    case sessionMismatch(String)
}

/// Transcript-only audio retention.
///
/// Rules (docs/AUDIO_STORAGE_PLAN.md):
/// - Only sessions with a persisted `.completed` status and a readable, nonempty
///   (after trimming) UTF-8 transcript lose their audio.
/// - Candidates come exclusively from explicit metadata references
///   (audioFilename, recoveredAudioFilename, systemAudioFilename,
///   transcriptionAudioFilename, compressedAudioFilename). Nothing is ever
///   inferred from filename prefixes or directory listings.
/// - A candidate must be an archive-local, regular, non-symbolic-link file with a
///   known audio extension, referenced by this session's audio fields only and by
///   no field of any other session. Path traversal, symlinks and foreign/shared
///   files are skipped.
/// - Every metadata file in the archive is inspected (recursively). If any is
///   unreadable, cleanup aborts before touching a single file.
/// - Deletion is idempotent; `audioDeletedAt` is persisted only after files were
///   actually removed. Filename references remain in metadata for lineage, and a
///   partial failure never downgrades a completed status.
extension ArchiveStore {
    private enum Policy {
        static let audioExtensions: Set<String> = ["wav", "m4a", "aac", "caf", "mp3", "aiff", "aif"]
        static let transcriptExtensions: Set<String> = ["txt"]
    }

    private struct Inventory {
        struct Entry {
            let metadataURL: URL
            let metadata: DictationMetadata
            let audioKeys: Set<String>
            let nonAudioKeys: Set<String>
            var owner: String { metadataURL.standardizedFileURL.path }
        }
        var entries: [Entry] = []
        /// Normalized filename -> set of metadata files referencing it from ANY field.
        var owners: [String: Set<String>] = [:]
    }

    private struct DeletionCandidate {
        let url: URL
        let size: Int64
    }

    // MARK: - Public API

    /// Preview: how much audio the confirmed cleanup of completed sessions would
    /// remove. Deletes nothing and writes no markers. Throws when any metadata in
    /// the archive is unreadable.
    public func completedAudioCleanupSummary() throws -> AudioCleanupSummary {
        let inventory = try retentionInventory()
        var sessions = 0
        var files = 0
        var bytes: Int64 = 0
        for entry in inventory.entries {
            let plan = completedPlan(for: entry, inventory: inventory)
            guard !plan.isEmpty else { continue }
            sessions += 1
            files += plan.count
            bytes += plan.reduce(into: Int64(0)) { $0 += $1.size }
        }
        return AudioCleanupSummary(sessionCount: sessions, fileCount: files, bytes: bytes)
    }

    /// Confirmed cleanup: remove session-owned audio for every completed session
    /// with a verified transcript. Idempotent; already-cleaned sessions count as zero.
    public func deleteCompletedAudio() throws -> AudioCleanupSummary {
        let inventory = try retentionInventory()
        var sessions = 0
        var files = 0
        var bytes: Int64 = 0
        for entry in inventory.entries {
            let plan = completedPlan(for: entry, inventory: inventory)
            guard !plan.isEmpty else { continue }
            let result = execute(plan, for: entry)
            sessions += result.sessionCount
            files += result.fileCount
            bytes += result.bytes
        }
        return AudioCleanupSummary(sessionCount: sessions, fileCount: files, bytes: bytes)
    }

    /// Remove this session's audio once its completed metadata and a nonempty
    /// transcript are durable. The persisted metadata is re-read before deletion;
    /// non-completed or unverifiable sessions are a no-op (zero summary).
    public func removeCompletedAudio(for session: DictationSession) throws -> AudioCleanupSummary {
        let inventory = try retentionInventory()
        let persisted = try persistedMetadata(for: session)
        let entry = inventoryEntry(metadataURL: session.metadataURL, metadata: persisted)
        let plan = completedPlan(for: entry, inventory: inventory)
        guard !plan.isEmpty else { return .zero }
        return execute(plan, for: entry)
    }

    /// Compression support: once a valid compressed audio file is persisted, remove
    /// this session's remaining original/variant audio while keeping the compressed
    /// file. Works for any status (failed/saved sessions keep their retry source in
    /// compressed form). Never touches files referenced by any field of another
    /// session or by non-audio fields. No-op without a valid compressed reference.
    public func removeSupersededAudio(for session: DictationSession) throws -> AudioCleanupSummary {
        let inventory = try retentionInventory()
        let persisted = try persistedMetadata(for: session)
        guard let compressedName = persisted.compressedAudioFilename,
              let compressed = validatedArchiveFile(named: compressedName, allowedExtensions: Policy.audioExtensions),
              compressed.size > 0 else { return .zero }
        let entry = inventoryEntry(metadataURL: session.metadataURL, metadata: persisted)
        let plan = supersededPlan(for: entry, inventory: inventory)
        guard !plan.isEmpty else { return .zero }
        try synchronizeFile(compressed.url)
        try synchronizeFile(session.metadataURL)
        return execute(plan, for: entry, markCompletedDeletion: false)
    }

    // MARK: - Inventory

    /// Every metadata file under the archive root, recursively. Any unreadable or
    /// unparseable metadata aborts the whole pass so shared ownership can never be
    /// misjudged. The derived graph.json is not session metadata and is skipped.
    private func retentionInventory() throws -> Inventory {
        var inventory = Inventory()
        let manager = FileManager.default
        var scanFailure: URL?
        guard let enumerator = manager.enumerator(
            at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [],
            errorHandler: { url, _ in scanFailure = url; return false }
        ) else { throw AudioRetentionError.unreadableMetadata(rootURL.lastPathComponent) }
        for case let file as URL in enumerator {
            guard file.pathExtension.lowercased() == "json", file.lastPathComponent != "graph.json" else { continue }
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink == false else {
                throw AudioRetentionError.unreadableMetadata(file.lastPathComponent)
            }
            guard let data = try? Data(contentsOf: file),
                  let metadata = try? MetadataCodec.decode(data) else {
                throw AudioRetentionError.unreadableMetadata(file.lastPathComponent)
            }
            let entry = inventoryEntry(metadataURL: file, metadata: metadata)
            for key in entry.audioKeys.union(entry.nonAudioKeys) {
                inventory.owners[key, default: []].insert(entry.owner)
            }
            inventory.entries.append(entry)
        }
        if let scanFailure { throw AudioRetentionError.unreadableMetadata(scanFailure.lastPathComponent) }
        return inventory
    }

    private func inventoryEntry(metadataURL: URL, metadata: DictationMetadata) -> Inventory.Entry {
        Inventory.Entry(
            metadataURL: metadataURL,
            metadata: metadata,
            audioKeys: Set(Self.audioReferenceNames(metadata).map(Self.referenceKey)),
            nonAudioKeys: Set(Self.nonAudioReferenceNames(metadata).map(Self.referenceKey))
        )
    }

    /// Re-read the persisted metadata instead of trusting the caller's in-memory copy.
    private func persistedMetadata(for session: DictationSession) throws -> DictationMetadata {
        guard let data = try? Data(contentsOf: session.metadataURL),
              let metadata = try? MetadataCodec.decode(data) else {
            throw AudioRetentionError.unreadableMetadata(session.metadataURL.lastPathComponent)
        }
        guard metadata.sessionID == session.metadata.sessionID else {
            throw AudioRetentionError.sessionMismatch(session.metadataURL.lastPathComponent)
        }
        return metadata
    }

    // MARK: - Reference fields (never inferred from prefixes or listings)

    private static func audioReferenceNames(_ metadata: DictationMetadata) -> [String] {
        [
            metadata.audioFilename,
            metadata.recoveredAudioFilename,
            metadata.systemAudioFilename,
            metadata.transcriptionAudioFilename,
            metadata.compressedAudioFilename,
        ].compactMap { $0 }
    }

    private static func nonAudioReferenceNames(_ metadata: DictationMetadata) -> [String] {
        var names = [metadata.transcriptFilename]
        names.append(contentsOf: [
            metadata.rawTranscriptFilename,
            metadata.metadataFilename,
        ].compactMap { $0 })
        names.append(contentsOf: metadata.enhancementEvidencePaths ?? [])
        names.append(contentsOf: (metadata.usefulContext ?? []).map(\.sourcePath))
        return names
    }

    /// Ownership key: the plain filename, case-folded (archive volumes may be
    /// case-insensitive). References containing directories fold to their last
    /// component so they still block same-named candidates conservatively.
    private static func referenceKey(_ name: String) -> String {
        URL(fileURLWithPath: name).lastPathComponent.lowercased()
    }

    // MARK: - Planning

    /// Completed retention: requires persisted completed status plus a readable,
    /// nonempty transcript. All five audio reference fields are candidates.
    private func completedPlan(for entry: Inventory.Entry, inventory: Inventory) -> [DeletionCandidate] {
        guard entry.metadata.status == .completed, hasVerifiedTranscript(entry.metadata) else { return [] }
        return deletionPlan(for: entry, inventory: inventory, excluding: [])
    }

    /// Superseded retention: keep the compressed file, delete the remaining
    /// exclusively owned audio references (originals and derived variants).
    private func supersededPlan(for entry: Inventory.Entry, inventory: Inventory) -> [DeletionCandidate] {
        let compressedKey = entry.metadata.compressedAudioFilename.map(Self.referenceKey)
        return deletionPlan(for: entry, inventory: inventory, excluding: compressedKey.map { [$0] } ?? [])
    }

    private func deletionPlan(
        for entry: Inventory.Entry,
        inventory: Inventory,
        excluding excludedKeys: Set<String>
    ) -> [DeletionCandidate] {
        var plan: [DeletionCandidate] = []
        var seen: Set<String> = []
        for name in Self.audioReferenceNames(entry.metadata) {
            let key = Self.referenceKey(name)
            guard !key.isEmpty, !seen.contains(key), !excludedKeys.contains(key) else { continue }
            seen.insert(key)
            // Exclusive ownership: referenced by this session's metadata file only,
            // across every reference field of every session in the archive.
            guard inventory.owners[key] == [entry.owner] else { continue }
            // Never delete something the session itself references as non-audio.
            guard !entry.nonAudioKeys.contains(key) else { continue }
            guard let file = validatedArchiveFile(named: name, allowedExtensions: Policy.audioExtensions) else { continue }
            plan.append(DeletionCandidate(url: file.url, size: file.size))
        }
        return plan
    }

    private func hasVerifiedTranscript(_ metadata: DictationMetadata) -> Bool {
        guard let file = validatedArchiveFile(named: metadata.transcriptFilename, allowedExtensions: Policy.transcriptExtensions),
              let text = try? String(contentsOf: file.url, encoding: .utf8) else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - File validation

    /// Accept only archive-local, regular, non-symbolic-link files with an allowed
    /// extension, named by a bare filename (no separators, traversal, or dotfiles).
    /// Anything else returns nil and is skipped.
    private func validatedArchiveFile(
        named name: String,
        allowedExtensions: Set<String>
    ) -> (url: URL, size: Int64)? {
        guard !name.isEmpty,
              !name.hasPrefix("."),
              !name.contains("/"), !name.contains("\\"),
              name != ".", name != "..",
              name == URL(fileURLWithPath: name).lastPathComponent,
              allowedExtensions.contains(URL(fileURLWithPath: name).pathExtension.lowercased())
        else { return nil }
        let url = rootURL.appendingPathComponent(name)
        // Even after resolving every symlink, the file must sit directly in the archive root.
        let rootPath = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.deletingLastPathComponent().path == rootPath else { return nil }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true,
              values.isSymbolicLink == false
        else { return nil }
        return (url, Int64(values.fileSize ?? 0))
    }

    // MARK: - Deletion

    private func synchronizeFile(_ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    /// Delete the planned files, then mark `audioDeletedAt`. Per-file failures are
    /// skipped; a marker-write failure is logged but never thrown back over an
    /// otherwise completed session. Metadata references stay intact for lineage.
    private func execute(_ plan: [DeletionCandidate], for entry: Inventory.Entry, markCompletedDeletion: Bool = true) -> AudioCleanupSummary {
        if markCompletedDeletion {
            // All callers, including historical cleanup, must cross the same
            // durability gate before deleting their only audio copy.
            do {
                try synchronizeFile(rootURL.appendingPathComponent(entry.metadata.transcriptFilename))
                try synchronizeFile(entry.metadataURL)
            } catch {
                NSLog("DICTATOR audio cleanup durability check failed: %@", error.localizedDescription)
                return .zero
            }
        }
        let manager = FileManager.default
        var files = 0
        var bytes: Int64 = 0
        for candidate in plan {
            // Re-validate immediately before removal (plan may be stale).
            guard let current = validatedArchiveFile(
                named: candidate.url.lastPathComponent, allowedExtensions: Policy.audioExtensions
            ), current.url.standardizedFileURL == candidate.url.standardizedFileURL else { continue }
            do {
                try manager.removeItem(at: current.url)
                files += 1
                bytes += current.size
            } catch {
                NSLog("DICTATOR audio cleanup could not remove %@: %@", current.url.lastPathComponent, error.localizedDescription)
            }
        }
        guard files > 0 else { return .zero }
        let result = AudioCleanupSummary(sessionCount: 1, fileCount: files, bytes: bytes)
        // Compaction retains playable audio. Partial cleanup or shared references
        // must not claim that a session is transcript-only.
        guard markCompletedDeletion,
              let data = try? Data(contentsOf: entry.metadataURL),
              var metadata = try? MetadataCodec.decode(data),
              metadata.sessionID == entry.metadata.sessionID,
              metadata.status == .completed,
              hasVerifiedTranscript(metadata),
              !Self.audioReferenceNames(metadata).contains(where: {
                  manager.fileExists(atPath: rootURL.appendingPathComponent($0).path)
              }) else { return result }
        metadata.audioDeletedAt = Date()
        let updated = DictationSession(
            folderURL: rootURL,
            audioURL: rootURL.appendingPathComponent(metadata.audioFilename),
            transcriptURL: rootURL.appendingPathComponent(metadata.transcriptFilename),
            metadataURL: entry.metadataURL,
            metadata: metadata
        )
        do { try writeMetadata(for: updated) }
        catch { NSLog("DICTATOR audio cleanup marker could not persist for %@: %@", entry.metadataURL.lastPathComponent, error.localizedDescription) }
        return AudioCleanupSummary(sessionCount: 1, fileCount: files, bytes: bytes)
    }
}
