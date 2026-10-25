import AppKit
import ApplicationServices
import Carbon
import WisprCore

@MainActor final class GlobalHotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?
    func register() -> Bool {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, pointer in
            guard let pointer else { return noErr }
            let hotkey = Unmanaged<GlobalHotKey>.fromOpaque(pointer).takeUnretainedValue()
            Task { @MainActor in hotkey.action?() }
            return noErr
        }, 1, &event, pointer, &handler)
        guard installed == noErr else { return false }
        let id = EventHotKeyID(signature: 0x5753504D, id: 1)
        return RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id,
                                  GetApplicationEventTarget(), 0, &reference) == noErr
    }
    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        reference = nil; handler = nil
    }
}

@MainActor final class TextInserter {
    struct Target {
        let application: NSRunningApplication
        let element: AXUIElement?
        var name: String { application.localizedName ?? "your app" }
    }
    func target() -> Target? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return Target(application: application, element: focusedElement(pid: application.processIdentifier))
    }
    private func focusedElement(pid: pid_t) -> AXUIElement? {
        var value: CFTypeRef?
        let app = AXUIElementCreateApplication(pid)
        guard AXUIElementSetMessagingTimeout(app, 0.3) == .success else { return nil }
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    var permitted: Bool { AXIsProcessTrusted() }
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func insert(_ text: String, into target: Target) -> String {
        guard permitted else { return "Text is ready. Enable Accessibility to insert it into other apps." }
        guard !target.application.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == target.application.processIdentifier else {
            return "Focus changed. Your text remains in wisprM; nothing was sent."
        }
        let focused = focusedElement(pid: target.application.processIdentifier)
        guard let original = target.element else { return "The original field was unavailable. Your text remains in wisprM." }
        if let focused, !CFEqual(original, focused) {
            return "The focused field changed. Your text remains in wisprM."
        }
        guard let focused else { return "No editable field was found. Your text remains in wisprM." }
        guard AXUIElementSetMessagingTimeout(focused, 0.3) == .success else {
            return "The field could not be checked within a bounded request. Use Command–V."
        }
        var roleValue: CFTypeRef?, subroleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &roleValue) == .success,
              AXUIElementCopyAttributeValue(focused, kAXSubroleAttribute as CFString, &subroleValue) == .success,
              InsertionEligibility.allows(role: roleValue as? String, subrole: subroleValue as? String) else {
            return "The field could not be verified as editable and unprotected. Use Command–V to paste."
        }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(focused, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return "This editor requires manual Paste. Use Command–V." }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.application.processIdentifier,
              let current = focusedElement(pid: target.application.processIdentifier), CFEqual(current, original) else {
            return "Focus changed. Use Command–V in the intended field."
        }
        guard AXUIElementSetMessagingTimeout(original, 0.3) == .success else {
            return "Direct insertion could not be bounded safely. Use Command–V."
        }
        if AXUIElementSetAttributeValue(original, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success {
            return "Inserted into \(target.name)"
        }
        return "The editor rejected direct insertion. Use Command–V to paste."
    }
}
