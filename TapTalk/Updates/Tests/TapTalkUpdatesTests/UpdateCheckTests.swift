import XCTest
@testable import TapTalkUpdates

final class UpdateCheckTests: XCTestCase {
    private let json = """
    {"tag_name":"v0.6.0","html_url":"https://github.com/vakharwalad23/tap-talk/releases/tag/v0.6.0",
     "assets":[{"name":"notes.txt","browser_download_url":"https://example.com/notes.txt"},
               {"name":"TapTalk-0.6.0.dmg","browser_download_url":"https://example.com/TapTalk-0.6.0.dmg"},
               {"name":"Other.dmg","browser_download_url":"https://example.com/Other.dmg"}]}
    """

    func testDecodesVersionPageAndFirstDmg() throws {
        let r = try UpdateCheck.release(fromGitHubJSON: Data(json.utf8))
        XCTAssertEqual(r.version, "0.6.0")
        XCTAssertEqual(r.pageURL.absoluteString, "https://github.com/vakharwalad23/tap-talk/releases/tag/v0.6.0")
        XCTAssertEqual(r.dmgURL?.absoluteString, "https://example.com/TapTalk-0.6.0.dmg")
    }

    func testReleaseWithoutDmgHasNoDmgURL() throws {
        let data = Data(#"{"tag_name":"0.6.0","html_url":"https://example.com/r","assets":[]}"#.utf8)
        XCTAssertNil(try UpdateCheck.release(fromGitHubJSON: data).dmgURL)
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try UpdateCheck.release(fromGitHubJSON: Data("{}".utf8)))
        XCTAssertThrowsError(try UpdateCheck.release(fromGitHubJSON: Data(#"{"message":"API rate limit exceeded"}"#.utf8)))
    }

    func testVersionComparison() {
        XCTAssertTrue(UpdateCheck.isNewer("0.6.0", than: "0.5.2"))
        XCTAssertTrue(UpdateCheck.isNewer("0.10.0", than: "0.9.9"))
        XCTAssertTrue(UpdateCheck.isNewer("v0.6.0", than: "0.5.2"))
        XCTAssertFalse(UpdateCheck.isNewer("0.5.2", than: "0.5.2"))
        XCTAssertFalse(UpdateCheck.isNewer("1.0", than: "1.0.0"))
        XCTAssertFalse(UpdateCheck.isNewer("0.5.1", than: "0.5.2"))
        XCTAssertFalse(UpdateCheck.isNewer("0.6.0-beta", than: "0.5.2"))
        XCTAssertFalse(UpdateCheck.isNewer("", than: "0.5.2"))
    }

    func testInstallSource() {
        XCTAssertEqual(UpdateCheck.installSource(caskroomEntries: ["taptalk"]), .homebrew)
        XCTAssertEqual(UpdateCheck.installSource(caskroomEntries: ["taptalk@0.5.1"]), .pinnedHomebrew)
        XCTAssertEqual(UpdateCheck.installSource(caskroomEntries: ["firefox"]), .dmg)
        XCTAssertEqual(UpdateCheck.installSource(caskroomEntries: []), .dmg)
    }

    func testNoticeActions() throws {
        let r = try UpdateCheck.release(fromGitHubJSON: Data(json.utf8))
        XCTAssertEqual(UpdateCheck.notice(for: r, currentVersion: "0.5.2", source: .homebrew, dismissedVersion: nil),
                       UpdateNotice(version: "0.6.0", action: .copyCommand("brew upgrade --cask taptalk")))
        XCTAssertEqual(UpdateCheck.notice(for: r, currentVersion: "0.5.2", source: .dmg, dismissedVersion: nil)?.action,
                       .open(try XCTUnwrap(r.dmgURL)))
        let noDmg = Release(version: "0.6.0", pageURL: r.pageURL, dmgURL: nil)
        XCTAssertEqual(UpdateCheck.notice(for: noDmg, currentVersion: "0.5.2", source: .dmg, dismissedVersion: nil)?.action,
                       .open(r.pageURL))
    }

    func testNoNoticeWhenPinnedDismissedOrCurrent() throws {
        let r = try UpdateCheck.release(fromGitHubJSON: Data(json.utf8))
        XCTAssertNil(UpdateCheck.notice(for: r, currentVersion: "0.5.2", source: .pinnedHomebrew, dismissedVersion: nil))
        XCTAssertNil(UpdateCheck.notice(for: r, currentVersion: "0.5.2", source: .dmg, dismissedVersion: "0.6.0"))
        XCTAssertNil(UpdateCheck.notice(for: r, currentVersion: "0.6.0", source: .dmg, dismissedVersion: nil))
    }

    func testDueWhenNeverCheckedAfterIntervalOrStampedInFuture() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(UpdateCheck.isDue(lastCheck: nil, now: now, interval: 86_400))
        XCTAssertFalse(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-3_600), now: now, interval: 86_400))
        XCTAssertTrue(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-86_400), now: now, interval: 86_400))
        XCTAssertTrue(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(3_600), now: now, interval: 86_400))
    }

    func testOnlyHTTPSLinksOpen() throws {
        XCTAssertTrue(UpdateCheck.isOpenable(try XCTUnwrap(URL(string: "https://github.com/vakharwalad23/tap-talk"))))
        XCTAssertFalse(UpdateCheck.isOpenable(try XCTUnwrap(URL(string: "http://example.com/TapTalk.dmg"))))
        XCTAssertFalse(UpdateCheck.isOpenable(try XCTUnwrap(URL(string: "file:///Applications/Calculator.app"))))
        XCTAssertFalse(UpdateCheck.isOpenable(try XCTUnwrap(URL(string: "x-apple.systempreferences:com.apple.preference"))))
    }
}
