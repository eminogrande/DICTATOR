import Foundation

public enum SpokenLanguage {
    public static func locked(detected: String, probabilities: [String: Float] = [:]) -> String {
        let code = detected.lowercased()
        if code == "de" || code == "en" { return code }
        let german = probabilities["de"] ?? .leastNonzeroMagnitude
        let english = probabilities["en"] ?? .leastNonzeroMagnitude
        return german >= english ? "de" : "en"
    }
}
