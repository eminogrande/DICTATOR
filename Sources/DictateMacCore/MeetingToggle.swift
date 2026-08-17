public enum MeetingToggle {
    public enum Result: Equatable, Sendable {
        case start
        case latch
        case stop
    }

    public static func result(isRecording: Bool, startedByHold: Bool) -> Result {
        if !isRecording { return .start }
        if startedByHold { return .latch }
        return .stop
    }
}
