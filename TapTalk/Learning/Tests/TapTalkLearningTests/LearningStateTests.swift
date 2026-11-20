import XCTest
@testable import TapTalkLearning

final class LearningStateTests: XCTestCase {
    private let tt = RulePair(from: "tap talk", to: "TapTalk")
    private let d1 = UUID(), d2 = UUID(), d3 = UUID(), d4 = UUID()

    private func pairs(_ s: LearningState) -> [RulePair] {
        s.rules.map { RulePair(from: $0.from, to: $0.to) }
    }

    private func learned(_ pair: RulePair) -> LearningState {
        var s = LearningState()
        _ = s.record([pair], dictation: UUID())
        _ = s.record([pair], dictation: UUID())
        return s
    }

    func testLearnsAfterTwoDifferentDictations() {
        var s = LearningState()
        XCTAssertEqual(s.record([tt], dictation: d1), [])
        XCTAssertEqual(s.record([tt], dictation: d1), [])
        let events = s.record([tt], dictation: d2)
        XCTAssertEqual(pairs(s), [tt])
        XCTAssertEqual(events, [.learned(s.rules[0])])
    }

    func testUndoLearnedRemovesAndBlocks() {
        var s = LearningState()
        _ = s.record([tt], dictation: d1)
        let events = s.record([tt], dictation: d2)
        s.undo(events[0])
        XCTAssertTrue(s.rules.isEmpty)
        _ = s.record([tt], dictation: d3)
        XCTAssertEqual(s.record([tt], dictation: d4), [])
        XCTAssertTrue(s.rules.isEmpty)
    }

    func testRemoveBlocks() {
        var s = learned(tt)
        s.remove(ruleID: s.rules[0].id)
        XCTAssertTrue(s.rules.isEmpty)
        _ = s.record([tt], dictation: d3)
        XCTAssertEqual(s.record([tt], dictation: d4), [])
        XCTAssertTrue(s.rules.isEmpty)
    }

    func testReverseIsNeverLearnedAndTwiceStops() {
        var s = learned(tt)
        let rule = s.rules[0]
        let reverse = RulePair(from: "TapTalk", to: "tap talk")
        XCTAssertEqual(s.record([reverse], dictation: d3), [])
        XCTAssertEqual(s.record([reverse], dictation: d4), [.stopped(rule)])
        XCTAssertTrue(s.rules.isEmpty)
        _ = s.record([tt], dictation: UUID())
        _ = s.record([tt], dictation: UUID())
        _ = s.record([reverse], dictation: UUID())
        _ = s.record([reverse], dictation: UUID())
        XCTAssertTrue(s.rules.isEmpty)
    }

    func testUndoStoppedRestoresRule() {
        var s = learned(tt)
        let rule = s.rules[0]
        let reverse = RulePair(from: "TapTalk", to: "tap talk")
        _ = s.record([reverse], dictation: d3)
        let events = s.record([reverse], dictation: d4)
        s.undo(events[0])
        XCTAssertEqual(s.rules, [rule])
    }

    func testIgnoresFixForExistingFrom() {
        var s = learned(tt)
        let other = RulePair(from: "tap talk", to: "Tap-Talk")
        _ = s.record([other], dictation: d3)
        XCTAssertEqual(s.record([other], dictation: d4), [])
        XCTAssertEqual(pairs(s), [tt])
    }

    func testCandidateCapDropsOldest() {
        var s = LearningState()
        let first = RulePair(from: "word0", to: "Word0")
        _ = s.record([first], dictation: UUID())
        for i in 1...LearningState.candidateCap {
            _ = s.record([RulePair(from: "word\(i)", to: "Word\(i)")], dictation: UUID())
        }
        XCTAssertEqual(s.record([first], dictation: UUID()), [])
        XCTAssertTrue(s.rules.isEmpty)
    }

    func testDisabledGroupHasNoActivePairs() {
        var s = learned(tt)
        XCTAssertEqual(s.activePairs, [tt])
        s.isEnabled = false
        XCTAssertEqual(s.activePairs, [])
    }

    func testUpdateChangesRule() {
        var s = learned(tt)
        s.update(ruleID: s.rules[0].id, from: "tap talk", to: "TapTalk app")
        XCTAssertEqual(pairs(s), [RulePair(from: "tap talk", to: "TapTalk app")])
    }

    func testCodableRoundTrip() throws {
        let s = learned(tt)
        let decoded = try JSONDecoder().decode(LearningState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }
}
