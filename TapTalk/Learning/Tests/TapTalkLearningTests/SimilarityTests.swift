import XCTest
@testable import TapTalkLearning

final class SimilarityTests: XCTestCase {
    func testMishearingsPass() {
        XCTAssertTrue(Similarity.isMishearing(from: "Drew", to: "Dhruv"))
        XCTAssertTrue(Similarity.isMishearing(from: "tap talk", to: "TapTalk"))
        XCTAssertTrue(Similarity.isMishearing(from: "Drumid", to: "Dhrumit"))
    }

    // Different first sound: a different word, not a mishearing.
    func testDifferentFirstSoundIsRefused() {
        XCTAssertFalse(Similarity.isMishearing(from: "Tuesday", to: "Thursday"))
        XCTAssertFalse(Similarity.isMishearing(from: "Monday", to: "Sunday"))
        XCTAssertFalse(Similarity.isMishearing(from: "He", to: "She"))
        XCTAssertFalse(Similarity.isMishearing(from: "Increase", to: "Decrease"))
    }

    // Adding an ending changes grammar, not spelling.
    func testInflectionIsRefused() {
        XCTAssertFalse(Similarity.isMishearing(from: "Mac", to: "Macs"))
        XCTAssertFalse(Similarity.isMishearing(from: "Dhruv", to: "Dhruv's"))
        XCTAssertFalse(Similarity.isMishearing(from: "Can", to: "Can't"))
        XCTAssertFalse(Similarity.isMishearing(from: "Send", to: "Sending"))
    }
}
