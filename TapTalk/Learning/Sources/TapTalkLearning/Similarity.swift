import Foundation

/// Decides whether a replacement looks like a mishearing (the fix sounds or reads like what was
/// typed) rather than a change of mind. "tap talk -> TapTalk" and "Drew -> Dhruv" pass;
/// "Tuesday -> Wednesday" does not.
enum Similarity {
    /// Largest edit distance, as a share of the longer word, for two spellings to count as close.
    static let maxSpellingDistance = 0.34
    /// The same limit for the two sound keys.
    static let maxSoundDistance = 0.34

    static func isMishearing(from: String, to: String) -> Bool {
        let a = letters(from)
        let b = letters(to)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        guard !isInflection(from, to), sameFirstSound(a, b) else { return false }
        if distanceRatio(a, b) <= maxSpellingDistance { return true }
        let keyA = soundKey(a)
        let keyB = soundKey(b)
        guard max(keyA.count, keyB.count) >= 2 else { return false }
        return distanceRatio(keyA, keyB) <= maxSoundDistance
    }

    // A different first sound means a different word ("Tuesday" -> "Thursday", "He" -> "She"), even
    // when the rest of the spelling is close.
    static func sameFirstSound(_ a: [Character], _ b: [Character]) -> Bool {
        soundKey(a).first == soundKey(b).first
    }

    /// Endings that change grammar rather than spelling: "Mac" -> "Macs", "Can" -> "Can't".
    static let inflections = ["s", "es", "d", "ed", "ing", "'s", "'t", "n't", "'d", "'m", "'re", "'ll", "'ve"]

    static func isInflection(_ a: String, _ b: String) -> Bool {
        let x = a.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        let y = b.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        return inflections.contains { y == x + $0 || x == y + $0 }
    }

    /// Lowercased letters only, so spacing, hyphens and case do not count as differences.
    static func letters(_ text: String) -> [Character] {
        Array(text.lowercased().filter(\.isLetter))
    }

    static func distanceRatio(_ a: [Character], _ b: [Character]) -> Double {
        Double(editDistance(a, b)) / Double(max(a.count, b.count))
    }

    static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        for i in stride(from: 1, through: a.count, by: 1) {
            var current = [i] + [Int](repeating: 0, count: b.count)
            for j in stride(from: 1, through: b.count, by: 1) {
                current[j] = a[i - 1] == b[j - 1]
                    ? previous[j - 1]
                    : 1 + min(previous[j - 1], previous[j], current[j - 1])
            }
            previous = current
        }
        return previous[b.count]
    }

    // A simplified Metaphone-style consonant key: enough to tell sound-alikes apart from other words
    // in short names and terms.
    static func soundKey(_ letters: [Character]) -> [Character] {
        var text = String(letters)
        for prefix in ["kn", "gn", "wr", "ps"] where text.hasPrefix(prefix) {
            text.removeFirst()
        }
        for (digraph, sound) in [("tch", "x"), ("sh", "x"), ("ch", "x"), ("ph", "f"), ("ck", "k"),
                                 ("th", "0"), ("gh", ""), ("wh", "w"), ("dh", "d"), ("kh", "k"), ("bh", "b")] {
            text = text.replacingOccurrences(of: digraph, with: sound)
        }
        var key: [Character] = []
        for (index, character) in text.enumerated() {
            let sound: Character?
            switch character {
            case "a", "e", "i", "o", "u", "y": sound = index == 0 ? "a" : nil
            case "w", "h": sound = index == 0 ? character : nil
            case "b", "p": sound = "p"
            case "d", "t": sound = "t"
            case "c", "g", "k", "q": sound = "k"
            case "f", "v": sound = "f"
            case "s", "z": sound = "s"
            case "j": sound = "x"
            default: sound = character
            }
            if let sound, key.last != sound { key.append(sound) }
        }
        return key
    }
}
