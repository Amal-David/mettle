#if os(macOS)
import AppKit
import SwiftUI
import Combine

public final class PreviewApplication: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    public var window: NSWindow?
    public let session: PreviewSession
    private let initialURL: URL?
    private let initialExampleID: String?
    private let initialTime: Double
    private let initialScene: Int
    private var keyboardMonitor: Any?
    private var appearanceObserver: AnyCancellable?
    public init(examples: [PreviewExample], initialURL: URL? = nil, initialExampleID: String? = nil,
                initialTime: Double = 0, initialScene: Int = 0) {
        session = PreviewSession(examples: examples)
        self.initialURL = initialURL; self.initialExampleID = initialExampleID
        self.initialTime = initialTime; self.initialScene = initialScene
        super.init()
    }
    public func applicationDidFinishLaunching(_ notification: Notification) {
        installMenus()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1160, height: 820),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Mettle Preview"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .aqua)
        window.minSize = NSSize(width: 900, height: 610)
        window.contentView = NSHostingView(rootView: PreviewRootView(session: session))
        window.center(); window.makeKeyAndOrderFront(nil); self.window = window
        appearanceObserver = session.$appearance.sink { [weak window] value in
            window?.appearance = value == "System" ? nil : NSAppearance(named: value == "Light" ? .aqua : .darkAqua)
        }
        NSApp.activate(ignoringOtherApps: true)
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, NSApp.keyWindow === self.window, self.window?.attachedSheet == nil,
                  !self.session.helpVisible, !self.session.referencesVisible, !(self.window?.firstResponder is NSTextView),
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return event }
            switch event.keyCode {
            case 49: self.session.togglePlayback(); return nil // Space
            case 123: self.session.step(-1.0/30.0); return nil
            case 124: self.session.step(1.0/30.0); return nil
            default: return event
            }
        }
        if let url = initialURL {
            session.open(url, sceneIndex: initialScene, exampleID: initialExampleID, initialTime: initialTime)
        }
        print("METTLE_WINDOW_ID=\(window.windowNumber)"); fflush(stdout)
    }
    public func applicationWillTerminate(_ notification: Notification) {
        session.pause()
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
    }
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    public func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let filename = filenames.first { session.open(URL(fileURLWithPath: filename)) }
        sender.reply(toOpenOrPrint: .success)
    }
    private func installMenus() {
        let bar = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title); item.submenu = submenu; bar.addItem(item); return submenu
        }
        func add(_ m: NSMenu, _ title: String, _ action: Selector, _ key: String = "",
                 modifiers: NSEvent.ModifierFlags = .command) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self; item.keyEquivalentModifierMask = modifiers; m.addItem(item)
        }
        let app = menu("Mettle")
        add(app, "About Mettle Preview", #selector(about))
        app.addItem(.separator()); add(app, "Hide Mettle", #selector(hide), "h")
        app.addItem(.separator()); add(app, "Quit Mettle", #selector(quit), "q")
        let file = menu("File")
        add(file, "Open Animation…", #selector(openFile), "o")
        add(file, "Reload Export", #selector(reloadFile), "r", modifiers: [.command, .shift])
        add(file, "Export Current Frame…", #selector(exportFrame), "e", modifiers: [.command, .shift])
        file.addItem(.separator()); add(file, "Close Animation", #selector(closeDocument), "w", modifiers: [.command, .shift])
        add(file, "Close Window", #selector(closeWindow), "w")
        let playback = menu("Playback")
        add(playback, "Play / Pause", #selector(togglePlay), " ", modifiers: [])
        add(playback, "Restart", #selector(restart), "r")
        let view = menu("View")
        add(view, "Fit Canvas", #selector(fit), "0")
        add(view, "Show / Hide File Details", #selector(details), "i")
        add(view, "Motion References", #selector(showReferences))
        let samples = menu("Developer")
        for (index, example) in session.examples.enumerated() {
            let item = NSMenuItem(title: example.title + " (test fixture)", action: #selector(openFixture(_:)), keyEquivalent: "")
            item.target = self; item.tag = index; samples.addItem(item)
        }
        let help = menu("Help")
        add(help, "Exporting from Figma", #selector(showGuide))
        NSApp.mainMenu = bar
    }
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if [#selector(exportFrame), #selector(reloadFile), #selector(closeDocument), #selector(details), #selector(fit)].contains(menuItem.action) {
            return session.renderer != nil && !session.isLoading
        }
        if [#selector(togglePlay), #selector(restart)].contains(menuItem.action) {
            return session.hasMotion && !session.isLoading && !session.reduceMotion
        }
        return true
    }
    @objc private func openFile() { session.openPanel() }
    @objc private func reloadFile() { session.reload() }
    @objc private func exportFrame() { session.exportPanel() }
    @objc private func closeDocument() { session.close() }
    @objc private func closeWindow() { window?.performClose(nil) }
    @objc private func togglePlay() { session.togglePlayback() }
    @objc private func restart() { session.seek(0) }
    @objc private func fit() { session.zoom = "Fit" }
    @objc private func details() { session.inspectorVisible.toggle() }
    @objc private func showReferences() { session.pause(); session.referencesVisible = true }
    @objc private func openFixture(_ sender: NSMenuItem) {
        guard session.examples.indices.contains(sender.tag) else { return }
        session.openExample(session.examples[sender.tag])
    }
    @objc private func showGuide() { session.helpVisible = true }
    @objc private func hide() { NSApp.hide(nil) }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func about() {
        let alert = NSAlert(); alert.messageText = "Mettle Preview"
        alert.informativeText = "Experimental v0.3\n\nA small macOS utility for previewing Mettle exports.\nThe Swift + Metal library is independent of this app.\n\nOpen an export, inspect the motion, or save a frame."
        if let window { alert.beginSheetModal(for: window) }
    }
}
#endif
