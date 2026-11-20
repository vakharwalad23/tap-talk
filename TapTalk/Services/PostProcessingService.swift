import Foundation

struct PostProcessingService {
    static func rewrite(
        _ text: String,
        systemPrompt: String,
        client: LLMBackendClient
    ) async throws -> String {
        let result = try await client.complete(systemPrompt: systemPrompt, userMessage: text)
        return result.isEmpty ? text : stripCodeFences(result)
    }

    // LLMs sometimes wrap output in ```lang ... ``` despite instructions not to
    private static func stripCodeFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("```") else { return s }
        // Remove opening fence (```plaintext, ```swift, ```, etc.)
        if let firstNewline = s.firstIndex(of: "\n") {
            s = String(s[s.index(after: firstNewline)...])
        }
        if s.hasSuffix("```") {
            s = String(s.dropLast(3))
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
