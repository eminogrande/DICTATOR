import Foundation

public enum SpokenLanguage {
    public static func locked(detected: String, probabilities: [String: Float] = [:]) -> String? {
        let code = detected.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return code.isEmpty ? nil : code
    }
}

