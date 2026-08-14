import Foundation

public enum AudioSampleMixer {
    public static func mix(
        microphone: [Float],
        system: [Float],
        systemOffset: Int
    ) -> [Float] {
        guard !system.isEmpty else { return microphone }
        let offset = max(0, systemOffset)
        var result = Array(repeating: Float.zero, count: max(microphone.count, offset + system.count))
        for index in microphone.indices {
            result[index] = microphone[index]
        }
        for index in system.indices {
            let destination = offset + index
            result[destination] = max(-1, min(1, result[destination] + system[index]))
        }
        return result
    }
}
