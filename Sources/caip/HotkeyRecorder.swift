import SwiftUI
import AppKit
import Carbon.HIToolbox

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var hotkey: Hotkey?

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.onChange = { hotkey = $0 }
        v.hotkey = hotkey
        return v
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.hotkey = hotkey
        nsView.needsDisplay = true
    }
}

final class RecorderView: NSView {
    var hotkey: Hotkey? { didSet { needsDisplay = true } }
    var onChange: ((Hotkey?) -> Void)?
    private var recording = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?
    private var isHovered = false { didSet { needsDisplay = true } }
    private var liveMods: NSEvent.ModifierFlags = [] { didSet { needsDisplay = true } }
    private var recordingStartedAt: TimeInterval = 0
    private var localMonitor: Any?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        teardownTap()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; NSCursor.pointingHand.push() }
    override func mouseExited(with event: NSEvent) { isHovered = false; NSCursor.pop() }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius: CGFloat = 6
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let fill: NSColor
        if recording {
            fill = NSColor.controlAccentColor.withAlphaComponent(0.15)
        } else if isHovered {
            fill = NSColor.controlBackgroundColor.blended(withFraction: 0.05, of: .labelColor) ?? .controlBackgroundColor
        } else {
            fill = NSColor.controlBackgroundColor
        }
        fill.setFill()
        path.fill()
        if recording {
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 1.5
        } else {
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
        }
        path.stroke()

        let label: String
        let labelColor: NSColor
        if recording {
            let live = describeMods(liveMods)
            if !live.isEmpty {
                label = "\(live)…  ·  Esc to cancel"
            } else {
                label = "Press shortcut  ·  Esc to cancel"
            }
            labelColor = .secondaryLabelColor
        } else if let hk = hotkey {
            label = describe(hk)
            labelColor = .labelColor
        } else {
            label = "Click to record"
            labelColor = .secondaryLabelColor
        }

        let font: NSFont = (hotkey != nil && !recording)
            ? NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
            : NSFont.systemFont(ofSize: 12)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: labelColor]
        let s = NSAttributedString(string: label, attributes: attrs)
        let size = s.size()
        let xInset: CGFloat = 10
        let clearWidth: CGFloat = (hotkey != nil && !recording) ? 22 : 0
        let textRect = NSRect(x: xInset,
                              y: (bounds.height - size.height) / 2,
                              width: bounds.width - xInset * 2 - clearWidth,
                              height: size.height)
        s.draw(in: textRect)

        if hotkey != nil && !recording {
            let clearGlyph = NSAttributedString(string: "⌫", attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: isHovered ? NSColor.labelColor : NSColor.tertiaryLabelColor
            ])
            let sz = clearGlyph.size()
            clearGlyph.draw(at: NSPoint(x: bounds.width - sz.width - 10,
                                        y: (bounds.height - sz.height) / 2))
        }
    }

    override func mouseDown(with event: NSEvent) {
        if hotkey != nil, !recording {
            let loc = convert(event.locationInWindow, from: nil)
            if loc.x > bounds.width - 28 {
                hotkey = nil
                onChange?(nil)
                return
            }
        }
        beginRecording()
    }

    private func beginRecording() {
        guard !recording else { return }
        recording = true
        liveMods = []
        recordingStartedAt = ProcessInfo.processInfo.systemUptime
        window?.makeFirstResponder(self)
        installLocalMonitor()
        if !installEventTap() {
            NSLog("[caip] CGEvent tap install failed — Accessibility permission needed for global key capture")
        }
    }

    private func endRecording() {
        recording = false
        liveMods = []
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        teardownTap()
    }

    private func installLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self = self, self.recording else { return event }
            switch event.type {
            case .keyDown:
                let elapsed = ProcessInfo.processInfo.systemUptime - self.recordingStartedAt
                if elapsed < 0.10 { return nil }
                let mods = event.modifierFlags
                    .intersection(.deviceIndependentFlagsMask)
                    .intersection([.command, .option, .control, .shift])
                self.captureKey(keyCode: UInt16(event.keyCode), mods: mods)
                return nil
            case .flagsChanged:
                self.liveMods = event.modifierFlags
                    .intersection(.deviceIndependentFlagsMask)
                    .intersection([.command, .option, .control, .shift])
                return nil
            case .keyUp:
                return nil
            default:
                return event
            }
        }
    }

    private func installEventTap() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
            let view = Unmanaged<RecorderView>.fromOpaque(userInfo).takeUnretainedValue()
            return view.handleTapped(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: selfPtr
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.eventTap = tap
        self.runLoopSource = source
        return true
    }

    private func teardownTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleTapped(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if disabled by timeout
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard recording else { return Unmanaged.passUnretained(event) }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let cgFlags = event.flags
        let nsMods = NSEvent.ModifierFlags(rawValue: UInt(cgFlags.rawValue))
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .option, .control, .shift])

        switch type {
        case .flagsChanged:
            DispatchQueue.main.async { self.liveMods = nsMods }
            // Don't consume modifier-only events — let them flow so other apps see flag state too
            return Unmanaged.passUnretained(event)
        case .keyDown:
            let elapsed = ProcessInfo.processInfo.systemUptime - recordingStartedAt
            if elapsed < 0.10 { return Unmanaged.passUnretained(event) }
            DispatchQueue.main.async { self.captureKey(keyCode: keyCode, mods: nsMods) }
            return nil // consume
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func captureKey(keyCode: UInt16, mods: NSEvent.ModifierFlags) {
        if keyCode == UInt16(kVK_Escape) {
            endRecording()
            return
        }
        NSLog("[caip recorder] keyCode=\(keyCode) mods=0x\(String(mods.rawValue, radix: 16)) glyph=\(KeyName.string(for: keyCode))")
        if mods.isEmpty && !Self.isStandaloneAllowed(keyCode: keyCode) {
            NSSound.beep()
            return
        }
        let hk = Hotkey(keyCode: UInt32(keyCode), modifierFlags: UInt32(mods.rawValue))
        hotkey = hk
        onChange?(hk)
        endRecording()
    }

    private static func isStandaloneAllowed(keyCode: UInt16) -> Bool {
        let fkeys: Set<Int> = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
            kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
            kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
        ]
        return fkeys.contains(Int(keyCode))
    }

    private func describeMods(_ m: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if m.contains(.control) { parts.append("⌃") }
        if m.contains(.option) { parts.append("⌥") }
        if m.contains(.shift) { parts.append("⇧") }
        if m.contains(.command) { parts.append("⌘") }
        return parts.joined()
    }

    private func describe(_ hk: Hotkey) -> String {
        var parts: [String] = []
        let m = NSEvent.ModifierFlags(rawValue: UInt(hk.modifierFlags))
        if m.contains(.control) { parts.append("⌃") }
        if m.contains(.option) { parts.append("⌥") }
        if m.contains(.shift) { parts.append("⇧") }
        if m.contains(.command) { parts.append("⌘") }
        parts.append(KeyName.string(for: UInt16(hk.keyCode)))
        return parts.joined()
    }
}

enum KeyName {
    static func string(for keyCode: UInt16) -> String {
        let map: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
            kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥",
            kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
            kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
            kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
            kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_LeftBracket: "[",
            kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\",
            kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_Grave: "`",
            kVK_Escape: "⎋"
        ]
        return map[Int(keyCode)] ?? "Key \(keyCode)"
    }
}
