import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow?
    let store = PresetStore.shared
    let hotkeys = HotkeyManager()
    let runner = ActionRunner()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenubar()
        rebuildHotkeys()
        store.onChange = { [weak self] in
            Task { @MainActor in self?.rebuildHotkeys() }
        }
        ensureAccessibilityPrompt()
    }

    func setStatusGlyph(_ extra: String? = nil) {
        guard let btn = statusItem?.button else { return }
        let glyph = "✦"
        let combined = (extra.map { " \($0)" } ?? "")
        btn.attributedTitle = NSAttributedString(
            string: glyph + combined,
            attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .baselineOffset: 0
            ]
        )
    }

    func ensureAccessibilityPrompt() {
        // Check only; do not auto-prompt at launch (would open System Settings on every
        // ad-hoc rebuild). Settings UI exposes a button to request access.
        _ = AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    func setupMenubar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = nil
            btn.toolTip = "caip — Copy · AI · Paste"
        }
        setStatusGlyph(nil)
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit caip", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let root = SettingsView().environmentObject(store)
            let host = NSHostingController(rootView: root)
            let win = NSWindow(contentViewController: host)
            win.setContentSize(NSSize(width: 540, height: 460))
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.title = "Copy · AI · Paste"
            win.titlebarAppearsTransparent = false
            win.center()
            win.isReleasedWhenClosed = false
            settingsWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    func rebuildHotkeys() {
        hotkeys.unregisterAll()
        for preset in store.presets {
            guard let key = preset.hotkey else { continue }
            hotkeys.register(id: preset.id, keyCode: key.keyCode, modifiers: key.carbonMods) { [weak self] in
                self?.runner.run(presetId: preset.id)
            }
        }
    }
}
