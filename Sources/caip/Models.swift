import Foundation
import AppKit
import Carbon.HIToolbox

struct Hotkey: Codable, Equatable {
    var keyCode: UInt32
    var modifierFlags: UInt32 // NSEvent.ModifierFlags raw

    var carbonMods: UInt32 {
        var mods: UInt32 = 0
        if modifierFlags & UInt32(NSEvent.ModifierFlags.command.rawValue) != 0 { mods |= UInt32(cmdKey) }
        if modifierFlags & UInt32(NSEvent.ModifierFlags.shift.rawValue) != 0 { mods |= UInt32(shiftKey) }
        if modifierFlags & UInt32(NSEvent.ModifierFlags.option.rawValue) != 0 { mods |= UInt32(optionKey) }
        if modifierFlags & UInt32(NSEvent.ModifierFlags.control.rawValue) != 0 { mods |= UInt32(controlKey) }
        return mods
    }
}

enum PresetBehavior: String, Codable, CaseIterable, Identifiable {
    case replaceInline
    case popover

    var id: String { rawValue }
    var title: String {
        switch self {
        case .replaceInline: return "Replace Inline"
        case .popover: return "Popover"
        }
    }
}

struct Preset: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var prompt: String
    var model: String
    var hotkey: Hotkey?
    var behavior: PresetBehavior

    init(id: UUID = UUID(), name: String, prompt: String, model: String, hotkey: Hotkey? = nil, behavior: PresetBehavior = .replaceInline) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.model = model
        self.hotkey = hotkey
        self.behavior = behavior
    }

    enum CodingKeys: String, CodingKey {
        case id, name, prompt, model, hotkey, behavior
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        prompt = try c.decode(String.self, forKey: .prompt)
        model = try c.decode(String.self, forKey: .model)
        hotkey = try c.decodeIfPresent(Hotkey.self, forKey: .hotkey)
        behavior = (try c.decodeIfPresent(PresetBehavior.self, forKey: .behavior)) ?? .replaceInline
    }

    static let defaultPrompt = """
You are a careful text editor. Fix grammar and typos in [TEXT]. Output only corrected text. No commentary.

[TEXT]:
```{selectedText}```
"""
}
