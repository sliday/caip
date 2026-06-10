import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow?
    let store = PresetStore.shared
    let hotkeys = HotkeyManager()
    let runner = ActionRunner()

    private var pulseTimer: Timer?
    private var pulseFrame = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenubar()
        rebuildHotkeys()
        store.onChange = { [weak self] in
            Task { @MainActor in self?.rebuildHotkeys() }
        }
        ensureAccessibilityPrompt()
        UpdateChecker.scheduleLaunchCheck()
    }

    @objc func checkForUpdates() {
        UpdateChecker.manualCheck()
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

    /// Breathe the sparkle while a prompt runs — instant visual confirm the shortcut fired.
    /// Swaps the button's image (a glyph rendered at a varying alpha) every frame.
    /// Changing content marks the status item dirty and forces the display cycle —
    /// the reliable menubar-animation mechanism. Setting layer.opacity or alphaValue
    /// does not refresh the live menu bar for an accessory app's status item.
    func startGlyphPulse() {
        guard pulseTimer == nil, statusItem?.button != nil else { return }
        pulseFrame = 0
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickPulse() }
        }
    }

    private func tickPulse() {
        guard let btn = statusItem?.button else { return }
        pulseFrame += 1
        let period: CGFloat = 36 // ~1.2s at 30fps
        let phase = CGFloat(pulseFrame).truncatingRemainder(dividingBy: period) / period
        let eased = (1 - cos(phase * 2 * .pi)) / 2 // 0 → 1 → 0
        let alpha = 1.0 - 0.85 * eased // 1.0 → 0.15 → 1.0
        btn.attributedTitle = NSAttributedString(string: "")
        btn.image = Self.glyphImage(alpha: alpha)
        btn.imagePosition = .imageOnly
    }

    private static func glyphImage(alpha: CGFloat) -> NSImage {
        let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let glyph = "✦" as NSString
        let probe = glyph.size(withAttributes: [.font: font])
        let size = NSSize(width: ceil(probe.width), height: ceil(probe.height))
        let img = NSImage(size: size, flipped: false) { _ in
            glyph.draw(at: .zero, withAttributes: [
                .font: font,
                .foregroundColor: NSColor.black.withAlphaComponent(alpha)
            ])
            return true
        }
        img.isTemplate = true // menu bar tints to the correct color; alpha drives the mask
        return img
    }

    func stopGlyphPulse(showCheck: Bool) {
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulseFrame = 0
        statusItem?.button?.image = nil
        statusItem?.button?.imagePosition = .noImage
        if showCheck {
            setStatusGlyph("✓")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.setStatusGlyph(nil)
            }
        } else {
            setStatusGlyph(nil)
        }
    }

    func ensureAccessibilityPrompt() {
        // Check only; do not auto-prompt at launch (would open System Settings on every
        // ad-hoc rebuild). Settings UI exposes a button to request access.
        _ = AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt"
        let opts: NSDictionary = [key: true]
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
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit caip", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let root = SettingsView().environment(store)
            let host = NSHostingController(rootView: root)
            let win = NSWindow(contentViewController: host)
            win.setContentSize(NSSize(width: 940, height: 600))
            win.minSize = NSSize(width: 920, height: 560)
            win.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
            win.title = "Copy · AI · Paste"
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .visible
            win.toolbarStyle = .unified
            // Empty toolbar so AppKit installs the unified title bar (gives us the
            // scroll-edge material blur). Visual effect comes from titlebar transparency.
            let toolbar = NSToolbar(identifier: "net.variant.caip.settings")
            toolbar.displayMode = .iconOnly
            toolbar.showsBaselineSeparator = false
            win.toolbar = toolbar
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
