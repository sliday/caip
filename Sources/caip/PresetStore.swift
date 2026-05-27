import Foundation
import Observation
import AppKit

@Observable
@MainActor
final class PresetStore {
    static let shared = PresetStore()

    var presets: [Preset] = []
    var apiKey: String = ""
    var defaultModel: String = "openrouter/auto"

    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let defaultModelKey = "caip.defaultModel"
    @ObservationIgnored private let apiKeyKey = "caip.openrouterApiKey"

    init() {
        let fm = FileManager.default
        let support = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = support.appendingPathComponent("caip", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("presets.json")
        if let saved = UserDefaults.standard.string(forKey: defaultModelKey), !saved.isEmpty {
            self.defaultModel = saved
        }
        load()
        if let stored = UserDefaults.standard.string(forKey: apiKeyKey) {
            apiKey = stored
        } else if let legacy = Keychain.apiKey() {
            apiKey = legacy
            UserDefaults.standard.set(legacy, forKey: apiKeyKey)
        }
    }

    func updateDefaultModel(_ value: String) {
        defaultModel = value
        UserDefaults.standard.set(value, forKey: defaultModelKey)
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([Preset].self, from: data) else {
            presets = [Preset(name: "Grammar Fix", prompt: Preset.defaultPrompt, model: defaultModel, hotkey: nil)]
            save()
            return
        }
        presets = list
    }

    func save() {
        if let data = try? JSONEncoder().encode(presets) {
            try? data.write(to: fileURL, options: .atomic)
        }
        onChange?()
    }

    func updateAPIKey(_ value: String) {
        apiKey = value
        if value.isEmpty {
            UserDefaults.standard.removeObject(forKey: apiKeyKey)
        } else {
            UserDefaults.standard.set(value, forKey: apiKeyKey)
        }
    }

    func addPreset() -> Preset {
        let preset = Preset(name: "New Action", prompt: Preset.defaultPrompt, model: defaultModel, hotkey: nil)
        presets.append(preset)
        save()
        return preset
    }

    func remove(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
        save()
    }

    func update(_ preset: Preset) {
        if let idx = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[idx] = preset
            save()
        }
    }
}
