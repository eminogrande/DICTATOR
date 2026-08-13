import AppKit
import ApplicationServices
import DictateMacCore

@MainActor
final class TargetApplicationTracker {
    private let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
    private var lastTarget: NSRunningApplication?
    private var observer: NSObjectProtocol?

    init() {
        remember(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else {
                return
            }
            Task { @MainActor [weak self] in
                self?.remember(application)
            }
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func targetApplication() -> NSRunningApplication? {
        remember(NSWorkspace.shared.frontmostApplication)
        return lastTarget?.isTerminated == false ? lastTarget : nil
    }

    private func remember(_ application: NSRunningApplication?) {
        guard let application,
              application.processIdentifier != ownProcessIdentifier,
              application.activationPolicy != .prohibited else {
            return
        }
        lastTarget = application
    }
}

@MainActor
enum TranscriptDeliveryService {
    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    static func deliver(
        _ transcript: String,
        to targetApplication: NSRunningApplication?
    ) async -> TranscriptDelivery {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcript, forType: .string)

        guard isAccessibilityGranted,
              let targetApplication,
              !targetApplication.isTerminated,
              targetApplication.activate() else {
            return .copied
        }

        try? await Task.sleep(for: .milliseconds(250))

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false) else {
            return .copied
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return .pasted
    }
}
