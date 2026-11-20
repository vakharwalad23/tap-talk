import Foundation

/// A word fix found in a field, and whether its first word starts a sentence (where the recognizer
/// capitalizes any word, so a capital there says nothing about it being a name).
public struct FoundFix: Equatable, Sendable {
    public let pair: RulePair
    public let startsSentence: Bool

    public init(pair: RulePair, startsSentence: Bool) {
        self.pair = pair
        self.startsSentence = startsSentence
    }
}

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
    /// Longer pastes are not compared: the comparison grows with their length, and fixes of names
    /// and terms arrive in ordinary-length dictations.
    static let maxPastedWords = 80
    /// Field text kept on each side of the paste position, beyond twice the pasted length.
    static let contextSlack = 200

    /// Replacements from the pasted form to the field's form; empty when the pasted text cannot be
    /// located with confidence. The ordinary-word rule is left to the caller (it needs a dictionary).
    /// `near` is where the paste landed, as a UTF-16 offset into `fieldText` (the caret when it was
    /// pasted). With it, the copy nearest the paste is chosen, so a sentence repeated elsewhere in the
    /// field neither hides the fix nor makes it ambiguous.
    public static func fixes(pasted: String, fieldText fullText: String, near caret: Int? = nil) -> [FoundFix] {
        let typed = words(in: pasted)
        guard !typed.isEmpty, typed.count <= maxPastedWords else { return [] }
        // Only the text around the paste is compared, so a long document costs no more than a short one.
        var fieldText = fullText
        var near = caret
        if let caret {
            (fieldText, near) = window(fullText, around: caret, radius: 2 * pasted.utf16.count + contextSlack)
        }
        let field = words(in: fieldText)
        guard !field.isEmpty else { return [] }
        let found: Match?
        if let near {
            found = locate(typed.map(\.text), in: field.map(\.text), near: near, offsets: utf16Ranges(field, in: fieldText))
        } else {
            found = locate(typed.map(\.text), in: field.map(\.text))
        }
        guard let located = found else { return [] }
        let match = realigned(located, typed.map(\.text), field.map(\.text))

        var fixes: [FoundFix] = []
        for block in replacedBlocks(match, typedCount: typed.count, fieldCount: field.count) {
            guard block.typed.count <= maxSpan, block.field.count <= maxSpan else { continue }
            let from = String(pasted[typed[block.typed.lowerBound].range.lowerBound..<typed[block.typed.upperBound - 1].range.upperBound])
            let to = String(fieldText[field[block.field.lowerBound].range.lowerBound..<field[block.field.upperBound - 1].range.upperBound])
            guard from != to, !from.contains(where: \.isNumber), !to.contains(where: \.isNumber),
                  Similarity.isMishearing(from: from, to: to)
            else { continue }
            let opens = startsSentence(at: typed[block.typed.lowerBound].range.lowerBound, in: pasted)
            fixes.append(FoundFix(pair: RulePair(from: from, to: to), startsSentence: opens))
        }
        return fixes
    }

    /// The words that, when every one is an ordinary dictionary word, mean the fix must not be learned;
    /// nil when no check is needed. A lowercase or sentence-start word ("drew", "He") would be replaced
    /// everywhere it is used; a join or split of ordinary words ("may be" -> "maybe") is grammar, not
    /// a mishearing. A capitalized word mid-sentence is taken as a name.
    public static func dictionaryWords(for fix: FoundFix) -> [String]? {
        let fromWords = words(in: fix.pair.from).map(\.text)
        let toWords = words(in: fix.pair.to).map(\.text)
        if fromWords.count == 1, toWords.count == 1 {
            guard fix.startsSentence || !fix.pair.from.contains(where: \.isUppercase) else { return nil }
            return fromWords.map(lowercasingFirst)
        }
        guard fromWords.count != toWords.count else { return nil }
        return (fromWords + toWords).map(lowercasingFirst)
    }

    static func lowercasingFirst(_ word: String) -> String {
        word.prefix(1).lowercased() + word.dropFirst()
    }

    /// True when only spaces, quotes or brackets stand between the word and the start of the text or
    /// a sentence end.
    static func startsSentence(at index: String.Index, in text: String) -> Bool {
        var cursor = index
        while cursor > text.startIndex {
            cursor = text.index(before: cursor)
            let character = text[cursor]
            if character == " " || character == "\t" || character == "\"" || character == "(" { continue }
            return character == "." || character == "!" || character == "?" || character.isNewline
        }
        return true
    }

    /// The field text within `radius` UTF-16 units of `caret`, and the caret offset within it.
    static func window(_ text: String, around caret: Int, radius: Int) -> (String, Int) {
        let utf16 = text.utf16
        guard utf16.count > 2 * radius else { return (text, caret) }
        let center = min(max(0, caret), utf16.count)
        let lowIndex = utf16.index(utf16.startIndex, offsetBy: max(0, center - radius))
        let highIndex = utf16.index(utf16.startIndex, offsetBy: min(utf16.count, center + radius))
        let low = lowIndex == text.endIndex ? text.endIndex : text.rangeOfComposedCharacterSequence(at: lowIndex).lowerBound
        let high = highIndex == text.endIndex ? text.endIndex : text.rangeOfComposedCharacterSequence(at: highIndex).lowerBound
        return (String(text[low..<high]), center - utf16.distance(from: utf16.startIndex, to: low))
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

    /// Picks the candidate nearest the paste position among those that fit well enough; a closer
    /// distance wins, then a better fit. Two separate places equally near and equally good are
    /// ambiguous.
    static func locate(_ typed: [String], in field: [String], near: Int, offsets: [Range<Int>]) -> Match? {
        let typedWords = Set(typed)
        var best: (distance: Int, score: Int, span: Range<Int>, match: Match)?
        var tied = false
        for start in field.indices where typedWords.contains(field[start]) {
            let window = Array(field[start..<min(field.count, start + typed.count + windowSlack)])
            let (score, length) = longestPrefixMatch(typed, window)
            guard score > 0, Double(score) / Double(typed.count) >= minimumScore else { continue }
            let pairs = alignment(typed, Array(field[start..<(start + length)]))
            guard let first = pairs.first, let last = pairs.last else { continue }
            let span = (start + first.field)..<(start + last.field + 1)
            let lower = offsets[span.lowerBound].lowerBound
            let upper = offsets[span.upperBound - 1].upperBound
            let distance = near < lower ? lower - near : max(0, near - upper)
            let match = pairs.map { (typed: $0.typed, field: start + $0.field) }
            guard let current = best else {
                best = (distance, score, span, match)
                continue
            }
            if distance < current.distance || (distance == current.distance && score > current.score) {
                best = (distance, score, span, match)
                tied = false
            } else if distance == current.distance, score == current.score, !span.overlaps(current.span) {
                tied = true
            }
        }
        guard let best, !tied else { return nil }
        return best.match
    }

    /// UTF-16 offsets of each word, the unit Accessibility reports the caret in. Walked once, in order.
    static func utf16Ranges(_ words: [Word], in text: String) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var index = text.startIndex
        var offset = 0
        for word in words {
            offset += text.utf16.distance(from: index, to: word.range.lowerBound)
            let length = text.utf16.distance(from: word.range.lowerBound, to: word.range.upperBound)
            ranges.append(offset..<(offset + length))
            offset += length
            index = word.range.upperBound
        }
        return ranges
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

    /// Aligns the pasted words again over the located span widened by the unmatched words on each
    /// side, so words typed inside the paste line up as an insertion instead of pairing a pasted word
    /// with an identical neighbour.
    static func realigned(_ match: Match, _ typed: [String], _ field: [String]) -> Match {
        guard let first = match.first, let last = match.last else { return match }
        let lower = max(0, first.field - first.typed - maxSpan)
        let upper = min(field.count, last.field + 1 + (typed.count - last.typed - 1) + maxSpan)
        return alignment(typed, Array(field[lower..<upper])).map { (typed: $0.typed, field: lower + $0.field) }
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
