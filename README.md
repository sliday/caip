<div align="center">
  <img src="docs/icon.png" width="128" alt="caip"/>
  <h1>caip</h1>
  <p><strong>c</strong>opy → <strong>AI</strong> → <strong>p</strong>aste</p>
  <p>Tiny native macOS menubar app. Select any text, press a hotkey, get AI-rewritten text pasted in place.</p>
  <p>
    <a href="https://caip.dev">caip.dev</a>
    ·
    <a href="https://openrouter.ai/keys">OpenRouter</a>
    ·
    <a href="#install">Install</a>
    ·
    <a href="#how-it-works">How it works</a>
  </p>
</div>

---

## Features

- **Menubar only.** No Dock icon, no Electron. Sits in the menubar (`✦`) and gets out of the way.
- **Per-action hotkeys.** Multiple presets, each with its own prompt and global shortcut. ⌃⌥⇧⌘ in any combination, plus standalone F-keys.
- **OpenRouter under the hood.** Bring your key. 350+ models. Pick one default; sort by price, context, or recency.
- **Real native UI.** SwiftUI + AppKit. Stock controls, no custom theming.
- **~700 KB binary.** Universal Swift build, no dependencies.

## Install

### From source

```bash
git clone https://github.com/sliday/caip.git
cd caip
bash build.sh
open build/caip.app
```

Requires Swift 5.9+. Xcode Command Line Tools is enough — no full Xcode needed.

> Drag `build/caip.app` to `/Applications` to install permanently.

### Permissions

caip needs **Accessibility** access to send ⌘C and ⌘V on your behalf. On first run, grant it in System Settings → Privacy & Security → Accessibility.

For ad-hoc builds (no Developer ID), each rebuild creates a fresh code identity. If permission seems granted but caip still complains, use **Settings → OpenRouter → ⋯ → Reset & re-grant**.

## How it works

1. You select text in any app.
2. You press the hotkey you bound to an action.
3. caip simulates **⌘C**, reads the pasteboard, substitutes `{selectedText}` into your prompt.
4. caip POSTs to `https://openrouter.ai/api/v1/chat/completions`.
5. caip writes the response to the pasteboard and simulates **⌘V**.
6. caip restores your previous clipboard.

The whole roundtrip is typically under a second with a fast model.

## Setup

1. Click the `✦` in the menubar → **Settings…**
2. **OpenRouter** tab → paste your API key (from [openrouter.ai/keys](https://openrouter.ai/keys)).
3. Pick a default model. Search and sort to find one with the right price/context tradeoff.
4. **Actions** tab → **+ Add Action** → give it a name, write a prompt, record a shortcut.

### Prompt placeholders

In an action's prompt, `{selectedText}` (or `{s}`) is replaced with the selected text before the request fires.

```
Fix grammar in [TEXT]. Output corrected text only. No commentary.

[TEXT]:
```{selectedText}```
```

## Build

```bash
bash build.sh
```

Outputs `build/caip.app`. The script:
- runs `swift build -c release`,
- copies the binary into a proper `.app` bundle,
- bundles `AppIcon.icns` and `Info.plist` (`LSUIElement=true`),
- ad-hoc code-signs with stable identifier `net.variant.caip`.

### Regenerating the icon

```bash
python3 scripts/make_icon.py
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
```

## File layout

```
Sources/caip/
├── App.swift            – @main, AppDelegate adaptor
├── AppDelegate.swift    – menubar, lifecycle, permission helpers
├── Models.swift         – Preset / Hotkey models
├── PresetStore.swift    – JSON persistence, defaults, prefs
├── HotkeyManager.swift  – Carbon RegisterEventHotKey
├── HotkeyRecorder.swift – CGEvent tap recorder
├── ActionRunner.swift   – copy → API → paste pipeline
├── OpenRouter.swift     – REST client + model list
├── SettingsView.swift   – SwiftUI Settings UI
├── Toast.swift          – floating HUD notifications
└── Provider.swift       – provider icons / colors
Resources/Info.plist     – bundle metadata
build.sh                 – build + package script
scripts/make_icon.py     – icon generator
```

## Data

- **Presets:** `~/Library/Application Support/caip/presets.json`
- **API key + default model:** `~/Library/Preferences/net.variant.caip.plist`

## License

MIT — see [LICENSE](LICENSE).
