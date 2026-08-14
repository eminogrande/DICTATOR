public enum StatusPopoverAction: Equatable, Sendable {
    case show
    case close

    public static func next(isShown: Bool) -> StatusPopoverAction {
        isShown ? .close : .show
    }
}
