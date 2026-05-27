import AppKit
import Carbon.HIToolbox

@MainActor
final class ActionRunner {
    private var running = false

    func run(presetId: UUID) {
        guard !running else { return }
        running = true
        Task { @MainActor in
            defer { self.running = false }
            await self.execute(presetId: presetId)
        }
    }

    private func execute(presetId: UUID) async {
        let store = PresetStore.shared
        guard let preset = store.presets.first(where: { $0.id == presetId }) else { return }

        if !AccessibilityCheck.isGranted() {
            Toast.show(title: "Accessibility access required",
                       body: "Open Settings → OpenRouter to grant it.",
                       icon: "lock.shield.fill",
                       tint: .orange,
                       duration: 3.5)
            AppDelegate.requestAccessibility()
            return
        }

        let capture = await captureSelectedText()
        switch capture {
        case .empty:
            Toast.show(title: "Selection is empty",
                       body: "Select some text, then press the shortcut.",
                       icon: "text.cursor",
                       tint: .secondary)
            return
        case .copyFailed:
            Toast.show(title: "Couldn't read selection",
                       body: "The focused app may block ⌘C.",
                       icon: "exclamationmark.triangle.fill",
                       tint: .orange)
            return
        case .success(let selection):
            await run(preset: preset, selection: selection, apiKey: store.apiKey, model: store.defaultModel)
        }
    }

    enum SelectionCapture {
        case success(String)
        case empty
        case copyFailed
    }

    private func run(preset: Preset, selection: String, apiKey: String, model: String) async {

        let prompt = preset.prompt
            .replacingOccurrences(of: "{selectedText}", with: selection)
            .replacingOccurrences(of: "{s}", with: selection)

        showStatus("⌛")
        do {
            let result = try await OpenRouter.complete(prompt: prompt, model: model, apiKey: apiKey)
            paste(text: result.trimmingCharacters(in: .whitespacesAndNewlines))
            showStatus("✓")
        } catch {
            Toast.show(title: "OpenRouter error",
                       body: error.localizedDescription,
                       icon: "exclamationmark.octagon.fill",
                       tint: .red,
                       duration: 4.0)
            showStatus(nil)
        }
    }

    private func captureSelectedText() async -> SelectionCapture {
        let pb = NSPasteboard.general
        let savedItems = pb.pasteboardItems?.map { item -> [NSPasteboard.PasteboardType: Data] in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy[type] = data
                }
            }
            return copy
        } ?? []
        Self.savedSnapshot = savedItems

        let beforeChange = pb.changeCount
        sendCommand(keyCode: CGKeyCode(kVK_ANSI_C))
        var changed = false
        for _ in 0..<24 {
            try? await Task.sleep(nanoseconds: 25_000_000) // 25ms each, up to 600ms
            if pb.changeCount != beforeChange { changed = true; break }
        }
        if !changed { return .copyFailed }
        guard let text = pb.string(forType: .string) else { return .copyFailed }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        return .success(text)
    }

    private static var savedSnapshot: [[NSPasteboard.PasteboardType: Data]] = []

    private func paste(text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        // Small delay so the focused app sees the new pasteboard before ⌘V fires.
        usleep(40_000)
        sendCommand(keyCode: CGKeyCode(kVK_ANSI_V))
        // Leave the AI result on the clipboard — user often wants to paste it again
        // elsewhere or keep it for reference. The pre-action clipboard is gone by design.
    }

    private func sendCommand(keyCode: CGKeyCode) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func notify(title: String, body: String) {
        Toast.show(title: title, body: body)
    }

    private func showStatus(_ text: String?) {
        guard let delegate = NSApp.delegate as? AppDelegate else { return }
        delegate.setStatusGlyph(text)
        if text != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                delegate.setStatusGlyph(nil)
            }
        }
    }
}
