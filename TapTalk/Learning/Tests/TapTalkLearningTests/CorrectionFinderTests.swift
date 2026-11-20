import XCTest
@testable import TapTalkLearning

final class CorrectionFinderTests: XCTestCase {
    private func fix(_ pasted: String, _ field: String) -> [RulePair] {
        CorrectionFinder.fixes(pasted: pasted, fieldText: field)
    }

    func testSpacingAndCaseFix() {
        XCTAssertEqual(fix("I use tap talk every day.", "Notes: I use TapTalk every day. More"), [.init(from: "tap talk", to: "TapTalk")])
    }

    func testNameFix() {
        XCTAssertEqual(fix("Ask Drew to review it.", "Ask Dhruv to review it."), [.init(from: "Drew", to: "Dhruv")])
    }

    func testJoinedWordFix() {
        XCTAssertEqual(fix("Open taptalk now.", "Open TapTalk now."), [.init(from: "taptalk", to: "TapTalk")])
    }

    func testTypedElsewhereInField() {
        XCTAssertEqual(fix("Ask Drew to review it.", "Hello team,\nAsk Dhruv to review it.\nThanks"), [.init(from: "Drew", to: "Dhruv")])
    }

    func testContentEditIgnored() {
        XCTAssertEqual(fix("See you Tuesday at ten.", "See you Wednesday at ten."), [])
    }

    func testNumberEditIgnored() {
        XCTAssertEqual(fix("Meet at 10 today.", "Meet at 11 today."), [])
    }

    func testRewordIgnored() {
        XCTAssertEqual(fix("Please send it tomorrow morning.", "Please ship the build next week."), [])
    }

    func testInsertionsIgnored() {
        XCTAssertEqual(fix("Ask Drew to review.", "Ask Drew to review it today."), [])
    }

    func testSpanOverThreeWords() {
        XCTAssertEqual(fix("we can go to the shop now", "we can travel over to a store now"), [])
    }

    func testNotFound() {
        XCTAssertEqual(fix("Ask Drew to review it.", "Totally different content here."), [])
    }

    func testUnchangedCopyWins() {
        XCTAssertEqual(fix("Ask Drew now.", "Ask Drew now. Ask Dhruv now."), [])
    }

    func testAmbiguousLocation() {
        XCTAssertEqual(fix("Ask Drew now.", "Ask Dhruv now. Ask Dhruv now."), [])
    }

    // The same sentence repeated in one field: the paste position picks the copy that was pasted.
    func testRepeatedSentenceUsesPastePosition() {
        let field = "I use tap talk every day.\nI use Tap Talk every day."
        XCTAssertEqual(
            CorrectionFinder.fixes(pasted: "I use tap talk every day.", fieldText: field, near: field.utf16.count),
            [.init(from: "tap talk", to: "Tap Talk")]
        )
    }

    func testRepeatedFixedSentencesUsePastePosition() {
        let field = "My name is Dhruv.\nMy name is Dhruv."
        XCTAssertEqual(
            CorrectionFinder.fixes(pasted: "My name is Drew.", fieldText: field, near: field.utf16.count),
            [.init(from: "Drew", to: "Dhruv")]
        )
    }

    func testPastePositionAtAnUnchangedCopyLearnsNothing() {
        let field = "I use tap talk every day.\nI use Tap Talk every day."
        XCTAssertEqual(CorrectionFinder.fixes(pasted: "I use tap talk every day.", fieldText: field, near: 0), [])
    }

    func testOrdinaryWordCheck() {
        XCTAssertTrue(CorrectionFinder.needsOrdinaryWordCheck(.init(from: "drew", to: "Dhruv")))
        XCTAssertFalse(CorrectionFinder.needsOrdinaryWordCheck(.init(from: "Drew", to: "Dhruv")))
        XCTAssertFalse(CorrectionFinder.needsOrdinaryWordCheck(.init(from: "tap talk", to: "TapTalk")))
    }
}
