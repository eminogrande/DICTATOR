public enum PushToTalkAction: Equatable, Sendable {
    case none
    case start
    case stop
    case toggle
    /// Fn+A: push-to-talk whose result is compressed to a minimal numbered list.
    case compressStart
    case compressStop
}

public struct FnHoldState: Sendable {
    public static let functionKeyCode: UInt16 = 63

    private var isPressed = false

    public init() {}

    public mutating func handle(keyCode: UInt16, functionFlag: Bool) -> PushToTalkAction {
        guard keyCode == Self.functionKeyCode else {
            return .none
        }
        guard functionFlag != isPressed else {
            return .none
        }
        isPressed = functionFlag
        return functionFlag ? .start : .stop
    }

    public var isFunctionHeld: Bool { isPressed }
}
