import AppKit
import ApplicationServices
import Carbon.HIToolbox

struct DictationPastePolicy {
    static func canPaste(target: pid_t?, current: pid_t?, sameField: Bool, trusted: Bool, fieldUnknown: Bool = false) -> Bool {
        blockReason(target: target, current: current, sameField: sameField, trusted: trusted, fieldUnknown: fieldUnknown) == nil
    }

    /// `fieldUnknown`: the app wouldn't say which field had focus, at the start or at the end. Electron apps
    /// (Claude, Slack, VS Code) answer no value by default; with the same app in front all along, the paste
    /// goes where you are typing, as it would in any dictation app.
    static func blockReason(target: pid_t?, current: pid_t?, sameField: Bool, trusted: Bool, fieldUnknown: Bool = false) -> String? {
        guard trusted else { return "accessibility_denied" }
        guard let target else { return "no_destination_app" }
        guard current == target else { return "application_changed" }
        guard sameField || fieldUnknown else { return "focused_field_changed" }
        return nil
    }
}

/// A recording's destination is captured before any app UI can take focus.
@MainActor final class DictationPaste {
    private let pid: pid_t?
    private let field: AXUIElement?
    private(set) var diagnostics: [String: Any]

    init(requestManualAccessibility: Bool = false) {
        let app = NSWorkspace.shared.frontmostApplication
        pid = app?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : app?.processIdentifier
        var manualStatus = -1
        if requestManualAccessibility, let pid, AXIsProcessTrusted() {
            manualStatus = Int(AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid),
                "AXManualAccessibility" as CFString, kCFBooleanTrue).rawValue)
        }
        var status = -1
        field = Self.focusedField(pid, status: &status)
        diagnostics = ["targetApp": app?.bundleIdentifier ?? "", "targetPID": Int(pid ?? -1),
                       "targetFieldCaptured": field != nil, "targetRole": Self.role(field),
                       "targetQueryStatus": status, "manualAccessibilityStatus": manualStatus,
                       "reason": "captured"]
    }

    private static func focusedField(_ pid: pid_t?, status: inout Int) -> AXUIElement? {
        guard let pid, AXIsProcessTrusted() else { return nil }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString, &value)
        status = Int(result.rawValue)
        guard result == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func role(_ field: AXUIElement?) -> String {
        guard let field else { return "" }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(field, kAXRoleAttribute as CFString, &value) == .success else { return "" }
        return value as? String ?? ""
    }

    func deliver(_ text: String) -> Bool {
        let board = NSPasteboard.general
        Self.copy(text, to: board)
        let currentApp = NSWorkspace.shared.frontmostApplication
        let current = currentApp?.processIdentifier
        var status = -1
        let focused = Self.focusedField(current, status: &status)
        let sameField = field != nil && focused != nil && CFEqual(field!, focused!)
        let fieldUnknown = field == nil && focused == nil
        let reason = DictationPastePolicy.blockReason(target: pid, current: current, sameField: sameField, trusted: AXIsProcessTrusted(),
                                                      fieldUnknown: fieldUnknown)
        diagnostics.merge(["currentApp": currentApp?.bundleIdentifier ?? "", "currentPID": Int(current ?? -1),
                           "currentFieldCaptured": focused != nil, "currentRole": Self.role(focused),
                           "currentQueryStatus": status, "sameField": sameField, "fieldUnknown": fieldUnknown,
                           "reason": reason ?? "ready"]) { _, new in new }
        guard reason == nil else { return false }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            diagnostics["reason"] = "keyboard_events_unavailable"
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        diagnostics["reason"] = "paste_posted"
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
