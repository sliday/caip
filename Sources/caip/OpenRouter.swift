import Foundation

struct OpenRouterModel: Identifiable, Codable, Hashable {
    let id: String
    let name: String?
    let promptPrice: Double?      // USD per input token
    let completionPrice: Double?  // USD per output token
    let contextLength: Int?
    let createdAt: Int?           // unix seconds

    var combinedPrice: Double? {
        guard let p = promptPrice, let c = completionPrice else { return promptPrice ?? completionPrice }
        return p + c
    }
}

private struct ModelsResponse: Codable {
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
    case http(Int, String)
    case empty

    var errorDescription: String? {
        switch self {
        case .missingKey: return "OpenRouter API key not set. Open Settings."
        case .http(let code, let body): return "OpenRouter error \(code): \(body)"
        case .empty: return "OpenRouter returned no content."
        }
    }
}

enum OpenRouter {
    static let endpoint = URL(string: "https://openrouter.ai/api/v1")!

    static func listModels(apiKey: String) async throws -> [OpenRouterModel] {
        var req = URLRequest(url: endpoint.appendingPathComponent("models"))
        if !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("https://github.com/stas/caip", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("caip", forHTTPHeaderField: "X-Title")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OpenRouterError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
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

    static func complete(prompt: String, model: String, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw OpenRouterError.missingKey }
        var req = URLRequest(url: endpoint.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://github.com/stas/caip", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("caip", forHTTPHeaderField: "X-Title")
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
}
