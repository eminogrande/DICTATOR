import Foundation

/// Only a completed inference probe may enable capture. Generation tokens prevent a
/// slow response for an old selection (including A → B → A) from enabling a new one.
public struct TranscriptionReadiness: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case loading
        case ready
        case failed(String)
    }
    public private(set) var engineID: String
    public private(set) var generation = UUID()
    public private(set) var phase: Phase = .loading

    public init(engineID: String) { self.engineID = engineID }

    @discardableResult
    public mutating func begin(engineID: String) -> UUID {
        self.engineID = engineID
        generation = UUID()
        phase = .loading
        return generation
    }

    public mutating func complete(_ token: UUID, error: String? = nil) {
        guard token == generation, phase == .loading else { return }
        phase = error.map(Phase.failed) ?? .ready
    }

    public func permitsRecording(engineID: String, busy: Bool, recording: Bool) -> Bool {
        self.engineID == engineID && phase == .ready && !busy && !recording
    }

    public var isLoading: Bool { phase == .loading }
    public var error: String? {
        if case .failed(let error) = phase { return error }
        return nil
    }
    public func status(engineName: String) -> String {
        switch phase {
        case .loading: "Loading \(engineName)…"
        case .ready: "Ready — hold Fn to talk"
        case .failed: "\(engineName) unavailable — choose another quality or retry"
        }
    }
}
