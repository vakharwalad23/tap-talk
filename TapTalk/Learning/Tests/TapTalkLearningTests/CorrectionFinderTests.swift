import XCTest
@testable import TapTalkLearning

final class CorrectionFinderTests: XCTestCase {
    private func fix(_ pasted: String, _ field: String) -> [RulePair] {
        CorrectionFinder.fixes(pasted: pasted, fieldText: field).map(\.pair)
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
            CorrectionFinder.fixes(pasted: "I use tap talk every day.", fieldText: field, near: field.utf16.count).map(\.pair),
            [.init(from: "tap talk", to: "Tap Talk")]
        )
    }

    func testRepeatedFixedSentencesUsePastePosition() {
        let field = "My name is Dhruv.\nMy name is Dhruv."
        XCTAssertEqual(
            CorrectionFinder.fixes(pasted: "My name is Drew.", fieldText: field, near: field.utf16.count).map(\.pair),
            [.init(from: "Drew", to: "Dhruv")]
        )
    }

    func testPastePositionAtAnUnchangedCopyLearnsNothing() {
        let field = "I use tap talk every day.\nI use Tap Talk every day."
        XCTAssertEqual(CorrectionFinder.fixes(pasted: "I use tap talk every day.", fieldText: field, near: 0).map(\.pair), [])
    }

    // The first word of a sentence is capitalized by the recognizer, so it is checked like a lowercase word.
    func testSentenceStartIsMarked() {
        XCTAssertEqual(CorrectionFinder.fixes(pasted: "Drew asked for it.", fieldText: "Dhruv asked for it.").map(\.startsSentence), [true])
        XCTAssertEqual(CorrectionFinder.fixes(pasted: "Done. Drew asked.", fieldText: "Done. Dhruv asked.").map(\.startsSentence), [true])
        XCTAssertEqual(CorrectionFinder.fixes(pasted: "Ask Drew to review it.", fieldText: "Ask Dhruv to review it.").map(\.startsSentence), [false])
    }

    func testDictionaryWordsToCheck() {
        func words(_ from: String, _ to: String, startsSentence: Bool = false) -> [String]? {
            CorrectionFinder.dictionaryWords(for: FoundFix(pair: .init(from: from, to: to), startsSentence: startsSentence))
        }
        XCTAssertEqual(words("drew", "Dhruv"), ["drew"])
        XCTAssertNil(words("Drew", "Dhruv"))
        XCTAssertEqual(words("He", "She", startsSentence: true), ["he"])
        XCTAssertEqual(words("may be", "maybe"), ["may", "be", "maybe"])
        XCTAssertEqual(words("tap talk", "TapTalk"), ["tap", "talk", "tapTalk"])
        XCTAssertNil(words("tap talk", "Tap Talk"))
    }

    // Words typed inside the pasted sentence are an insertion, never a fix of a neighbouring word.
    func testInsertedWordsInsideThePasteAreNotAFix() {
        let pasted = "I will send the draft to the team today."
        let field = "I will send the draft and the slide deck to the team today."
        XCTAssertEqual(CorrectionFinder.fixes(pasted: pasted, fieldText: field, near: field.utf16.count).map(\.pair), [])
        XCTAssertEqual(fix(pasted, field), [])
    }

    func testLongPasteIsSkipped() {
        let pasted = Array(repeating: "word", count: 81).joined(separator: " ") + " Drew"
        let field = Array(repeating: "word", count: 81).joined(separator: " ") + " Dhruv"
        XCTAssertEqual(fix(pasted, field), [])
    }

    func testLongFieldIsReadAroundThePaste() {
        let field = String(repeating: "Some earlier notes about the week. ", count: 500) + "Ask Dhruv to review it."
        XCTAssertEqual(
            CorrectionFinder.fixes(pasted: "Ask Drew to review it.", fieldText: field, near: field.utf16.count).map(\.pair),
            [.init(from: "Drew", to: "Dhruv")]
        )
    }
}
