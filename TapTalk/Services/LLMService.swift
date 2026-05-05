import Foundation

protocol LLMBackendClient {
    func complete(systemPrompt: String, userMessage: String) async throws -> String
}

// OpenAI-compatible chat completions endpoint (works with OpenAI, Ollama, LM Studio, etc.)
struct CustomEndpointClient: LLMBackendClient {
    let baseURL: String
    let model: String
    let apiKey: String

    func complete(systemPrompt: String, userMessage: String) async throws -> String {
        guard var urlString = Optional(baseURL.trimmingCharacters(in: .whitespaces)),
              !urlString.isEmpty else {
            throw LLMError.invalidConfiguration("Endpoint URL is empty")
        }
        if urlString.hasSuffix("/") { urlString.removeLast() }
        guard let url = URL(string: "\(urlString)/v1/chat/completions") else {
            throw LLMError.invalidConfiguration("Invalid endpoint URL: \(urlString)")
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userMessage]
            ],
            "max_tokens": 1024,
            "temperature": 0.3
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LLMError.networkError("No HTTP response")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.serverError(http.statusCode, body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum LLMError: LocalizedError {
    case invalidConfiguration(String)
    case networkError(String)
    case serverError(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let msg): return "Config error: \(msg)"
        case .networkError(let msg):         return "Network error: \(msg)"
        case .serverError(let code, _):      return "Server error \(code)"
        case .invalidResponse:               return "Unexpected response format"
        }
    }
}

func makeLLMClient(settings: SettingsStore) -> LLMBackendClient? {
    guard settings.llmEnabled else { return nil }
    switch settings.llmBackend {
    case .custom:
        guard !settings.llmEndpointURL.isEmpty else { return nil }
        return CustomEndpointClient(
            baseURL: settings.llmEndpointURL,
            model: settings.llmModel,
            apiKey: settings.llmApiKey
        )
    case .local:
        return nil // Phase A2
    }
}

func testLLMConnection(settings: SettingsStore) async throws -> String {
    guard let client = makeLLMClient(settings: settings) else {
        throw LLMError.invalidConfiguration("LLM not configured")
    }
    let result = try await client.complete(
        systemPrompt: "You are a test assistant.",
        userMessage: "Reply with exactly: ok"
    )
    return result.isEmpty ? "Connected" : "Connected · \(result.prefix(30))"
}
