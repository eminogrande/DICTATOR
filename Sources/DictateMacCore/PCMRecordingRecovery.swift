import Foundation

/// Copy-only salvage for inactive AVAudioRecorder microphone WAVs. Not a general WAV repairer.
public enum PCMRecordingRecovery {
    public enum RecoveryError: Error, LocalizedError {
        case unsupportedOrInvalid, sourceChanged, destinationExists, activeSession

        public var errorDescription: String? {
            switch self {
            case .unsupportedOrInvalid: return "Microphone WAV is unsupported, truncated, or ambiguous; original retained."
            case .sourceChanged: return "Microphone WAV changed during recovery; original retained."
            case .destinationExists: return "Recovery destination already exists."
            case .activeSession: return "Microphone recovery requires an inactive session."
            }
        }
    }

    private struct Snapshot: Equatable {
        let size: UInt64
        let inode: UInt64
        let device: UInt64
        let modified: Date
        let created: Date

        init(_ url: URL) throws {
            let a = try FileManager.default.attributesOfItem(atPath: url.path)
            guard a[.type] as? FileAttributeType == .typeRegular,
                  let size = a[.size] as? NSNumber,
                  let inode = a[.systemFileNumber] as? NSNumber,
                  let device = a[.systemNumber] as? NSNumber,
                  let modified = a[.modificationDate] as? Date,
                  let created = a[.creationDate] as? Date else {
                throw RecoveryError.unsupportedOrInvalid
            }
            self.size = size.uint64Value
            self.inode = inode.uint64Value
            self.device = device.uint64Value
            self.modified = modified
            self.created = created
        }
    }

    /// Returns false without creating a destination for already-finalized PCM WAVs.
    /// A repair requires the exact native 4096-byte JUNK/fmt/FLLR/data header and
    /// consistent zero-length or stale checkpoints. No sample bytes are discarded.
    /// Caller must establish exclusive ownership: this detects changes, not future writers.
    @discardableResult
    public static func recover(source: URL, destination: URL) throws -> Bool {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path) else { throw RecoveryError.destinationExists }
        let before = try Snapshot(source)
        guard before.size >= 44, before.size <= UInt64(UInt32.max) + 8 else {
            throw RecoveryError.unsupportedOrInvalid
        }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        // Header reads and chunk traversal are bounded independently of recording length.
        let header = try input.read(upToCount: Int(min(before.size, 65_536))) ?? Data()
        guard header.count >= 12, tag(header, 0) == "RIFF", tag(header, 8) == "WAVE" else {
            throw RecoveryError.unsupportedOrInvalid
        }
        let riffLength = UInt64(u32(header, 4))
        var offset = 12
        var formatSeen = false
        var dataOffset: Int?
        var dataLength: UInt64 = 0
        var chunks: [(String, Int, UInt32)] = []
        for _ in 0..<128 {
            guard offset <= header.count - 8 else { break }
            let name = tag(header, offset)
            let length = u32(header, offset + 4)
            chunks.append((name, offset, length))
            if name == "data" {
                guard formatSeen else { throw RecoveryError.unsupportedOrInvalid }
                dataOffset = offset + 8
                dataLength = UInt64(length)
                break
            }
            let end = UInt64(offset) + 8 + UInt64(length) + UInt64(length & 1)
            guard end <= UInt64(header.count) else { throw RecoveryError.unsupportedOrInvalid }
            if name == "fmt " {
                guard !formatSeen, length == 16,
                      u16(header, offset + 8) == 1, u16(header, offset + 10) == 1,
                      u32(header, offset + 12) == 16_000, u32(header, offset + 16) == 32_000,
                      u16(header, offset + 20) == 2, u16(header, offset + 22) == 16 else {
                    throw RecoveryError.unsupportedOrInvalid
                }
                formatSeen = true
            } else if name != "JUNK" && name != "FLLR" {
                throw RecoveryError.unsupportedOrInvalid
            }
            offset = Int(end)
        }
        guard let start = dataOffset else { throw RecoveryError.unsupportedOrInvalid }
        let actualLength = before.size - UInt64(start)
        guard dataLength <= actualLength, actualLength % 2 == 0, dataLength % 2 == 0 else {
            throw RecoveryError.unsupportedOrInvalid
        }
        if riffLength == before.size - 8 && dataLength == actualLength {
            guard try Snapshot(source) == before else { throw RecoveryError.sourceChanged }
            return false
        }
        // A plain/foreign WAV with bytes after its advertised data is NOT evidence of PCM.
        guard start == 4096, chunks.count == 4,
              chunks[0].0 == "JUNK", chunks[0].1 == 12, chunks[0].2 == 28,
              chunks[1].0 == "fmt ", chunks[1].1 == 48, chunks[1].2 == 16,
              chunks[2].0 == "FLLR", chunks[2].1 == 72, chunks[2].2 == 4008,
              chunks[3].0 == "data", chunks[3].1 == 4088,
              actualLength > 0,
              riffLength == 4088 + dataLength || (riffLength == 0 && dataLength == 0) else {
            throw RecoveryError.unsupportedOrInvalid
        }
        // Reject a recognizable trailing RIFF chunk at a stale data boundary rather
        // than silently interpreting an appended metadata/container chunk as samples.
        if dataLength > 0 && dataLength < actualLength {
            try input.seek(toOffset: UInt64(start) + dataLength)
            let tail = try input.read(upToCount: 8) ?? Data()
            if tail.count == 8 && ["LIST", "JUNK", "FLLR", "RIFF", "data", "fmt ", "bext", "iXML", "cue "].contains(tag(tail, 0)) {
                throw RecoveryError.unsupportedOrInvalid
            }
        }
        guard try Snapshot(source) == before else { throw RecoveryError.sourceChanged }
        // copyItem is disk-backed and refuses an existing destination (including races).
        // Do not clean up a failed copy: it may be somebody else's pre-existing file.
        try manager.copyItem(at: source, to: destination)
        var keep = false
        defer { if !keep { try? manager.removeItem(at: destination) } }
        let output = try FileHandle(forUpdating: destination)
        defer { try? output.close() }
        guard try Snapshot(destination).size == before.size else { throw RecoveryError.sourceChanged }
        try input.seek(toOffset: 0)
        try output.seek(toOffset: 0)
        var remaining = before.size
        while remaining > 0 {
            let count = Int(min(remaining, 1_048_576))
            let original = try input.read(upToCount: count) ?? Data()
            let copied = try output.read(upToCount: count) ?? Data()
            guard original.count == count, original == copied else { throw RecoveryError.sourceChanged }
            remaining -= UInt64(count)
        }
        guard try Snapshot(source) == before else { throw RecoveryError.sourceChanged }
        try output.seek(toOffset: 4)
        try output.write(contentsOf: littleEndian(UInt32(before.size - 8)))
        try output.seek(toOffset: UInt64(start - 4))
        try output.write(contentsOf: littleEndian(UInt32(actualLength)))
        try output.synchronize()
        guard try Snapshot(source) == before else { throw RecoveryError.sourceChanged }
        keep = true
        return true
    }

    private static func tag(_ data: Data, _ offset: Int) -> String {
        String(decoding: data[offset..<(offset + 4)], as: UTF8.self)
    }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 |
            UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }

    private static func littleEndian(_ value: UInt32) -> Data {
        Data((0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
}
