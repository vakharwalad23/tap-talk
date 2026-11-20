import Foundation

/// A word fix TapTalk has learned and applies to later dictations.
public struct LearnedRule: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var from: String
    public var to: String

    public init(id: UUID = UUID(), from: String, to: String) {
        self.id = id
        self.from = from
        self.to = to
    }
}

/// What a recorded dictation changed, for the pill to announce and Undo to reverse.
public enum LearningEvent: Equatable, Sendable {
    case learned(LearnedRule)
    case stopped(LearnedRule)
}

/// Learned rules plus what learning more needs: fixes seen once, and fixes the user refused.
public struct LearningState: Codable, Equatable, Sendable {
    /// Fixes seen only once are kept up to this many; the oldest are forgotten first.
    public static let candidateCap = 200
    /// A fix seen in this many different dictations becomes a rule; its reverse, a removal.
    static let sightingsNeeded = 2

    public private(set) var rules: [LearnedRule] = []
    /// The Learned group's own switch on Words.
    public var isEnabled = true
    private var candidates: [Candidate] = []
    private var blocked: Set<RulePair> = []

    private struct Candidate: Codable, Equatable, Sendable {
        var pair: RulePair
        var dictations: Set<UUID>
    }

    public init() {}

    public var activePairs: [RulePair] {
        isEnabled ? rules.map { RulePair(from: $0.from, to: $0.to) } : []
    }

    /// Records the fixes found after one dictation. Repeats within the same dictation count once.
    public mutating func record(_ fixes: [RulePair], dictation: UUID) -> [LearningEvent] {
        var events: [LearningEvent] = []
        for fix in fixes where !blocked.contains(where: { Self.sameFix($0, fix) }) {
            // Changing a rule's output back is evidence against the rule, never a new rule.
            if let index = rules.firstIndex(where: { Self.sameText($0.from, fix.to) && Self.sameText($0.to, fix.from) }) {
                if sighted(fix, in: dictation) != nil {
                    let rule = rules.remove(at: index)
                    forget(fix)
                    blocked.insert(RulePair(from: rule.from, to: rule.to))
                    blocked.insert(fix)
                    events.append(.stopped(rule))
                }
                continue
            }
            guard !rules.contains(where: { Self.sameText($0.from, fix.from) }) else { continue }
            if let learned = sighted(fix, in: dictation) {
                forget(fix)
                let rule = LearnedRule(from: learned.from, to: learned.to)
                rules.append(rule)
                events.append(.learned(rule))
            }
        }
        return events
    }

    /// Reverses a learned or stopped notice. Undoing a learned rule also blocks it from returning.
    public mutating func undo(_ event: LearningEvent) {
        switch event {
        case .learned(let rule):
            rules.removeAll { $0.id == rule.id }
            blocked.insert(RulePair(from: rule.from, to: rule.to))
        case .stopped(let rule):
            blocked.remove(RulePair(from: rule.from, to: rule.to))
            blocked.remove(RulePair(from: rule.to, to: rule.from))
            if !rules.contains(where: { $0.id == rule.id }) { rules.append(rule) }
        }
    }

    /// Deletes a rule from Words; the same fix is never learned again.
    public mutating func remove(ruleID: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }
        let rule = rules.remove(at: index)
        blocked.insert(RulePair(from: rule.from, to: rule.to))
    }

    public mutating func update(ruleID: UUID, from: String, to: String) {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }
        rules[index].from = from
        rules[index].to = to
    }

    /// Adds a sighting; returns the fix to learn once it has been seen in enough different dictations.
    /// The mid-sentence form is kept when both were seen, so the rule also matches at sentence start.
    private mutating func sighted(_ fix: RulePair, in dictation: UUID) -> RulePair? {
        if let index = candidates.firstIndex(where: { Self.sameFix($0.pair, fix) }) {
            candidates[index].dictations.insert(dictation)
            if fix.from.first?.isLowercase == true { candidates[index].pair.from = fix.from }
            let pair = candidates[index].pair
            return candidates[index].dictations.count >= Self.sightingsNeeded ? pair : nil
        }
        candidates.append(Candidate(pair: fix, dictations: [dictation]))
        if candidates.count > Self.candidateCap {
            candidates.removeFirst(candidates.count - Self.candidateCap)
        }
        return nil
    }

    private mutating func forget(_ fix: RulePair) {
        candidates.removeAll { Self.sameFix($0.pair, fix) }
    }

    // A capital first letter is how speech recognition starts a sentence, not a different word.
    private static func sameText(_ a: String, _ b: String) -> Bool {
        a == b || (a.prefix(1).lowercased() == b.prefix(1).lowercased() && a.dropFirst() == b.dropFirst())
    }

    private static func sameFix(_ a: RulePair, _ b: RulePair) -> Bool {
        sameText(a.from, b.from) && a.to == b.to
    }
}
