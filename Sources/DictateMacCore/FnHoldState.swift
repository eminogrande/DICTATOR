public enum PushToTalkAction: Equatable, Sendable {
    case none
    case start
    case stop
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
}
