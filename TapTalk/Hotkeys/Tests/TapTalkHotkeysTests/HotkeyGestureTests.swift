import XCTest
@testable import TapTalkHotkeys

final class HotkeyGestureTests: XCTestCase {
    func testHoldPressStartsAndReleaseStops() {
        var g = HotkeyGesture(mode: .hold)
        XCTAssertEqual(g.handle(.hotkeyDown(.dictation, at: 0), isRecording: false), .start(.dictation))
        XCTAssertEqual(g.handle(.hotkeyUp(.dictation), isRecording: true), .stop)
    }

    func testToggleReleaseKeepsRecording() {
        var g = HotkeyGesture(mode: .toggle)
        XCTAssertEqual(g.handle(.hotkeyDown(.dictation, at: 0), isRecording: false), .start(.dictation))
        XCTAssertNil(g.handle(.hotkeyUp(.dictation), isRecording: true))
        XCTAssertEqual(g.handle(.hotkeyDown(.dictation, at: 5), isRecording: true), .stop)
        XCTAssertNil(g.handle(.hotkeyUp(.dictation), isRecording: false))
    }

    func testToggleEitherKeyStops() {
        var g = HotkeyGesture(mode: .toggle)
        XCTAssertEqual(g.handle(.hotkeyDown(.smart, at: 0), isRecording: false), .start(.smart))
        XCTAssertNil(g.handle(.hotkeyUp(.smart), isRecording: true))
        XCTAssertEqual(g.handle(.hotkeyDown(.dictation, at: 3), isRecording: true), .stop)
    }

    func testShortcutInsideWindowCancelsSilently() {
        for mode in HotkeyMode.allCases {
            var g = HotkeyGesture(mode: mode)
            XCTAssertEqual(g.handle(.hotkeyDown(.dictation, at: 10.0), isRecording: false), .start(.dictation))
            XCTAssertEqual(g.handle(.otherInput(at: 10.3), isRecording: true), .cancelShortcut, "\(mode)")
            XCTAssertNil(g.handle(.hotkeyUp(.dictation), isRecording: false), "\(mode)")
        }
    }

    func testInputAfterWindowIsIgnored() {
        var g = HotkeyGesture(mode: .hold)
        _ = g.handle(.hotkeyDown(.dictation, at: 10.0), isRecording: false)
        XCTAssertNil(g.handle(.otherInput(at: 11.5), isRecording: true))
        XCTAssertEqual(g.handle(.hotkeyUp(.dictation), isRecording: true), .stop)
    }

    func testWindowBoundary() {
        var g = HotkeyGesture(mode: .hold)
        _ = g.handle(.hotkeyDown(.dictation, at: 10.0), isRecording: false)
        let edge = 10.0 + HotkeyGesture.shortcutWindow
        XCTAssertEqual(g.handle(.otherInput(at: edge), isRecording: true), .cancelShortcut)
    }

    func testFirstInputWhileToggledOnPausesOnce() {
        var g = HotkeyGesture(mode: .toggle)
        _ = g.handle(.hotkeyDown(.dictation, at: 0), isRecording: false)
        _ = g.handle(.hotkeyUp(.dictation), isRecording: true)
        XCTAssertEqual(g.handle(.otherInput(at: 4), isRecording: true), .pauseLiveTyping)
        XCTAssertNil(g.handle(.otherInput(at: 5), isRecording: true))
    }

    // A click that moves the caret during a long first press must also freeze live typing.
    func testToggleInputAfterWindowWhilePressingPausesOnce() {
        var g = HotkeyGesture(mode: .toggle)
        _ = g.handle(.hotkeyDown(.dictation, at: 0), isRecording: false)
        XCTAssertEqual(g.handle(.otherInput(at: 1.5), isRecording: true), .pauseLiveTyping)
        XCTAssertNil(g.handle(.hotkeyUp(.dictation), isRecording: true))
        XCTAssertNil(g.handle(.otherInput(at: 4), isRecording: true))
        XCTAssertEqual(g.handle(.hotkeyDown(.dictation, at: 6), isRecording: true), .stop)
    }

    func testEscapeCancelsAnyRecording() {
        var pressing = HotkeyGesture(mode: .hold)
        _ = pressing.handle(.hotkeyDown(.dictation, at: 0), isRecording: false)
        XCTAssertEqual(pressing.handle(.escape, isRecording: true), .cancel)

        var toggled = HotkeyGesture(mode: .toggle)
        _ = toggled.handle(.hotkeyDown(.dictation, at: 0), isRecording: false)
        _ = toggled.handle(.hotkeyUp(.dictation), isRecording: true)
        XCTAssertEqual(toggled.handle(.escape, isRecording: true), .cancel)

        var elsewhere = HotkeyGesture(mode: .hold)
        XCTAssertEqual(elsewhere.handle(.escape, isRecording: true), .cancel)

        var notRecording = HotkeyGesture(mode: .toggle)
        XCTAssertNil(notRecording.handle(.escape, isRecording: false))
    }

    func testReleaseAfterRecordingEndedElsewhereDoesNothing() {
        var g = HotkeyGesture(mode: .hold)
        _ = g.handle(.hotkeyDown(.dictation, at: 0), isRecording: false)
        XCTAssertNil(g.handle(.hotkeyUp(.dictation), isRecording: false))
    }

    func testToggledOnResetsWhenRecordingEndedElsewhere() {
        var g = HotkeyGesture(mode: .toggle)
        _ = g.handle(.hotkeyDown(.dictation, at: 0), isRecording: false)
        _ = g.handle(.hotkeyUp(.dictation), isRecording: true)
        XCTAssertEqual(g.handle(.hotkeyDown(.dictation, at: 9), isRecording: false), .start(.dictation))
    }

    func testToggleDownWhileRecordingElsewhereStops() {
        var g = HotkeyGesture(mode: .toggle)
        XCTAssertEqual(g.handle(.hotkeyDown(.dictation, at: 0), isRecording: true), .stop)
    }

    func testHoldDownWhileRecordingElsewhereIgnored() {
        var g = HotkeyGesture(mode: .hold)
        XCTAssertNil(g.handle(.hotkeyDown(.dictation, at: 0), isRecording: true))
    }

    func testOtherKeyDownWhilePressingIgnored() {
        var g = HotkeyGesture(mode: .hold)
        _ = g.handle(.hotkeyDown(.dictation, at: 0), isRecording: false)
        XCTAssertNil(g.handle(.hotkeyDown(.smart, at: 0.2), isRecording: true))
    }
}
