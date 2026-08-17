import AppKit
import DictateMacCore

@MainActor
final class FnKeyMonitor {
    static let rKeyCode: UInt16 = 15

    private var globalFlags: Any?
    private var localFlags: Any?
    private var globalKeys: Any?
    private var localKeys: Any?
    private var state = FnHoldState()
    private let onAction: (PushToTalkAction) -> Void

    init(onAction: @escaping (PushToTalkAction) -> Void) {
        self.onAction = onAction
    }

    func start() {
        guard globalFlags == nil else { return }
        globalFlags = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlags(event) }
        }
        localFlags = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
            return event
        }
        globalKeys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in self?.handleKey(event) }
        }
        localKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) == true ? nil : event
        }
    }

    func stop() {
        for monitor in [globalFlags, localFlags, globalKeys, localKeys] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        globalFlags = nil
        localFlags = nil
        globalKeys = nil
        localKeys = nil
    }

    private func handleFlags(_ event: NSEvent) {
        let action = state.handle(
            keyCode: event.keyCode,
            functionFlag: event.modifierFlags.contains(.function)
        )
        if action != .none { onAction(action) }
    }

    @discardableResult
    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.keyCode == Self.rKeyCode, event.modifierFlags.contains(.function) else {
            return false
        }
        onAction(.toggle)
        return true
    }
}
