import AppKit
import CoreGraphics
import DictateMacCore

@MainActor
final class FnKeyMonitor {
    static let rKeyCode: UInt16 = 15
    static let aKeyCode: UInt16 = 0

    private var globalFlags: Any?
    private var localFlags: Any?
    private var globalKeys: Any?
    private var localKeys: Any?
    private var eventTap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var state = FnHoldState()
    private let onAction: (PushToTalkAction) -> Void
    private let tapOwner = TapOwner()
    /// Tracks whether the 'a' key is physically held (for Fn+A compress mode).
    private var aDown = false
    /// True while the current Fn-hold session is a compress (Fn+A) session.
    private var compressSession = false
    private var globalKeyUp: Any?
    private var localKeyUp: Any?

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
        globalKeyUp = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            Task { @MainActor in self?.handleKeyUp(event) }
        }
        localKeyUp = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleKeyUp(event)
            return event
        }
        startTap()
    }

    func stop() {
        for monitor in [globalFlags, localFlags, globalKeys, localKeys, globalKeyUp, localKeyUp] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        globalFlags = nil
        localFlags = nil
        globalKeys = nil
        localKeys = nil
        globalKeyUp = nil
        localKeyUp = nil
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
        switch action {
        case .start:
            // Fn pressed while 'a' is already held → compress session.
            compressSession = aDown
            onAction(compressSession ? .compressStart : .start)
        case .stop:
            onAction(compressSession ? .compressStop : .stop)
            compressSession = false
        default:
            break
        }
    }

    private func handleKeyUp(_ event: NSEvent) {
        if event.keyCode == Self.aKeyCode {
            aDown = false
        }
    }

    @discardableResult
    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == Self.aKeyCode {
            aDown = true
            // Fn already down + A pressed → upgrade the running hold to compress mode.
            if state.isFunctionHeld {
                compressSession = true
                onAction(.compressStart) // no-op in controller if already recording
            }
        }
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
