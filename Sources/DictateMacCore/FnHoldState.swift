import Foundation

public enum PushToTalkAction: Equatable, Sendable {
    case none
    case start
    case stop
    case toggle
    /// Second Fn tap within the double-tap window: keep recording, latched hands-free.
    case latch
    /// Fn+A: push-to-talk whose result is compressed to a minimal numbered list.
    case compressStart
    case compressStop
}

/// Fn gesture state machine.
///
/// - Hold Fn (longer than `maxTapDuration`) → `.start`, release → `.stop`.
/// - Tap Fn (shorter than `maxTapDuration`) → `.start`, release is deferred by
///   `doubleTapGap`. A second press in that window yields `.latch` (native macOS
///   double-tap dictation: recording stays on). Without a second press the
///   deferred stop fires, so a quick single tap still records a short take.
/// - While latched, the next press yields `.stop`.
public struct FnHoldState: Sendable {
    public static let functionKeyCode: UInt16 = 63
    /// Longest press still treated as a tap.
    public static let maxTapDuration: TimeInterval = 0.30
    /// Window after a released tap in which a second tap latches.
    public static let doubleTapGap: TimeInterval = 0.35

    private var isPressed = false
    private var pressStartedAt: TimeInterval = 0
    private var lastReleaseAt: TimeInterval?
    private var latched = false
    private var awaitingSecondTap = false
    private var ignoreRelease = false

    public init() {}

    public mutating func handle(
        keyCode: UInt16,
        functionFlag: Bool,
        at time: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> PushToTalkAction {
        guard keyCode == Self.functionKeyCode else {
            return .none
        }
        guard functionFlag != isPressed else {
            return .none
        }
        guard functionFlag else {
            return release(at: time)
        }
        isPressed = true
        pressStartedAt = time
        if awaitingSecondTap, let lastReleaseAt, time - lastReleaseAt <= Self.doubleTapGap {
            awaitingSecondTap = false
            latched = true
            ignoreRelease = true
            return .latch
        }
        if latched {
            latched = false
            ignoreRelease = true
            return .stop
        }
        return .start
    }

    /// Call when a deferred tap window expires; stops a tap that never doubled.
    public mutating func handleDoubleTapTimeout(at time: TimeInterval) -> PushToTalkAction {
        guard awaitingSecondTap, !isPressed else { return .none }
        guard let lastReleaseAt, time - lastReleaseAt >= Self.doubleTapGap else { return .none }
        awaitingSecondTap = false
        return .stop
    }

    public var isFunctionHeld: Bool { isPressed }

    public var isLatched: Bool { latched }

    /// Seconds until the pending tap window expires, or nil when none is open.
    public var secondsUntilDoubleTapTimeout: TimeInterval? {
        guard awaitingSecondTap, !isPressed, let lastReleaseAt else { return nil }
        return max(0, Self.doubleTapGap - (ProcessInfo.processInfo.systemUptime - lastReleaseAt))
    }

    private mutating func release(at time: TimeInterval) -> PushToTalkAction {
        isPressed = false
        lastReleaseAt = time
        if ignoreRelease {
            ignoreRelease = false
            return .none
        }
        if latched { return .stop }
        if time - pressStartedAt < Self.maxTapDuration {
            awaitingSecondTap = true
            return .none
        }
        return .stop
    }
}
