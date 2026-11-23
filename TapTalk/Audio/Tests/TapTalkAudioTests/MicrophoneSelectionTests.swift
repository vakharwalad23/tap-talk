import CoreAudio
import XCTest
@testable import TapTalkAudio

final class MicrophoneSelectionTests: XCTestCase {
    private let headset = InputDeviceInfo(id: 3, transport: kAudioDeviceTransportTypeBluetooth)
    private let headsetLE = InputDeviceInfo(id: 4, transport: kAudioDeviceTransportTypeBluetoothLE)
    private let usb = InputDeviceInfo(id: 5, transport: kAudioDeviceTransportTypeUSB)
    private let builtIn: AudioDeviceID = 7

    func testBluetoothDefaultWithLidOpenRecordsFromTheBuiltInMicrophone() {
        XCTAssertEqual(MicrophoneSelection.device(systemDefault: headset, builtIn: builtIn, isLidClosed: { false }), builtIn)
        XCTAssertEqual(MicrophoneSelection.device(systemDefault: headsetLE, builtIn: builtIn, isLidClosed: { false }), builtIn)
    }

    func testBluetoothDefaultWithLidClosedKeepsTheHeadset() {
        XCTAssertEqual(MicrophoneSelection.device(systemDefault: headset, builtIn: builtIn, isLidClosed: { true }), headset.id)
    }

    func testBluetoothDefaultWithoutABuiltInMicrophoneKeepsTheHeadset() {
        XCTAssertEqual(MicrophoneSelection.device(systemDefault: headset, builtIn: nil, isLidClosed: { false }), headset.id)
    }

    func testWiredDefaultIsRespectedAndNeverReadsTheLid() {
        let device = MicrophoneSelection.device(systemDefault: usb, builtIn: builtIn, isLidClosed: {
            XCTFail("lid state read for a wired microphone")
            return false
        })
        XCTAssertEqual(device, usb.id)
    }

    func testNoDefaultMeansNoDevice() {
        XCTAssertNil(MicrophoneSelection.device(systemDefault: nil, builtIn: builtIn, isLidClosed: { false }))
    }
}
