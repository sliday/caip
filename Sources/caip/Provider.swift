import SwiftUI

enum Provider: String, CaseIterable {
    case openai, anthropic, google, meta, mistral, cohere, perplexity, groq, openrouter, ollama, together, deepseek, qwen, xai, other

    static func from(modelId: String) -> Provider {
        let lower = modelId.lowercased()
        if lower.contains("openai/") || lower.hasPrefix("gpt") || lower.contains("o1") || lower.contains("o3") { return .openai }
        if lower.contains("anthropic/") || lower.contains("claude") { return .anthropic }
        if lower.contains("google/") || lower.contains("gemini") || lower.contains("palm") { return .google }
        if lower.contains("meta/") || lower.contains("llama") { return .meta }
        if lower.contains("mistral") { return .mistral }
        if lower.contains("cohere") { return .cohere }
        if lower.contains("perplexity") { return .perplexity }
        if lower.contains("groq") { return .groq }
        if lower.contains("openrouter") { return .openrouter }
        if lower.contains("ollama") { return .ollama }
        if lower.contains("together") { return .together }
        if lower.contains("deepseek") { return .deepseek }
        if lower.contains("qwen") { return .qwen }
        if lower.contains("xai/") || lower.contains("grok") { return .xai }
        return .other
    }

    var symbol: String {
        switch self {
        case .openai: return "circle.hexagongrid.fill"
        case .anthropic: return "a.circle.fill"
        case .google: return "g.circle.fill"
        case .meta: return "m.circle.fill"
        case .mistral: return "wind"
        case .cohere: return "c.circle.fill"
        case .perplexity: return "questionmark.circle.fill"
        case .groq: return "bolt.circle.fill"
        case .openrouter: return "arrow.triangle.branch"
        case .ollama: return "circle.dashed"
        case .together: return "t.circle.fill"
        case .deepseek: return "magnifyingglass.circle.fill"
        case .qwen: return "q.circle.fill"
        case .xai: return "x.circle.fill"
        case .other: return "sparkle"
        }
    }

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .google: return "Google"
        case .meta: return "Meta"
        case .mistral: return "Mistral"
        case .cohere: return "Cohere"
        case .perplexity: return "Perplexity"
        case .groq: return "Groq"
        case .openrouter: return "OpenRouter"
        case .ollama: return "Ollama"
        case .together: return "Together"
        case .deepseek: return "DeepSeek"
        case .qwen: return "Qwen"
        case .xai: return "xAI"
        case .other: return "Model"
        }
    }

    var tint: Color {
        switch self {
        case .openai: return .green
        case .anthropic: return .orange
        case .google: return .blue
        case .meta: return .blue
        case .mistral: return .red
        case .cohere: return .pink
        case .perplexity: return .teal
        case .groq: return .yellow
        case .openrouter: return .purple
        case .ollama: return .gray
        case .together: return .indigo
        case .deepseek: return .cyan
        case .qwen: return .mint
        case .xai: return .black
        case .other: return .secondary
        }
    }
}
