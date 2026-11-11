import AppKit
import ApplicationServices
import Carbon.HIToolbox

struct DictationPastePolicy {
    static func canPaste(target: pid_t?, current: pid_t?, sameField: Bool, trusted: Bool) -> Bool {
        guard let target, let current else { return false }
        return target == current && sameField && trusted
    }
}

/// A recording's destination is captured before any app UI can take focus.
@MainActor final class DictationPaste {
    private let pid: pid_t?
    private let field: AXUIElement?

    init() {
        let app = NSWorkspace.shared.frontmostApplication
        pid = app?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : app?.processIdentifier
        field = Self.focusedField(pid)
    }

    private static func focusedField(_ pid: pid_t?) -> AXUIElement? {
        guard let pid, AXIsProcessTrusted() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func deliver(_ text: String) -> Bool {
        let board = NSPasteboard.general
        Self.copy(text, to: board)
        let current = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let focused = Self.focusedField(current)
        let sameField = field != nil && focused != nil && CFEqual(field!, focused!)
        guard DictationPastePolicy.canPaste(target: pid, current: current, sameField: sameField, trusted: AXIsProcessTrusted()),
              let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    // Keep the dictated text available for a slow target's queued Cmd+V.
    // Posting a key event cannot confirm that the target consumed the clipboard.
    static func copy(_ text: String, to board: NSPasteboard = .general) {
        board.clearContents()
        board.setString(text, forType: .string)
    }

    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
