import AppKit
import ApplicationServices
import Carbon

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
            return "Focus changed. Your text is ready to copy; nothing was sent."
        }
        let focused = focusedElement(pid: target.application.processIdentifier)
        guard let original = target.element else { return "The original field was unavailable. Your text is ready to copy." }
        if let focused, !CFEqual(original, focused) {
            return "The focused field changed. Your text is ready to copy."
        }
        guard let focused else { return "No editable field was found. Your text is ready to copy." }
        var roleValue: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String ?? ""
        var subrole: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(focused, kAXSubroleAttribute as CFString, &subrole)
        guard role != "AXSecureTextField", subrole as? String != "AXSecureTextField" else { return "Secure fields are excluded. Your text is ready to copy." }
        if AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success {
            return "Inserted into \(target.name)"
        }
        // Apps with custom editors often accept keyboard paste but not AXSelectedText.
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else { return nil }; return (type, data)
            }
        }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { return "Could not send Paste. Your text is ready to copy." }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let change = pasteboard.changeCount
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard pasteboard.changeCount == change else { return }
            pasteboard.clearContents()
            let items = saved.map { representations in
                let item = NSPasteboardItem()
                for (type, data) in representations { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { pasteboard.writeObjects(items) }
        }
        return "Sent Paste to \(target.name)"
    }
}
