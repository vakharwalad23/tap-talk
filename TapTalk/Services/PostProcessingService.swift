import Foundation

struct PostProcessingService {
    // Longest-match-first to avoid partial replacement (e.g. "gonna" before "gon")
    static func applyDictionary(_ text: String, segments: [DictionarySegment]) -> String {
        let pairs = segments
            .filter(\.isEnabled)
            .flatMap(\.entries)
            .filter { !$0.from.isEmpty }
            .sorted { $0.from.count > $1.from.count }

        guard !pairs.isEmpty else { return text }

        var result = text
        for pair in pairs {
            let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: pair.from))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: pair.to)
        }
        return result
    }

    static func rewrite(
        _ text: String,
        systemPrompt: String,
        client: LLMBackendClient
    ) async throws -> String {
        let result = try await client.complete(systemPrompt: systemPrompt, userMessage: text)
        return result.isEmpty ? text : result
    }
}
