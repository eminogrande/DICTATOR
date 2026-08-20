import Foundation

/// Fn+A mode: compress a transcript to a minimal numbered list via local Ollama (qwen3:4b).
/// No network beyond localhost; falls back to the full transcript if Ollama is unavailable.
struct CompressService {
    struct Result: Sendable {
        let compressed: String
        let model: String
        let tookSeconds: Double
    }

    enum CompressError: LocalizedError {
        case ollamaUnavailable
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .ollamaUnavailable:
                return "Ollama is not running (localhost:11434)."
            case .emptyResponse:
                return "Compression model returned no text."
            }
        }
    }

    static let defaultModel = "qwen3:4b"

    private static var endpoint: URL {
        URL(string: "http://127.0.0.1:11434/api/generate")!
    }

    /// Compress `transcript` into a minimal numbered list in the transcript's own language.
    /// Timeout-bounded so a stuck Ollama never blocks delivery.
    static func compress(_ transcript: String, model: String = defaultModel) async throws -> Result {
        let prompt = """
        /no_think
        Compress the following dictated text into a minimal numbered list. Rules:
        - Match the language of the input exactly. Never translate.
        - As few words as possible per point; keep every distinct piece of information.
        - No preamble, no closing remarks, no markdown headers. Output ONLY the numbered list.
        - If a point is an action item, start it with a verb.

        Text:
        \(transcript)
        """
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": ["temperature": 0.2, "num_predict": 300]
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = object["response"] as? String else {
            throw CompressError.emptyResponse
        }
        let trimmed = response
            .replacingOccurrences(of: "<think>", with: "")
            .replacingOccurrences(of: "</think>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CompressError.emptyResponse
        }
        return Result(compressed: trimmed, model: model, tookSeconds: 0)
    }
}
