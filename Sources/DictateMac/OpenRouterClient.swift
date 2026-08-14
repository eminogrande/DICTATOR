import DictateMacCore
import Foundation

struct OpenRouterClient {
    let apiKey: String
    let model: String

    func enhance(transcript: String, evidence: [BrainEvidenceItem]) async throws -> TranscriptEnhancement {
        let evidenceJSON = String(decoding: try JSONEncoder().encode(evidence), as: UTF8.self)
        let content = try await complete(
            system: """
            Correct only obvious speech-recognition mistakes in the supplied transcript. Preserve every spoken idea, word choice, filler, language, tone, order, repetition, and uncertainty. Do not improve style, grammar, clarity, or concision. When uncertain, copy the original exactly. Punctuation and casing may be fixed. For every changed word or phrase, report original, replacement, and confidence from 0 to 1; only make changes at confidence 0.90 or higher. Never insert Brain facts or links into correctedTranscript unless spoken. Put up to 3 optional grounded recall items in usefulContext. Every recall item must copy an exact sourcePath and optional exact url from the supplied evidence. Return JSON only: {"correctedTranscript":"...","corrections":[{"original":"...","replacement":"...","confidence":0.99}],"usefulContext":[{"title":"...","detail":"...","url":null,"sourcePath":"exact path"}]}.
            """,
            user: "RAW TRANSCRIPT:\n\(transcript)\n\nBRAIN EVIDENCE:\n\(evidenceJSON)"
        )
        let data = try jsonData(from: content)
        return try JSONDecoder().decode(TranscriptEnhancement.self, from: data)
    }


    private func complete(system: String, user: String) async throws -> String {
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
            throw OpenRouterError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://github.com/eminogrande/DictateMac", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("DICTATOR", forHTTPHeaderField: "X-OpenRouter-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenRouterError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw OpenRouterError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            let api = try? JSONDecoder().decode(OpenRouterErrorResponse.self, from: data)
            throw OpenRouterError.api(api?.error.message ?? "HTTP \(http.statusCode)")
        }
        let result = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
        guard let content = result.choices.first?.message.content, !content.isEmpty else {
            throw OpenRouterError.invalidResponse
        }
        return content
    }

    private func jsonData(from content: String) throws -> Data {
        guard let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}"), start <= end else {
            throw OpenRouterError.invalidResponse
        }
        return Data(content[start...end].utf8)
    }
}

private struct OpenRouterResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}

private struct OpenRouterErrorResponse: Decodable {
    struct APIError: Decodable { let message: String }
    let error: APIError
}

enum OpenRouterError: LocalizedError {
    case invalidResponse
    case unauthorized
    case api(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "OpenRouter returned an invalid response"
        case .unauthorized: "OpenRouter authorization failed"
        case let .api(message): "OpenRouter: \(message)"
        }
    }
}
