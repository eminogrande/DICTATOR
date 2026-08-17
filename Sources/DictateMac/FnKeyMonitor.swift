import AppKit
import CoreGraphics
import DictateMacCore

@MainActor
final class FnKeyMonitor {
    static let rKeyCode: UInt16 = 15

    private var globalFlags: Any?
    private var localFlags: Any?
    private var globalKeys: Any?
    private var localKeys: Any?
    private var eventTap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var state = FnHoldState()
    private let onAction: (PushToTalkAction) -> Void
    private let tapOwner = TapOwner()

    init(onAction: @escaping (PushToTalkAction) -> Void) {
        self.onAction = onAction
        tapOwner.handler = { [weak self] in
            Task { @MainActor in self?.onAction(.toggle) }
        }
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
            Task { @MainActor in _ = self?.handleKey(event) }
        }
        localKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) == true ? nil : event
        }
        startTap()
    }

    func stop() {
        for monitor in [globalFlags, localFlags, globalKeys, localKeys] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        globalFlags = nil
        localFlags = nil
        globalKeys = nil
        localKeys = nil
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        tapSource = nil
        eventTap = nil
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

    private func startTap() {
        let owner = Unmanaged.passUnretained(tapOwner).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, userInfo in
                guard type == .keyDown, let userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let key = event.getIntegerValueField(.keyboardEventKeycode)
                if key == 15, event.flags.contains(.maskSecondaryFn) {
                    Unmanaged<TapOwner>.fromOpaque(userInfo).takeUnretainedValue().handler()
                    return nil
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: owner
        ) else { return }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

private final class TapOwner {
    var handler: () -> Void = {}
}
