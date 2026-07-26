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
        //
        // Punctuation is flattened to spaces before matching. Padding the markers alone is not
        // enough: "Um, can you send it" keeps "um" adjacent to a comma, so " um " never matches
        // and the sentence looks clean enough to skip — silently pasting the filler that Polish
        // was enabled to remove.
        let flattened = " " + trimmed.lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            + " "
        for marker in disfluencyMarkers where flattened.contains(marker) { return true }

        // Otherwise only worth a round trip if it isn't already a well-formed sentence.
        //
        // Scripts without letter case — Devanagari among them — can never satisfy the uppercase
        // test, so this returns true and the rewrite always runs for them. That is the safe
        // direction (the model is asked rather than the text assumed clean), but it does mean the
        // saving is Latin-script only. Widening it needs per-script sentence heuristics and
        // per-language filler lists, which is not worth carrying until someone measures how often
        // this fires.
        let endsCleanly = trimmed.last.map { ".!?।".contains($0) } ?? false
        let startsUpper = trimmed.first?.isUppercase ?? false
        return !(endsCleanly && startsUpper)
    }

    // Space-padded, matched against punctuation-flattened text, so "um" does not hit inside
    // "album" nor "like" inside "unlike", while "Um," and "like." still match.
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
