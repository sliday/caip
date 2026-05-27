import Foundation

// Renamed to a generic OpenAI-compatible Service so caip can talk to OpenRouter,
// Ollama, LM Studio, Jan, llama.cpp, vLLM, or any custom endpoint.

enum ServicePreset: String, CaseIterable, Identifiable, Codable {
    case openRouter, openAI, anthropic, zai, kimi, ollama, lmStudio, jan, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .openAI:     return "OpenAI"
        case .anthropic:  return "Anthropic"
        case .zai:        return "Z.AI"
        case .kimi:       return "Kimi"
        case .ollama:     return "Ollama"
        case .lmStudio:   return "LM Studio"
        case .jan:        return "Jan"
        case .custom:     return "Custom"
        }
    }

    var subtitle: String {
        switch self {
        case .openRouter: return "Cloud · 350+ models · requires key"
        case .openAI:     return "Cloud · GPT-4/o-series direct from OpenAI"
        case .anthropic:  return "Cloud · Claude models via OpenAI-compat layer"
        case .zai:        return "Cloud · Zhipu GLM family"
        case .kimi:       return "Cloud · Moonshot Kimi models (long context)"
        case .ollama:     return "Local · runs models on your Mac"
        case .lmStudio:   return "Local · GUI for local models"
        case .jan:        return "Local · open-source chat runtime"
        case .custom:     return "Any OpenAI-compatible endpoint"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .openAI:     return "https://api.openai.com/v1"
        case .anthropic:  return "https://api.anthropic.com/v1"
        case .zai:        return "https://api.z.ai/api/paas/v4"
        case .kimi:       return "https://api.moonshot.ai/v1"
        case .ollama:     return "http://localhost:11434/v1"
        case .lmStudio:   return "http://localhost:1234/v1"
        case .jan:        return "http://127.0.0.1:1337/v1"
        case .custom:     return ""
        }
    }

    var needsAPIKey: Bool {
        switch self {
        case .openRouter, .openAI, .anthropic, .zai, .kimi: return true
        case .ollama, .lmStudio, .jan: return false
        case .custom: return false // user decides
        }
    }

    var apiKeyURL: String? {
        switch self {
        case .openRouter: return "https://openrouter.ai/keys"
        case .openAI:     return "https://platform.openai.com/api-keys"
        case .anthropic:  return "https://console.anthropic.com/settings/keys"
        case .zai:        return "https://z.ai/manage-apikey/apikey-list"
        case .kimi:       return "https://platform.kimi.ai/console/api-keys"
        default: return nil
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .openRouter: return "sk-or-…"
        case .openAI:     return "sk-…"
        case .anthropic:  return "sk-ant-…"
        case .zai, .kimi: return "your API key"
        default:          return "leave blank if not needed"
        }
    }

    var symbol: String {
        switch self {
        case .openRouter: return "globe"
        case .openAI:     return "circle.hexagongrid.fill"
        case .anthropic:  return "a.circle.fill"
        case .zai:        return "z.circle.fill"
        case .kimi:       return "k.circle.fill"
        case .ollama:     return "cube"
        case .lmStudio:   return "macbook"
        case .jan:        return "j.square"
        case .custom:     return "slider.horizontal.3"
        }
    }

    /// Z.AI does not expose `/models`. Provide a curated list so the picker still works.
    var hardcodedModels: [OpenRouterModel]? {
        switch self {
        case .zai:
            return [
                OpenRouterModel(id: "glm-4.6", name: "GLM-4.6", promptPrice: nil, completionPrice: nil, contextLength: 200_000, createdAt: nil),
                OpenRouterModel(id: "glm-4.5", name: "GLM-4.5", promptPrice: nil, completionPrice: nil, contextLength: 128_000, createdAt: nil),
                OpenRouterModel(id: "glm-4-air", name: "GLM-4 Air", promptPrice: nil, completionPrice: nil, contextLength: 128_000, createdAt: nil),
                OpenRouterModel(id: "glm-4-flash", name: "GLM-4 Flash", promptPrice: nil, completionPrice: nil, contextLength: 128_000, createdAt: nil)
            ]
        default:
            return nil
        }
    }
}

