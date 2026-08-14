import AppKit
import DictateMacCore
import Foundation

@MainActor
final class BrainController: ObservableObject {
    @Published var query = ""
    @Published var repositoryURL = ""
    @Published private(set) var results: [BrainSearchItem] = []
    @Published private(set) var stats: BrainStats?
    @Published private(set) var status = "Ready"
    @Published private(set) var isBusy = false

    func refresh() { Task { await runStats() } }

    func search() {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        Task {
            await perform("Searching…") {
                let data = try await BrainSidecar.run(["search", value])
                let response = try JSONDecoder().decode(BrainSearchResponse.self, from: data)
                self.results = response.results
                self.status = "\(self.results.count) results"
            }
        }
    }

    func importRepository() {
        let value = repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("https://github.com/") || FileManager.default.fileExists(atPath: value) else {
            status = "Enter a GitHub URL or local repository path"
            return
        }
        Task {
            await perform("Importing repository…") {
                let data = try await BrainSidecar.run(["import-repo", value])
                self.stats = try JSONDecoder().decode(BrainStats.self, from: data)
                self.repositoryURL = ""
                self.status = "Imported \(self.stats?.files ?? 0) files · \(self.stats?.functions ?? 0) functions"
            }
        }
    }

    func open(_ item: BrainSearchItem) {
        guard let path = item.path else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func runStats() async {
        await perform("Refreshing Brain…") {
            let data = try await BrainSidecar.run(["stats"])
            self.stats = try JSONDecoder().decode(BrainStats.self, from: data)
            self.status = "\(self.stats?.nodes ?? 0) nodes · \(self.stats?.edges ?? 0) connections"
        }
    }

    private func perform(_ busyStatus: String, operation: @escaping @MainActor () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        status = busyStatus
        do { try await operation() }
        catch { status = "Brain error: \(error.localizedDescription)" }
        isBusy = false
    }
}

private enum BrainSidecar {
    static func run(_ arguments: [String]) async throws -> Data {
        guard let resources = Bundle.main.resourceURL else { throw BrainError.missingResources }
        let root = resources.appendingPathComponent("Brain", isDirectory: true)
        let node = root.appendingPathComponent("node")
        let script = root.appendingPathComponent("dist/brain-cli.js")
        guard FileManager.default.isExecutableFile(atPath: node.path), FileManager.default.fileExists(atPath: script.path) else {
            throw BrainError.missingResources
        }
        return try await Task.detached {
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = node
            process.arguments = [script.path] + arguments
            process.currentDirectoryURL = root
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            if process.terminationStatus != 0 {
                let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                throw BrainError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return data
        }.value
    }
}

private enum BrainError: LocalizedError {
    case missingResources
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingResources: "Bundled Brain engine is missing"
        case let .commandFailed(message): message.isEmpty ? "Brain command failed" : message
        }
    }
}
