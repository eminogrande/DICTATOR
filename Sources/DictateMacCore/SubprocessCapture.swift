import Foundation

public struct CapturedSubprocessResult: Sendable {
    public let terminationStatus: Int32
    public let stdout: Data
    public let stderr: Data

    public init(terminationStatus: Int32, stdout: Data, stderr: Data) {
        self.terminationStatus = terminationStatus
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct SubprocessTimeout: LocalizedError {
    public var errorDescription: String? { "Local engine validation timed out. Retry or choose another quality." }
}

public enum SubprocessCapture {
    public static func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> CapturedSubprocessResult {
        try await Task.detached {
            let fileManager = FileManager.default
            let directory = fileManager.temporaryDirectory
                .appendingPathComponent("dictator-process-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            defer { try? fileManager.removeItem(at: directory) }

            let stdoutURL = directory.appendingPathComponent("stdout")
            let stderrURL = directory.appendingPathComponent("stderr")
            guard fileManager.createFile(
                atPath: stdoutURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ), fileManager.createFile(
                atPath: stderrURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }

            let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
            let stderrHandle = try FileHandle(forWritingTo: stderrURL)
            defer {
                try? stdoutHandle.close()
                try? stderrHandle.close()
            }

            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectoryURL
            process.environment = environment
            process.standardOutput = stdoutHandle
            process.standardError = stderrHandle
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            try process.run()
            if let timeout, finished.wait(timeout: .now() + timeout) == .timedOut {
                // Only the process owned by this call (a readiness probe) is stopped.
                process.terminate()
                if finished.wait(timeout: .now() + 2) == .timedOut {
                    kill(process.processIdentifier, SIGKILL)
                    finished.wait()
                }
                throw SubprocessTimeout()
            } else if timeout == nil {
                finished.wait()
            }
            process.waitUntilExit()
            try stdoutHandle.close()
            try stderrHandle.close()

            return CapturedSubprocessResult(
                terminationStatus: process.terminationStatus,
                stdout: try Data(contentsOf: stdoutURL),
                stderr: try Data(contentsOf: stderrURL)
            )
        }.value
    }
}
