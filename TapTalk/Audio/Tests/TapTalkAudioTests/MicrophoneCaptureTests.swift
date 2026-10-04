import AVFoundation
import XCTest
@testable import TapTalkAudio

final class MicrophoneCaptureTests: XCTestCase {
    func testRebuildIsClaimedOnceUntilMarkedStale() {
        let flag = RebuildFlag()
        XCTAssertTrue(flag.claim())
        XCTAssertFalse(flag.claim())
        flag.markStale()
        XCTAssertTrue(flag.claim())
        XCTAssertFalse(flag.claim())
    }

    func testConfigurationChangeFromAnotherThreadMarksTheGraphStale() {
        let engine = AVAudioEngine()
        let flag = RebuildFlag()
        _ = flag.claim()
        let token = MicrophoneCapture.observeConfigurationChanges(of: engine, marking: flag)
        defer { NotificationCenter.default.removeObserver(token) }
        let handled = expectation(description: "configuration change handled")
        DispatchQueue.global().async {
            NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
            handled.fulfill()
        }
        wait(for: [handled], timeout: 2)
        XCTAssertTrue(flag.claim())
    }

    func testChangesOnOtherEnginesAreIgnored() {
        let observed = AVAudioEngine()
        let other = AVAudioEngine()
        let flag = RebuildFlag()
        _ = flag.claim()
        let token = MicrophoneCapture.observeConfigurationChanges(of: observed, marking: flag)
        defer { NotificationCenter.default.removeObserver(token) }
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: other)
        XCTAssertFalse(flag.claim())
        withExtendedLifetime(observed) {}
    }
}
