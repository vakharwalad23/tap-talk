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

    func testEmptyFromAndNoRules() {
        XCTAssertEqual(TextRules([.init(from: "", to: "x")], matching: .caseInsensitive).apply("keep"), "keep")
        XCTAssertEqual(TextRules.empty.apply("keep"), "keep")
    }
}
