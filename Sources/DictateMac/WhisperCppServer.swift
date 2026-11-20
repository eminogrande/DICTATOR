import DictateMacCore
import Foundation

/// Keeps the large Whisper model loaded between takes. Localhost only; audio never leaves the Mac.
actor WhisperCppServer {
    static let shared = WhisperCppServer()
    private static let processLock = NSLock()
    private static var runningProcess: Process?

    private let endpoint = URL(string: "http://127.0.0.1:17891")!
    private var process: Process?
    private var logDirectory: URL?

    static func shutdown() {
        processLock.lock()
        let process = runningProcess
        runningProcess = nil
        processLock.unlock()
        if process?.isRunning == true { process?.terminate() }
    }

    private static func register(_ process: Process) {
        processLock.lock()
        runningProcess = process
        processLock.unlock()
    }

    func transcribe(wavURL: URL, timeout: TimeInterval = 120) async throws -> WhisperCppService.Result {
        try await start(timeout: timeout)
        let request = try Self.request(wavURL: wavURL, endpoint: endpoint, timeout: timeout)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw EngineValidationError("Local transcription server failed: \(String(decoding: data, as: UTF8.self))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["text"] as? String else {
            throw EngineValidationError("Local transcription server returned no transcript.")
        }
        let text = TranscriptCleaner.clean(raw)
        guard !text.isEmpty else { throw EngineValidationError("Local engine produced no transcript.") }
        return WhisperCppService.Result(text: text, model: "whisper.cpp large-v3-turbo (warm)")
    }

    private func start(timeout: TimeInterval) async throws {
        if process?.isRunning == true { return }
        let directory = try EngineValidation.temporaryOutputDirectory()
        logDirectory = directory
        let log = directory.appendingPathComponent("server.log")
        guard FileManager.default.createFile(atPath: log.path, contents: nil,
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: log)
        let child = Process()
        child.executableURL = TranscriptionEngine.wcppServerURL
        child.arguments = [
            "--host", "127.0.0.1", "--port", "\(endpoint.port!)",
            "-m", TranscriptionEngine.wcppModelURL.path,
            "-l", "auto", "-t", "8", "-p", "1", "-fa",
            "-vm", TranscriptionEngine.wcppVADModelURL.path, "--vad"
        ]
        child.environment = TranscriptionEngine.localEnvironment
        child.standardOutput = handle
        child.standardError = handle
        do { try child.run() } catch {
            try? handle.close()
            throw error
        }
        process = child
        Self.register(child)
        try? handle.close() // The child retains its own descriptor.

        let deadline = ContinuousClock.now + .seconds(timeout)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if !child.isRunning {
                let message = (try? String(contentsOf: log, encoding: .utf8)) ?? "Process exited."
                throw EngineValidationError("Could not start local transcription server.\n\(message)")
            }
            var request = URLRequest(url: endpoint.appendingPathComponent("health"))
            request.timeoutInterval = 1
            if let (_, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        Self.shutdown()
        throw EngineValidationError("Local model loading timed out.")
    }

    static func request(wavURL: URL, endpoint: URL, timeout: TimeInterval) throws -> URLRequest {
        let boundary = "DICTATOR-" + UUID().uuidString
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"take.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
        body.append(try Data(contentsOf: wavURL))
        append("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"response_format\"\r\n\r\njson\r\n--\(boundary)--\r\n")
        var request = URLRequest(url: endpoint.appendingPathComponent("inference"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }
}
