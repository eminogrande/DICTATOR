import Foundation
import AVFAudio
import DictateMacCore

/// Read-only presentation facts. Browsing old recordings never migrates their source files.
struct SessionLibraryInfo: Sendable {
    let title: String
    let kind: String
    let durationSeconds: Double?
    let wordCount: Int
    let transcript: String
    let audioURL: URL?
    let audioBytes: Int64?

    init(session: DictationSession) {
        let metadata = session.metadata
        kind = Self.kind(for: metadata)
        title = Self.title(for: metadata)
        transcript = (try? String(contentsOf: session.transcriptURL, encoding: .utf8)) ?? ""
        wordCount = Self.countWords(transcript)
        // Prefer the completed mix; never play only the mic when the saved mix exists.
        let mixed = metadata.transcriptionAudioFilename.map { session.folderURL.appendingPathComponent($0) }
        let recovered = metadata.recoveredAudioFilename.map { session.folderURL.appendingPathComponent($0) }
        let candidates = [mixed, recovered, session.audioURL].compactMap { $0 }
        let playable = candidates.first { url in
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let bytes = attributes[.size] as? NSNumber else { return false }
            return bytes.int64Value > 0
        }
        audioURL = playable
        audioBytes = playable.flatMap { url in
            ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value
        }
        let measured: Double? = playable.flatMap { url in
            guard let audio = try? AVAudioFile(forReading: url), audio.processingFormat.sampleRate > 0 else { return nil }
            let seconds = Double(audio.length) / audio.processingFormat.sampleRate
            return seconds.isFinite && seconds > 0 ? seconds : nil
        }
        if let measured { durationSeconds = measured }
        else if let saved = metadata.durationSeconds, saved.isFinite, saved > 0 { durationSeconds = saved }
        else { durationSeconds = nil }
    }

    var durationLabel: String { Self.durationLabel(durationSeconds) }
    var sizeLabel: String {
        guard let audioBytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: audioBytes, countStyle: .file)
    }

    static func kind(for metadata: DictationMetadata) -> String {
        switch metadata.recordingKind {
        case "meeting": return "Meeting"
        case "dictation": return "Diktat"
        case "import": return "Import"
        default: return "Aufnahme" // Old flags cannot reliably distinguish meetings from Fn.
        }
    }

    static func title(for metadata: DictationMetadata) -> String {
        if let custom = metadata.displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty { return custom }
        if let original = metadata.originalFilename, !original.isEmpty {
            return URL(fileURLWithPath: original).deletingPathExtension().lastPathComponent
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd. MMM · HH:mm"
        let number = metadata.sequence.map { " #\($0)" } ?? ""
        return metadata.sequence == nil ? "\(kind(for: metadata)) · \(formatter.string(from: metadata.startedAt))" : "\(kind(for: metadata))\(number)"
    }

    static func countWords(_ text: String) -> Int {
        // Unicode words; punctuation alone is never counted as a word.
        let expression = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}]+(?:['’][\\p{L}\\p{N}]+)*")
        return expression.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    static func durationLabel(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
        let value = Int(min(seconds, Double(Int.max / 2)))
        if value >= 3_600 { return String(format: "%d:%02d:%02d", value / 3_600, (value / 60) % 60, value % 60) }
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
