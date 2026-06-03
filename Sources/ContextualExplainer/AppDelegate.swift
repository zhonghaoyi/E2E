import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private var statusItem: NSStatusItem?
    private var panelController: PanelWindowController?
    private var settingsController: SettingsWindowController?
    private var serviceProvider: TextServiceProvider?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var clipboardTimer: Timer?
    private var lastPasteboardChangeCount = NSPasteboard.general.changeCount
    private var lastClipboardText: String?
    private var lastClipboardCopyAt: Date?
    private var lastCommandCAt: Date?
    private var lastCommandClipboardText: String?
    private var lastCommandClipboardAt: Date?
    private var lastDoubleCopyTriggeredAt: Date?
    private let doubleCommandCInterval: TimeInterval = 1.2

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        settingsController = SettingsWindowController(appState: appState)
        panelController = PanelWindowController(appState: appState) { [weak self] in
            self?.settingsController?.show()
        }
        configureMainMenu()
        configureStatusItem()
        configureServices()
        configureKeyboardMonitor()
        configureClipboardMonitor()
        appState.refreshAccessibilityPermission()
        showInitialWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        clipboardTimer?.invalidate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        appState.refreshAccessibilityPermission()
        if !flag {
            showInitialWindow()
        } else {
            panelController?.show()
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        appState.refreshAccessibilityPermission()
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(menuItem("Settings", action: #selector(showSettings), key: ",", modifiers: [.command]))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(menuItem("Quit Contextual Explainer", action: #selector(quit), key: "q", modifiers: [.command]))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "text.magnifyingglass", accessibilityDescription: "Contextual Explainer")
            button.imagePosition = .imageLeading
            button.title = "Explain"
        }

        let menu = NSMenu()
        menu.addItem(menuItem("Capture Selected Context", action: #selector(explainSelectedText), key: "e", modifiers: [.command, .shift]))
        menu.addItem(menuItem("Capture Clipboard Context", action: #selector(explainClipboard), key: "v", modifiers: [.command, .shift]))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem("Show Window", action: #selector(showWindow), key: "0", modifiers: [.command]))
        menu.addItem(menuItem("Settings", action: #selector(showSettings), key: ",", modifiers: [.command]))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem("Quit", action: #selector(quit), key: "q", modifiers: [.command]))

        item.menu = menu
        statusItem = item
    }

    private func menuItem(_ title: String, action: Selector, key: String, modifiers: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private func configureServices() {
        guard let panelController else { return }
        let provider = TextServiceProvider(appState: appState, panelController: panelController)
        serviceProvider = provider
        NSApp.servicesProvider = provider
        NSUpdateDynamicServices()
    }

    private func configureKeyboardMonitor() {
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event)
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if Task.isCancelled {
                return event
            }
            Task { @MainActor in
                self?.lastCommandCAt = nil
            }
            return event
        }
    }

    private func configureClipboardMonitor() {
        clipboardTimer?.invalidate()
        lastPasteboardChangeCount = NSPasteboard.general.changeCount
        clipboardTimer = Timer(timeInterval: 0.18, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handlePasteboardTick()
            }
        }
        if let clipboardTimer {
            RunLoop.main.add(clipboardTimer, forMode: .common)
        }
    }

    private func showInitialWindow() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            if appState.hasAPIKey {
                panelController?.show()
            } else {
                settingsController?.show()
            }
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !event.isARepeat else { return }

        if appState.settings.shortcutMode == .doubleCommandC,
           !flags.contains(.shift),
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            handleCommandCPress()
            return
        }

        guard appState.settings.shortcutMode == .commandShiftE, flags.contains(.shift) else { return }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "e":
            explainSelectedText()
        default:
            break
        }
    }

    private func handleCommandCPress() {
        let now = Date()

        if let lastCommandCAt, now.timeIntervalSince(lastCommandCAt) <= doubleCommandCInterval {
            self.lastCommandCAt = nil
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 140_000_000)
                recordCommandCCopy()
            }
            return
        }

        lastCommandCAt = now
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 140_000_000)
            recordCommandCCopy()
        }
    }

    private func recordCommandCCopy() {
        guard !NSApp.isActive else { return }
        guard
            let copiedText = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !copiedText.isEmpty
        else {
            return
        }

        let now = Date()
        if
            let lastCommandClipboardText,
            let lastCommandClipboardAt,
            lastCommandClipboardText == copiedText,
            now.timeIntervalSince(lastCommandClipboardAt) <= doubleCommandCInterval
        {
            triggerDoubleCopy(selection: copiedText)
            return
        }

        lastCommandClipboardText = copiedText
        lastCommandClipboardAt = now
    }

    private func handlePasteboardTick() {
        guard appState.settings.shortcutMode == .doubleCommandC else {
            resetClipboardShortcutState()
            lastPasteboardChangeCount = NSPasteboard.general.changeCount
            return
        }

        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = changeCount

        guard !NSApp.isActive else {
            resetClipboardShortcutState()
            return
        }

        guard
            let copiedText = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !copiedText.isEmpty
        else {
            resetClipboardShortcutState()
            return
        }

        let now = Date()
        if
            let lastClipboardText,
            let lastClipboardCopyAt,
            lastClipboardText == copiedText,
            now.timeIntervalSince(lastClipboardCopyAt) <= doubleCommandCInterval
        {
            triggerDoubleCopy(selection: copiedText)
            return
        }

        lastClipboardText = copiedText
        lastClipboardCopyAt = now
        appState.statusMessage = "Copied once. Press Command-C again to capture context."
        appState.errorMessage = nil
    }

    private func resetClipboardShortcutState() {
        lastClipboardText = nil
        lastClipboardCopyAt = nil
        lastCommandClipboardText = nil
        lastCommandClipboardAt = nil
    }

    @objc private func explainSelectedText() {
        panelController?.show()
        appState.explainSystemSelection()
    }

    @objc private func explainClipboard() {
        panelController?.show()
        appState.explainClipboard()
    }

    private func triggerDoubleCopy(selection: String) {
        let now = Date()
        if let lastDoubleCopyTriggeredAt, now.timeIntervalSince(lastDoubleCopyTriggeredAt) < 0.8 {
            return
        }

        lastDoubleCopyTriggeredAt = now
        resetClipboardShortcutState()
        explainClipboardAfterCopy(selection: selection)
    }

    private func explainClipboardAfterCopy(selection copiedSelection: String) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            panelController?.show()
            appState.captureContext(copiedSelection)
        }
    }

    @objc private func showWindow() {
        panelController?.show()
    }

    @objc private func showSettings() {
        settingsController?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

@MainActor
final class PanelWindowController: NSWindowController {
    private var cancellable: AnyCancellable?

    init(appState: AppState, openSettings: @escaping () -> Void) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Contextual Explainer"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentViewController = NSHostingController(rootView: ExplainerPanelView(appState: appState, openSettings: openSettings))
        super.init(window: panel)
        applyPinned(appState.settings.isPanelPinned)
        cancellable = appState.$settings.sink { [weak self] settings in
            Task { @MainActor in
                self?.applyPinned(settings.isPanelPinned)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyPinned(_ isPinned: Bool) {
        window?.level = isPinned ? .statusBar : .normal
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    init(appState: AppState) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentViewController = NSHostingController(rootView: SettingsView(appState: appState))
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
        window.center()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
@objc final class TextServiceProvider: NSObject {
    private let appState: AppState
    private let panelController: PanelWindowController

    init(appState: AppState, panelController: PanelWindowController) {
        self.appState = appState
        self.panelController = panelController
    }

    @objc(explainSelection:userData:error:)
    func explainSelection(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            error?.pointee = "No selected text was provided." as NSString
            return
        }

        panelController.show()
        appState.captureContext(text)
    }
}
