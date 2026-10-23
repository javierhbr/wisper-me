import AppKit
import SwiftUI
import Combine

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var window: NSWindow!
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private let hotkey = GlobalHotKey()
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        let root = RootView(model: model)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "wisprM"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 940, height: 700)
        window.contentView = NSHostingView(rootView: root)
        window.center()
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 354, height: 100),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        model.showHUD = { [weak self] in self?.showHUD() }
        model.hideHUD = { [weak self] in self?.panel.orderOut(nil) }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatus()
        let menu = NSMenu()
        menu.addItem(withTitle: "Open wisprM", action: #selector(openWindow), keyEquivalent: "")
        menu.addItem(withTitle: "Start / finish dictation", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Models…", action: #selector(openModels), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit wisprM", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        hotkey.action = { [weak self] in self?.model.toggleDictation() }
        model.hotkeyAvailable = hotkey.register()
        model.$phase.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatus() }
        }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        installMainMenu()
        openWindow()
        model.resumeModelIfPreviouslyLoaded()
    }
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "Quit wisprM", action: #selector(quit), keyEquivalent: "q").target = self
        let fileItem = NSMenuItem(); main.addItem(fileItem)
        let file = NSMenu(title: "File"); fileItem.submenu = file
        file.addItem(withTitle: "Transcribe audio…", action: #selector(importAudio), keyEquivalent: "o").target = self
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        NSApp.mainMenu = main
    }
    @objc private func importAudio() { model.importAudio() }
    private func updateStatus() {
        guard statusItem != nil else { return }
        statusItem.button?.image = NSImage(systemSymbolName: model?.recording == true ? "record.circle.fill" : "waveform", accessibilityDescription: "wisprM")
        statusItem.button?.contentTintColor = model?.recording == true ? .systemRed : nil
    }
    private func showHUD() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 35))
        panel.orderFrontRegardless()
    }
    @objc private func openWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); model.refreshPermissions() }
    @objc private func openModels() { model.page = .models; openWindow() }
    @objc private func openSettings() { model.page = .settings; openWindow() }
    @objc private func toggle() { model.toggleDictation() }
    @objc private func refresh() { model.refreshPermissions() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openWindow(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    private var terminationTask: Task<Void, Never>?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard terminationTask == nil else { return .terminateLater }
        terminationTask = Task {
            let cleaned = await model.shutdown()
            if !cleaned { openWindow() }
            sender.reply(toApplicationShouldTerminate: cleaned)
            terminationTask = nil
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        hotkey.unregister()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
