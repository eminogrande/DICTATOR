import AppKit
import DictateMacCore
import Foundation

@MainActor
final class BrainController: ObservableObject {
    @Published var query = ""
    @Published var repositoryURL = ""
    @Published private(set) var section: BrainBrowserSection = .home
    @Published private(set) var results: [BrainSearchItem] = []
    @Published private(set) var selectedItem: BrainSearchItem?
    @Published private(set) var stats: BrainStats?
    @Published private(set) var status = "Ready"
    @Published private(set) var isBusy = false

    func refresh() {
        Task {
            await updateManagedRepositories(force: false, reportResult: false)
            await runStats()
            await loadHome()
        }
    }

    func updateManagedRepositories() {
        Task {
            await updateManagedRepositories(force: true, reportResult: true)
        }
    }

    func search() {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        section = .search
        selectedItem = nil
        results = []
        Task {
            await perform("Searching…") {
                let data = try await BrainSidecar.run(["search", value])
                let response = try JSONDecoder().decode(BrainSearchResponse.self, from: data)
                self.results = response.results
                self.selectedItem = response.results.first
                self.status = "\(self.results.count) results"
            }
        }
    }

    func selectSection(_ newSection: BrainBrowserSection) {
        guard newSection != .search else { return }
        section = newSection
        query = ""
        selectedItem = nil
        results = []
        Task {
            if newSection == .home {
                await loadHome()
            } else if let type = newSection.browseType {
                await browse(type: type, limit: 60)
            }
        }
    }

    func goHome() {
        selectSection(.home)
    }

    func clearSearch() {
        goHome()
    }

    func select(_ item: BrainSearchItem) {
        selectedItem = item
    }

    func openSelected() {
        guard let selectedItem else { return }
        open(selectedItem)
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

    func importFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.prompt = "Import into Brain"
        guard panel.runModal() == .OK else { return }
        importSources(panel.urls)
    }

    func syncHermesMemory() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes/memories", isDirectory: true)
        let urls = ["MEMORY.md", "USER.md"]
            .map(directory.appendingPathComponent)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else {
            status = "No Hermes memory files found"
            return
        }
        importSources(urls)
    }

    func importText(label: String, text: String) {
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLabel.isEmpty, !cleanText.isEmpty else {
            status = "Title and text are required"
            return
        }
        Task {
            await perform("Adding context…") {
                let imports = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/DictateMac/Brain/Imports", isDirectory: true)
                try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
                let source = imports.appendingPathComponent("\(UUID().uuidString).txt")
                try cleanText.write(to: source, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path)
                let data = try await BrainSidecar.run(["ingest-file", source.path, "paste", cleanLabel])
                self.stats = try JSONDecoder().decode(BrainStats.self, from: data)
                self.status = "Context added to Brain"
            }
        }
    }

    func open(_ item: BrainSearchItem) {
        guard let path = item.path else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func loadHome() async {
        await browse(type: "recording", limit: 12, statusText: "Recent recordings")
    }

    private func browse(type: String, limit: Int, statusText: String? = nil) async {
        await perform("Loading \(section.title.lowercased())…") {
            let data = try await BrainSidecar.run(["browse", type, String(limit)])
            let response = try JSONDecoder().decode(BrainSearchResponse.self, from: data)
            self.results = response.results
            self.selectedItem = response.results.first
            self.status = statusText ?? "\(self.results.count) \(self.section.title.lowercased())"
        }
    }

    private func runStats() async {
        await perform("Refreshing Brain…") {
            let data = try await BrainSidecar.run(["stats"])
            self.stats = try JSONDecoder().decode(BrainStats.self, from: data)
            self.status = "\(self.stats?.nodes ?? 0) nodes · \(self.stats?.edges ?? 0) connections"
        }
    }

    private func updateManagedRepositories(force: Bool, reportResult: Bool) async {
        await perform(force ? "Updating repositories…" : "Checking repositories…") {
            let arguments = force ? ["managed-repos-refresh", "--force"] : ["managed-repos-refresh"]
            let data = try await BrainSidecar.run(arguments)
            let response = try JSONDecoder().decode(BrainManagedRefreshResponse.self, from: data)
            if reportResult {
                let value = response.repositories
                let statsData = try await BrainSidecar.run(["stats"])
                self.stats = try JSONDecoder().decode(BrainStats.self, from: statsData)
                self.status = "Updated \(value.updated) · unchanged \(value.unchanged) · failed \(value.failed)"
            }
        }
    }

    private func importSources(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            await perform("Importing \(urls.count) source\(urls.count == 1 ? "" : "s")…") {
                var latest: BrainStats?
                for url in urls {
                    let data = try await BrainSidecar.run(["ingest-file", url.path])
                    latest = try JSONDecoder().decode(BrainStats.self, from: data)
                }
                self.stats = latest
                self.status = "Imported \(urls.count) source\(urls.count == 1 ? "" : "s")"
            }
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

enum BrainSidecar {
    static func run(_ arguments: [String]) async throws -> Data {
        guard let resources = Bundle.main.resourceURL else { throw BrainError.missingResources }
        let root = resources.appendingPathComponent("Brain", isDirectory: true)
        let node = root.appendingPathComponent("node")
        let script = root.appendingPathComponent("dist/brain-cli.js")
        guard FileManager.default.isExecutableFile(atPath: node.path), FileManager.default.fileExists(atPath: script.path) else {
            throw BrainError.missingResources
        }
        let result = try await SubprocessCapture.run(
            executableURL: node,
            arguments: [script.path] + arguments,
            currentDirectoryURL: root
        )
        guard result.terminationStatus == 0 else {
            let message = String(decoding: result.stderr, as: UTF8.self)
            throw BrainError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.stdout
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