struct OpenRouterModel: Identifiable, Codable, Hashable {
    let id: String
    let name: String?
    let promptPrice: Double?
    let completionPrice: Double?
    let contextLength: Int?
    let createdAt: Int?

    var combinedPrice: Double? {
        guard let p = promptPrice, let c = completionPrice else { return promptPrice ?? completionPrice }
        return p + c
    }
}

private struct ModelsResponseFull: Codable {
    struct Pricing: Codable {
        let prompt: String?
        let completion: String?
    }
    struct Item: Codable {
        let id: String
        let name: String?
        let pricing: Pricing?
        let context_length: Int?
        let created: Int?
    }
    let data: [Item]
}

private struct ChatRequest: Codable {
    struct Message: Codable { let role: String; let content: String }
    let model: String
    let messages: [Message]
    let stream: Bool
}

private struct ChatResponse: Codable {
    struct Choice: Codable {
        struct Msg: Codable { let content: String? }
        let message: Msg
    }
    let choices: [Choice]
}

enum OpenRouterError: Error, LocalizedError {
    case missingKey
    case missingBaseURL
    case http(Int, String)
    case empty

    var errorDescription: String? {
        switch self {
        case .missingKey: return "API key not set. Open Settings → Service."
        case .missingBaseURL: return "Base URL not set. Open Settings → Service."
        case .http(let code, let body): return "Service error \(code): \(body)"
        case .empty: return "Service returned no content."
        }
    }
}

enum OpenRouter {

    static func listModels(baseURL: String, apiKey: String, preset: ServicePreset = .custom) async throws -> [OpenRouterModel] {
        if let curated = preset.hardcodedModels { return curated }
        let url = try url(base: baseURL, path: "models")
        var req = URLRequest(url: url)
        if !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        applyAttribution(&req)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OpenRouterError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        // Many local servers return the same OpenAI-style shape. Be lenient.
        if let decoded = try? JSONDecoder().decode(ModelsResponseFull.self, from: data) {
            return decoded.data.map { item in
                OpenRouterModel(
                    id: item.id,
                    name: item.name,
                    promptPrice: item.pricing?.prompt.flatMap(Double.init),
                    completionPrice: item.pricing?.completion.flatMap(Double.init),
                    contextLength: item.context_length,
                    createdAt: item.created
                )
            }
        }
        // Fallback: minimal shape
        struct Minimal: Codable { struct Item: Codable { let id: String; let name: String? }; let data: [Item] }
        let mini = try JSONDecoder().decode(Minimal.self, from: data)
        return mini.data.map { OpenRouterModel(id: $0.id, name: $0.name, promptPrice: nil, completionPrice: nil, contextLength: nil, createdAt: nil) }
    }

    static func complete(prompt: String, model: String, baseURL: String, apiKey: String, requireKey: Bool) async throws -> String {
        guard !baseURL.isEmpty else { throw OpenRouterError.missingBaseURL }
        if requireKey, apiKey.isEmpty { throw OpenRouterError.missingKey }
        let url = try url(base: baseURL, path: "chat/completions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAttribution(&req)
        let body = ChatRequest(model: model, messages: [.init(role: "user", content: prompt)], stream: false)
        req.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OpenRouterError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
            throw OpenRouterError.empty
        }
        return text
    }

    private static func applyAttribution(_ req: inout URLRequest) {
        req.setValue("https://caip.dev", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("caip", forHTTPHeaderField: "X-Title")
    }

    private static func url(base: String, path: String) throws -> URL {
        var trimmed = base.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed + "/" + path) else {
            throw OpenRouterError.missingBaseURL
        }
        return url
    }
}
