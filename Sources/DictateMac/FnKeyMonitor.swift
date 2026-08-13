import AppKit
import DictateMacCore

@MainActor
final class FnKeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var state = FnHoldState()
    private let onAction: (PushToTalkAction) -> Void

    init(onAction: @escaping (PushToTalkAction) -> Void) {
        self.onAction = onAction
    }

    func start() {
        guard globalMonitor == nil, localMonitor == nil else {
            return
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        let action = state.handle(
            keyCode: event.keyCode,
            functionFlag: event.modifierFlags.contains(.function)
        )
        guard action != .none else {
            return
        }
        onAction(action)
    }
}
