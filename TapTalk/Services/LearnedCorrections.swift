import Combine
import Foundation
import TapTalkLearning

/// The word fixes TapTalk has learned, stored on this Mac, with their rules compiled once per change.
@MainActor
final class LearnedCorrections: ObservableObject {
    static let shared = LearnedCorrections()

    private static let storageKey = "learnedCorrections"

    @Published private(set) var state: LearningState
    /// Applied to the final text right before it is pasted; snapshot it on the main actor.
    private(set) var rules: TextRules = .empty
    private var dictionaryWatch: AnyCancellable?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(LearningState.self, from: data) {
            state = decoded
        } else {
            state = LearningState()
        }
        rules = Self.compile(state.activePairs, dictionary: SettingsStore.shared.dictionarySegments)
        // A dictionary edit can cover a learned word; the user's entry must win from the next paste on.
        dictionaryWatch = SettingsStore.shared.$dictionarySegments
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] segments in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.rules = Self.compile(self.state.activePairs, dictionary: segments)
                }
            }
    }

    private static func compile(_ learned: [RulePair], dictionary: [DictionarySegment]) -> TextRules {
        TextRules(learned.overridden(by: SettingsStore.pairs(for: dictionary)), matching: .exactCaseOrSentenceStart)
    }

    func record(_ fixes: [RulePair], dictation: UUID) -> [LearningEvent] {
        guard !fixes.isEmpty else { return [] }
        var next = state
        let events = next.record(fixes, dictation: dictation)
        commit(next)
        return events
    }

    func undo(_ event: LearningEvent) { change { $0.undo(event) } }

    func remove(ruleID: UUID) { change { $0.remove(ruleID: ruleID) } }

    func update(ruleID: UUID, from: String, to: String) {
        change { $0.update(ruleID: ruleID, from: from, to: to) }
    }

    func setEnabled(_ on: Bool) { change { $0.isEnabled = on } }

    private func change(_ edit: (inout LearningState) -> Void) {
        var next = state
        edit(&next)
        commit(next)
    }

    private func commit(_ next: LearningState) {
        guard next != state else { return }
        if next.activePairs != state.activePairs {
            rules = Self.compile(next.activePairs, dictionary: SettingsStore.shared.dictionarySegments)
        }
        state = next
        if let data = try? JSONEncoder().encode(next) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
