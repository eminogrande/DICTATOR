import DictateMacCore
import Foundation

struct BrainEvidenceProvider {
    func evidence(for transcript: String) async -> [BrainEvidenceItem] {
        let keywords = GraphBrainText.analyze(transcript).keywords.prefix(12).joined(separator: " ")
        let query = keywords.isEmpty ? String(transcript.prefix(400)) : keywords
        var items: [BrainSearchItem] = []
        if let data = try? await BrainSidecar.run(["search", query]),
           let response = try? JSONDecoder().decode(BrainSearchResponse.self, from: data) {
            items.append(contentsOf: response.results.prefix(8))
        }
        return boundedEvidence(from: items)
    }

    private func boundedEvidence(from items: [BrainSearchItem], limit: Int = 8) -> [BrainEvidenceItem] {
        var seen: Set<String> = []
        return items.compactMap { item -> BrainEvidenceItem? in
            guard seen.insert(item.id).inserted else { return nil }
            return BrainEvidenceItem(
                id: item.id,
                type: item.type,
                label: item.label,
                path: item.path,
                excerpt: String(item.excerpt.prefix(600)),
                url: item.path.flatMap(RepositoryURLResolver.githubURL)
            )
        }.prefix(limit).map { $0 }
    }
}

private enum RepositoryURLResolver {
    static func githubURL(for path: String) -> String? {
        var directory = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue {
            directory.deleteLastPathComponent()
        }
        for _ in 0..<16 {
            let config = directory.appendingPathComponent(".git/config")
            if let contents = try? String(contentsOf: config, encoding: .utf8),
               let remote = contents.split(separator: "\n").compactMap({ line -> String? in
                   let value = line.trimmingCharacters(in: .whitespaces)
                   guard value.hasPrefix("url = ") else { return nil }
                   return String(value.dropFirst(6))
               }).first,
               let normalized = normalize(remote) {
                return normalized
            }
            let parent = directory.deletingLastPathComponent()
            if parent == directory { break }
            directory = parent
        }
        return nil
    }

    private static func normalize(_ remote: String) -> String? {
        var value = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("git@github.com:") {
            value = "https://github.com/" + value.dropFirst("git@github.com:".count)
        } else if value.hasPrefix("ssh://git@github.com/") {
            value = "https://github.com/" + value.dropFirst("ssh://git@github.com/".count)
        }
        guard value.hasPrefix("https://github.com/") else { return nil }
        if value.hasSuffix(".git") { value.removeLast(4) }
        return value
    }
}
