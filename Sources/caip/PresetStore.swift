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
    var preset: ServicePreset = .openRouter
    var baseURL: String = ServicePreset.openRouter.defaultBaseURL

    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let defaultModelKey = "caip.defaultModel"
    @ObservationIgnored private let apiKeyKey = "caip.openrouterApiKey"
    @ObservationIgnored private let presetKey = "caip.servicePreset"
    @ObservationIgnored private let baseURLKey = "caip.serviceBaseURL"

    init() {
        let fm = FileManager.default
        let support = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = support.appendingPathComponent("caip", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("presets.json")
        if let saved = UserDefaults.standard.string(forKey: defaultModelKey), !saved.isEmpty {
            self.defaultModel = saved
        }
        if let rawPreset = UserDefaults.standard.string(forKey: presetKey),
           let p = ServicePreset(rawValue: rawPreset) {
            self.preset = p
            self.baseURL = p.defaultBaseURL
        }
        if let savedURL = UserDefaults.standard.string(forKey: baseURLKey), !savedURL.isEmpty {
            self.baseURL = savedURL
        }
        load()
        if let stored = UserDefaults.standard.string(forKey: apiKeyKey) {
            apiKey = stored
        } else if let legacy = Keychain.apiKey() {
            apiKey = legacy
            UserDefaults.standard.set(legacy, forKey: apiKeyKey)
        }
    }

    func updateServicePreset(_ value: ServicePreset, autoApplyBaseURL: Bool = true) {
        preset = value
        UserDefaults.standard.set(value.rawValue, forKey: presetKey)
        if autoApplyBaseURL && value != .custom {
            updateBaseURL(value.defaultBaseURL)
        }
    }

    func updateBaseURL(_ value: String) {
        baseURL = value
        UserDefaults.standard.set(value, forKey: baseURLKey)
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
