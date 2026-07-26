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

    /// Whether the cleanup modes have anything to do. A round trip costs ~750 ms, so a transcript
    /// that is already clean should be pasted as-is rather than sent for confirmation.
    ///
    /// Only applies to the cleanup modes. Match-the-app reformats for the destination regardless
    /// of how tidy the transcript is — "list files by size" is spotless and still has to become a
    /// shell command — so a smart rewrite is never skipped.
    static func needsCleanup(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Long enough to plausibly contain a self-correction or a run-on worth fixing.
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        if words.count > 12 { return true }

        // Disfluency or self-correction markers anywhere means there is work to do.
        let lowered = " " + trimmed.lowercased() + " "
        for marker in disfluencyMarkers where lowered.contains(marker) { return true }

        // Otherwise only worth a round trip if it isn't already a well-formed sentence.
        let endsCleanly = trimmed.last.map { ".!?।".contains($0) } ?? false
        let startsUpper = trimmed.first?.isUppercase ?? false
        return !(endsCleanly && startsUpper)
    }

    // Padded with spaces so "um" does not match inside "album" and "like" not inside "unlike".
    private static let disfluencyMarkers = [
        " um ", " uh ", " er ", " erm ", " hmm ", " like ", " you know ", " i mean ",
        " actually ", " no wait ", " sorry ", " scratch that ", " i meant ",
    ]

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
