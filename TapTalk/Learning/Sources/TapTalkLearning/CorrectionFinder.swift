import Foundation

/// Finds the words a person fixed in text TapTalk pasted, by comparing it with what the field holds
/// now. Only short replacements that look or sound like what was typed count; anything else is
/// treated as an ordinary edit and ignored.
public enum CorrectionFinder {
    /// Share of the pasted words that must still be in place for the text to count as found.
    static let minimumScore = 0.6
    /// Longest replacement, in words, on either side.
    static let maxSpan = 3
    /// Extra field words a candidate location may span beyond the pasted word count.
    static let windowSlack = 3

    /// Replacements from the pasted form to the field's form; empty when the pasted text cannot be
    /// located with confidence. The ordinary-word rule is left to the caller (it needs a dictionary).
    public static func fixes(pasted: String, fieldText: String) -> [RulePair] {
        let typed = words(in: pasted)
        let field = words(in: fieldText)
        guard !typed.isEmpty, !field.isEmpty,
              let match = locate(typed.map(\.text), in: field.map(\.text))
        else { return [] }

        var fixes: [RulePair] = []
        for block in replacedBlocks(match, typedCount: typed.count, fieldCount: field.count) {
            guard block.typed.count <= maxSpan, block.field.count <= maxSpan else { continue }
            let from = String(pasted[typed[block.typed.lowerBound].range.lowerBound..<typed[block.typed.upperBound - 1].range.upperBound])
            let to = String(fieldText[field[block.field.lowerBound].range.lowerBound..<field[block.field.upperBound - 1].range.upperBound])
            guard !from.contains(where: \.isNumber), !to.contains(where: \.isNumber),
                  Similarity.isMishearing(from: from, to: to)
            else { continue }
            fixes.append(RulePair(from: from, to: to))
        }
        return fixes
    }

    /// True when "from" is a single word with no capital letter: the case where an ordinary
    /// dictionary word ("drew") would be replaced everywhere it is used.
    public static func needsOrdinaryWordCheck(_ pair: RulePair) -> Bool {
        words(in: pair.from).count == 1 && !pair.from.contains(where: \.isUppercase)
    }

    struct Word {
        let text: String
        let range: Range<String.Index>
    }

    static func words(in text: String) -> [Word] {
        var result: [Word] = []
        var start: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let isWordCharacter = text[index].isLetter || text[index].isNumber
                || text[index] == "'" || text[index] == "\u{2019}"
            if isWordCharacter, start == nil {
                start = index
            } else if !isWordCharacter, let wordStart = start {
                result.append(Word(text: String(text[wordStart..<index]), range: wordStart..<index))
                start = nil
            }
            index = text.index(after: index)
        }
        if let wordStart = start {
            result.append(Word(text: String(text[wordStart...]), range: wordStart..<text.endIndex))
        }
        return result
    }

    /// Matched (typed index, field index) pairs of the located text, in order.
    typealias Match = [(typed: Int, field: Int)]

    /// Finds where the pasted words sit in the field. Words compare exactly, case included, so a
    /// case-only fix shows up as a replacement. Two separate places that fit equally well are
    /// ambiguous, and nothing is learned from them.
    static func locate(_ typed: [String], in field: [String]) -> Match? {
        let typedWords = Set(typed)
        var bestScore = 0
        var candidates: [Range<Int>] = []
        for start in field.indices where typedWords.contains(field[start]) {
            let window = Array(field[start..<min(field.count, start + typed.count + windowSlack)])
            let (score, length) = longestPrefixMatch(typed, window)
            if score > bestScore {
                bestScore = score
                candidates = [start..<(start + length)]
            } else if score == bestScore {
                candidates.append(start..<(start + length))
            }
        }
        guard bestScore > 0, Double(bestScore) / Double(typed.count) >= minimumScore else { return nil }

        // Trim each candidate to the words its alignment actually uses, then group overlaps.
        let aligned: [(span: Range<Int>, match: Match)] = candidates.compactMap { candidate in
            let pairs = alignment(typed, Array(field[candidate]))
            guard let first = pairs.first, let last = pairs.last else { return nil }
            let match = pairs.map { (typed: $0.typed, field: candidate.lowerBound + $0.field) }
            return ((candidate.lowerBound + first.field)..<(candidate.lowerBound + last.field + 1), match)
        }.sorted { $0.span.lowerBound < $1.span.lowerBound }

        var groups = 0
        var groupEnd = Int.min
        for entry in aligned {
            if entry.span.lowerBound >= groupEnd { groups += 1 }
            groupEnd = max(groupEnd, entry.span.upperBound)
        }
        guard groups == 1 else { return nil }
        return aligned.first?.match
    }

    /// The longest common subsequence of `typed` with any prefix of `window`, and the shortest
    /// prefix length that reaches it.
    static func longestPrefixMatch(_ typed: [String], _ window: [String]) -> (score: Int, length: Int) {
        var previous = [Int](repeating: 0, count: window.count + 1)
        for word in typed {
            var current = [Int](repeating: 0, count: window.count + 1)
            for j in stride(from: 1, through: window.count, by: 1) {
                current[j] = word == window[j - 1] ? previous[j - 1] + 1 : max(previous[j], current[j - 1])
            }
            previous = current
        }
        let score = previous.max() ?? 0
        return (score, previous.firstIndex(of: score) ?? 0)
    }

    /// Longest-common-subsequence alignment of two word lists, as matched index pairs in order.
    static func alignment(_ typed: [String], _ field: [String]) -> Match {
        guard !typed.isEmpty, !field.isEmpty else { return [] }
        var table = [[Int]](repeating: [Int](repeating: 0, count: field.count + 1), count: typed.count + 1)
        for i in 1...typed.count {
            for j in 1...field.count {
                table[i][j] = typed[i - 1] == field[j - 1]
                    ? table[i - 1][j - 1] + 1
                    : max(table[i - 1][j], table[i][j - 1])
            }
        }
        var pairs: Match = []
        var i = typed.count
        var j = field.count
        while i > 0, j > 0 {
            if typed[i - 1] == field[j - 1] {
                pairs.append((typed: i - 1, field: j - 1))
                i -= 1
                j -= 1
            } else if table[i - 1][j] >= table[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return pairs.reversed()
    }

    /// Stretches of typed words and field words between matched words, including a stretch before
    /// the first or after the last match, so a fixed first or last word is still seen.
    static func replacedBlocks(_ match: Match, typedCount: Int, fieldCount: Int) -> [(typed: Range<Int>, field: Range<Int>)] {
        guard let first = match.first, let last = match.last else { return [] }
        var blocks: [(typed: Range<Int>, field: Range<Int>)] = []
        blocks.append((0..<first.typed, max(0, first.field - first.typed)..<first.field))
        for (a, b) in zip(match, match.dropFirst()) {
            blocks.append(((a.typed + 1)..<b.typed, (a.field + 1)..<b.field))
        }
        let trailing = typedCount - last.typed - 1
        blocks.append(((last.typed + 1)..<typedCount, (last.field + 1)..<min(fieldCount, last.field + 1 + trailing)))
        return blocks.filter { !$0.typed.isEmpty && !$0.field.isEmpty }
    }
}
