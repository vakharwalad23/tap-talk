import Foundation

/// One word replacement: text matching `from` becomes `to`.
public struct RulePair: Codable, Hashable, Sendable {
    public var from: String
    public var to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

/// How a rule's `from` is matched against text.
public enum RuleMatching: Sendable {
    /// Any letter case, as the user's dictionary has always matched.
    case caseInsensitive
    /// The form as written, plus the same form with its first letter capitalized (sentence start).
    case exactCaseOrSentenceStart
}

/// Replacements compiled once into a single pattern and applied in one pass, so the cost per
/// dictation stays flat as the rule list grows. A replacement's output is never matched again.
public struct TextRules: Sendable {
    public static let empty = TextRules([], matching: .caseInsensitive)

    private let regex: NSRegularExpression?
    private let replacements: [String: String]
    private let caseInsensitive: Bool

    public init(_ pairs: [RulePair], matching: RuleMatching) {
        let caseInsensitive = matching == .caseInsensitive
        var table: [String: String] = [:]
        var forms: [String] = []
        for pair in pairs where !pair.from.isEmpty {
            let variants = caseInsensitive ? [pair.from] : [pair.from, Self.capitalizingFirst(pair.from)]
            for form in variants {
                let key = caseInsensitive ? form.lowercased() : form
                guard table[key] == nil else { continue }
                table[key] = pair.to
                forms.append(form)
            }
        }
        self.caseInsensitive = caseInsensitive
        replacements = table
        guard !forms.isEmpty else {
            regex = nil
            return
        }
        // Alternation takes the first branch that matches, so longer forms go first ("gonna" before "gon").
        let alternatives = forms.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:))
        regex = try? NSRegularExpression(
            pattern: "\\b(?:" + alternatives.joined(separator: "|") + ")\\b",
            options: caseInsensitive ? [.caseInsensitive] : []
        )
    }

    public func apply(_ text: String) -> String {
        guard let regex else { return text }
        let source = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let range = match.range
            let found = source.substring(with: range)
            guard let replacement = replacements[caseInsensitive ? found.lowercased() : found] else { continue }
            result += source.substring(with: NSRange(location: cursor, length: range.location - cursor))
            result += replacement
            cursor = range.location + range.length
        }
        return result + source.substring(from: cursor)
    }

    private static func capitalizingFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
