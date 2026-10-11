import CoreAudio
import XCTest
@testable import TapTalkAudio

final class MicrophoneSelectionTests: XCTestCase {
    private let usb = InputDeviceInfo(id: 5, isBuiltIn: false)
    private let builtIn = InputDeviceInfo(id: 7, isBuiltIn: true)

    func testBuiltInPreferencePinsTheBuiltInMicrophone() {
        XCTAssertEqual(MicrophoneSelection.device(for: .builtIn, among: [usb, builtIn], systemDefault: 5), 7)
    }

    func testBuiltInPreferenceFallsBackToTheSystemDefaultWhenThereIsNone() {
        XCTAssertEqual(MicrophoneSelection.device(for: .builtIn, among: [usb], systemDefault: 5), 5)
    }

    func testSystemDefaultPreferenceFollowsTheDefaultEvenWithABuiltInPresent() {
        XCTAssertEqual(MicrophoneSelection.device(for: .systemDefault, among: [usb, builtIn], systemDefault: 5), 5)
    }

    func testNoDefaultAndNoBuiltInMeansNoDevice() {
        XCTAssertNil(MicrophoneSelection.device(for: .builtIn, among: [usb], systemDefault: kAudioObjectUnknown))
        XCTAssertNil(MicrophoneSelection.device(for: .systemDefault, among: [], systemDefault: kAudioObjectUnknown))
    }

    func testChangingThePreferenceSchedulesOneRebuild() {
        let capture = MicrophoneCapture()
        _ = capture.rebuild.claim()
        capture.setInputPreference(.builtIn)
        XCTAssertTrue(capture.rebuild.claim())
        capture.setInputPreference(.builtIn)
        XCTAssertFalse(capture.rebuild.claim())
        capture.setInputPreference(.systemDefault)
        XCTAssertTrue(capture.rebuild.claim())
    }

    func testRecorderPassesThePreferenceToItsCapture() {
        let capture = FakeCapture()
        let recorder = DictationRecorder(capture: capture)
        recorder.setInputPreference(.builtIn)
        XCTAssertEqual(capture.preference, .builtIn)
    }
}
