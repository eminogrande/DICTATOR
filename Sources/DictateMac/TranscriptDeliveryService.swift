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
        to targetApplication: NSRunningApplication?,
        mode: TranscriptDeliveryMode
    ) async -> TranscriptDelivery {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcript, forType: .string)

        guard mode == .automaticInsert else {
            return .clipboardOnly
        }
        guard isAccessibilityGranted else {
            return .accessibilityDenied
        }
        guard let targetApplication, !targetApplication.isTerminated else {
            return .targetUnavailable
        }

        if await postPasteShortcut(to: targetApplication) {
            return .pasteShortcutPosted
        }

        let insertionError = insertAtFocusedCursor(
            transcript,
            processIdentifier: targetApplication.processIdentifier
        )
        return TranscriptInsertionDecision.afterAccessibilityResult(insertionError.rawValue) == .inserted
            ? .accessibilityInserted
            : .targetUnavailable
    }

    private static func postPasteShortcut(to targetApplication: NSRunningApplication) async -> Bool {
        guard targetApplication.activate() else {
            return false
        }
        guard await waitUntilFrontmost(targetApplication.processIdentifier) else {
            return false
        }
        try? await Task.sleep(for: .milliseconds(120))

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
            return false
        }

        commandDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        commandUp.flags = []
        for event in [commandDown, vDown, vUp, commandUp] {
            event.post(tap: .cghidEventTap)
        }
        return true
    }

    private static func insertAtFocusedCursor(
        _ transcript: String,
        processIdentifier: pid_t
    ) -> AXError {
        let application = AXUIElementCreateApplication(processIdentifier)
        var focusedValue: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusedError == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return focusedError == .success ? .failure : focusedError
        }

        let focusedElement = unsafeBitCast(focusedValue, to: AXUIElement.self)
        return AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            transcript as CFTypeRef
        )
    }

    private static func waitUntilFrontmost(_ processIdentifier: pid_t) async -> Bool {
        for _ in 0..<20 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier {
                return true
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return false
    }
}
