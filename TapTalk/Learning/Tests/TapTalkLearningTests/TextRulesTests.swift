import XCTest
@testable import TapTalkLearning

final class TextRulesTests: XCTestCase {
    func testLongestMatchFirst() {
        let r = TextRules([.init(from: "gon", to: "X"), .init(from: "gonna", to: "going to")], matching: .caseInsensitive)
        XCTAssertEqual(r.apply("I'm gonna go"), "I'm going to go")
    }

    func testCaseInsensitiveOnWordBoundaries() {
        let r = TextRules([.init(from: "tap talk", to: "TapTalk")], matching: .caseInsensitive)
        XCTAssertEqual(r.apply("Tap talk and TAP TALK, not tap talker"), "TapTalk and TapTalk, not tap talker")
    }

    func testExactCaseOrSentenceStart() {
        let r = TextRules([.init(from: "Drew", to: "Dhruv"), .init(from: "tap talk", to: "TapTalk")], matching: .exactCaseOrSentenceStart)
        XCTAssertEqual(r.apply("Drew drew it. Tap talk works, TAP TALK not."), "Dhruv drew it. TapTalk works, TAP TALK not.")
    }

    func testReplacementIsNotRematched() {
        let r = TextRules([.init(from: "a", to: "b"), .init(from: "b", to: "c")], matching: .caseInsensitive)
        XCTAssertEqual(r.apply("a b"), "b c")
    }

    func testMetacharactersAreLiteral() {
        let r = TextRules([.init(from: "node.js", to: "Node.js")], matching: .caseInsensitive)
        XCTAssertEqual(r.apply("nodexjs and node.js"), "nodexjs and Node.js")
    }

    func testDictionaryEntryOverridesLearnedPair() {
        let learned: [RulePair] = [.init(from: "tap talk", to: "Tap Talk"), .init(from: "Drew", to: "Dhruv")]
        let dictionary: [RulePair] = [.init(from: "TAP TALK", to: "TapTalk")]
        XCTAssertEqual(learned.overridden(by: dictionary), [.init(from: "Drew", to: "Dhruv")])
        XCTAssertEqual(learned.overridden(by: []), learned)
    }

    func testCaseFoldingMatchesFinalSigma() {
        // Greek "logos": final small sigma in the rule, capital sigma in the all-caps text.
        let lower = "\u{3BB}\u{3CC}\u{3B3}\u{3BF}\u{3C2}"
        let upper = "\u{39B}\u{38C}\u{393}\u{39F}\u{3A3}"
        let r = TextRules([.init(from: lower, to: "logos")], matching: .caseInsensitive)
        XCTAssertEqual(r.apply("say \(upper) now"), "say logos now")
    }

    func testEmptyFromAndNoRules() {
        XCTAssertEqual(TextRules([.init(from: "", to: "x")], matching: .caseInsensitive).apply("keep"), "keep")
        XCTAssertEqual(TextRules.empty.apply("keep"), "keep")
    }
}
