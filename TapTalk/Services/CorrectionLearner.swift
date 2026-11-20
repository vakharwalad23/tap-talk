import AppKit
import ApplicationServices
import TapTalkLearning
import os

/// Remembers where the last dictation was pasted and, when the next one starts, reads that field
/// once to see whether a word TapTalk typed was fixed. Nothing runs between dictations, and no
/// field text is kept or logged: only the fixed words are stored.
@MainActor
final class CorrectionLearner {
    static let shared = CorrectionLearner()

    private struct Pending {
        let field: AXUIElement
        let text: String
    }

    // Accessibility messages block their thread until the other app answers, so they run here.
    private let queue = DispatchQueue(label: "talk.tap.learning", qos: .utility)
    private let logger = Logger(subsystem: "talk.tap.app", category: "learning")
    private let settings = SettingsStore.shared
    private var pending: Pending?
    private var pasteGeneration = 0
    private var notice: (event: LearningEvent, generation: Int)?

    private init() {}

    /// Remembers the focused field and the text just inserted into it.
    func didPaste(_ text: String) {
        pending = nil
        guard settings.learnCorrections, !text.isEmpty else { return }
        pasteGeneration &+= 1
        let generation = pasteGeneration
        queue.async {
            let field = FieldReader.focusedTextField()
            Task { @MainActor in
                guard generation == self.pasteGeneration else { return }
                guard let field else {
                    self.logger.notice("paste: no readable field")
                    return
                }
                self.pending = Pending(field: field, text: text)
            }
        }
    }

    /// Compares the remembered paste with its field, once. Called after capture has started; never
    /// awaited. `generation` ties any notice to the dictation that produced it.
    func dictationStarted(generation: Int) {
        // The paste is taken before reading, so a paste landing meanwhile becomes the next one.
        guard let taken = pending else { return }
        pending = nil
        guard settings.learnCorrections else { return }
        let userFroms = Set(settings.dictionarySegments.flatMap(\.entries).map { $0.from.lowercased() })
        let started = DispatchTime.now().uptimeNanoseconds
        queue.async {
            let read = FieldReader.text(of: taken.field)
            var fixes: [RulePair] = []
            if case .text(let fieldText) = read {
                fixes = CorrectionFinder.fixes(pasted: taken.text, fieldText: fieldText)
            }
            let ms = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            Task { @MainActor in
                self.finish(read: read, fixes: fixes, ms: ms, generation: generation, userFroms: userFroms)
            }
        }
    }

    /// The notice for the dictation being pasted, if its comparison produced one.
    func takeNotice(generation: Int) -> LearningEvent? {
        defer { notice = nil }
        guard let notice, notice.generation == generation else { return nil }
        return notice.event
    }

    func undoNotice(_ event: LearningEvent) {
        LearnedCorrections.shared.undo(event)
    }

    private func finish(read: FieldRead, fixes: [RulePair], ms: Double, generation: Int, userFroms: Set<String>) {
        // A user dictionary entry always wins, and an ordinary word ("drew") is never replaced.
        let learnable = fixes.filter { fix in
            !userFroms.contains(fix.from.lowercased())
                && !(CorrectionFinder.needsOrdinaryWordCheck(fix) && Self.isOrdinaryWord(fix.from))
        }
        let events = LearnedCorrections.shared.record(learnable, dictation: UUID())
        if let last = events.last { notice = (last, generation) }
        logger.notice("""
            read \(Self.label(read), privacy: .public) in \(ms, format: .fixed(precision: 1)) ms: \
            \(fixes.count) found, \(learnable.count) kept, \(events.count) changed
            """)
    }

    private static func isOrdinaryWord(_ word: String) -> Bool {
        NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0).location == NSNotFound
    }

    private static func label(_ read: FieldRead) -> String {
        switch read {
        case .text: return "ok"
        case .gone: return "field gone"
        case .timedOut: return "timed out"
        case .tooLong: return "too long"
        case .unreadable: return "unreadable"
        }
    }
}
