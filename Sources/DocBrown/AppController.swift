import AppKit
import SwiftUI
import Carbon

/// Carbon hot keys do not require Accessibility or Input Monitoring access.
@MainActor final class AppController {
    private let model: AppModel
    private var libraryWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var searchPanel: SearchPanel?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var localKeys: Any?
    private var lastHotkeyInvocation = Date.distantPast

    init(model: AppModel) {
        self.model = model
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, pointer in
            guard let pointer else { return OSStatus(eventNotHandledErr) }
            Task { @MainActor in Unmanaged<AppController>.fromOpaque(pointer).takeUnretainedValue().toggleSearch() }
            return noErr
        }, 1, &event, pointer, &eventHandler)
        registerShortcut()
        // Directly delivered events (for example accessibility keyboard input) may bypass
        // WindowServer's global hot-key routing. Handle the same chord locally as well.
        localKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if let panel = self.searchPanel, panel.isVisible,
               event.window === panel || panel.isKeyWindow,
               panel.handleSearchKey(event) { return nil }
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
            let choice = self.model.hotkeyChoice
            let expected: NSEvent.ModifierFlags = choice == "command-d" ? [.command] : choice == "control-option-command-d" ? [.control,.option,.command] : choice == "control-shift-d" ? [.control,.shift] : [.control,.option]
            let code: UInt16 = choice == "control-option-space" ? 49 : 2
            if event.keyCode == code && flags == expected { self.toggleSearch(); return nil }
            return event
        }
    }

    func registerShortcut() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        let shortcut = model.hotkeyChoice
        let key: UInt32 = shortcut == "control-option-space" ? UInt32(kVK_Space) : UInt32(kVK_ANSI_D)
        let modifiers = shortcut == "command-d" ? UInt32(cmdKey) : shortcut == "control-option-command-d" ? UInt32(controlKey | optionKey | cmdKey) : shortcut == "control-shift-d" ? UInt32(controlKey | shiftKey) : UInt32(controlKey | optionKey)
        let identifier = EventHotKeyID(signature: OSType(0x4442524E), id: 1)
        let result = RegisterEventHotKey(key, modifiers, identifier, GetApplicationEventTarget(), 0, &hotKey)
        model.hotkeyError = result == noErr ? "" : "This shortcut is already in use. Choose a different shortcut."
    }

    func toggleSearch() {
        // Carbon and directly delivered key events can describe the same press.
        guard Date().timeIntervalSince(lastHotkeyInvocation) > 0.2 else { return }
        lastHotkeyInvocation = Date()
        if searchPanel?.isVisible == true { searchPanel?.orderOut(nil); return }
        showSearch()
    }
    func showSearch() {
        if searchPanel == nil {
            let panel = SearchPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540), styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.navigate = { [weak model] delta in model?.moveQuickSelection(delta) }
            panel.choose = { [weak model] in model?.openQuickSelection() }
            panel.title = "Search DocBrown"
            panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            panel.isFloatingPanel = true; panel.level = .floating
            panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            panel.isMovableByWindowBackground = true
            panel.contentView = NSHostingView(rootView: QuickSearchView().environmentObject(model))
            searchPanel = panel
        }
        model.quickQuery = ""; model.quickResults = []; model.quickSelection = 0
        model.quickFocusToken = UUID()
        model.searchQuickly()
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            searchPanel?.setFrameOrigin(NSPoint(x: visible.midX - 380, y: visible.midY - 190))
        }
        // A nonactivating panel takes keyboard focus without raising the library
        // or switching away from the application the user is working in.
        searchPanel?.makeKeyAndOrderFront(nil)
        searchPanel?.contentView?.layoutSubtreeIfNeeded()
        if let content = searchPanel?.contentView, let field = searchField(in: content) {
            searchPanel?.makeFirstResponder(field)
        }
    }
    private func searchField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.identifier?.rawValue == "quick-search" { return field }
        for child in view.subviews { if let field = searchField(in: child) { return field } }
        return nil
    }
    func hideSearch() { searchPanel?.orderOut(nil) }
    func openSetup() {
        hideSearch()
        if setupWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 650), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.center(); setupWindow = window
        }
        setupWindow?.title = "Capture Richer Git History"
        setupWindow?.contentView = NSHostingView(rootView: IntegrationSetupView().environmentObject(model))
        NSApp.activate(ignoringOtherApps: true); setupWindow?.makeKeyAndOrderFront(nil)
    }
    func openLibrary(sessionID: String? = nil) {
        hideSearch()
        if libraryWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1380, height: 880), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "DocBrown"
            window.minSize = NSSize(width: 1000, height: 640)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ContentView().environmentObject(model))
            window.center(); libraryWindow = window
        }
        if let sessionID { model.openConversation(sessionID) }
        NSApp.activate(ignoringOtherApps: true)
        libraryWindow?.makeKeyAndOrderFront(nil)
    }
}

final class SearchPanel: NSPanel {
    var navigate: ((Int) -> Void)?
    var choose: (() -> Void)?
    override func sendEvent(_ event: NSEvent) {
        if handleSearchKey(event) { return }
        super.sendEvent(event)
    }
    @discardableResult func handleSearchKey(_ event: NSEvent) -> Bool {
        if let editor = firstResponder as? NSTextView, editor.hasMarkedText() { return false }
        if event.type == .keyDown && event.modifierFlags.intersection([.command,.control,.option,.shift]).isEmpty {
            switch event.keyCode {
            case 125: navigate?(1); return true
            case 126: navigate?(-1); return true
            case 36, 76: choose?(); return true
            case 53: orderOut(nil); return true
            default: break
            }
        }
        return false
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
    override func resignKey() { super.resignKey(); orderOut(nil) }
}

@MainActor final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.start()
        AppUpdater.shared.start()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard AppModel.shared.importing else { return .terminateNow }
        Task { @MainActor in
            await AppModel.shared.finishImportBeforeQuitting()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Launch Services, login startup, and background app inspections can all
        // send reopen events. Only an explicit menu action or hotkey opens UI.
        return false
    }
}
