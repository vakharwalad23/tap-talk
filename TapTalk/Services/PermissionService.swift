import AVFoundation
import Cocoa

/// Microphone and Accessibility permission state, and the actions that grant or repair them.
/// Nothing here prompts on its own: every prompt follows a click on the setup card.
@MainActor
final class PermissionService: ObservableObject {
    static let shared = PermissionService()

    enum MicrophoneAccess { case notDetermined, granted, denied }

    @Published private(set) var microphone: MicrophoneAccess
    @Published private(set) var isRepairingAccessibility = false

    private static let microphoneSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    private static let accessibilitySettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    nonisolated static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    private init() { microphone = Self.currentMicrophoneAccess() }

    /// Re-reads the microphone grant; a fresh grant warms the audio path so the next press records.
    func refresh() {
        let previous = microphone
        microphone = Self.currentMicrophoneAccess()
        if previous != .granted, microphone == .granted {
            AppController.shared.warmUpAudioStream()
        }
    }

    /// Shows the system microphone prompt. A denial is the user's choice and is never reset.
    func requestMicrophone() {
        guard microphone == .notDetermined else { return }
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor in PermissionService.shared.refresh() }
        }
    }

    func openMicrophoneSettings() {
        open(Self.microphoneSettingsURL)
    }

    /// Clears any Accessibility entry left by an earlier build, then asks again. An unsigned or
    /// re-signed build matches no stale entry, which otherwise sits switched on in System Settings
    /// while the hotkey stays dead.
    func repairAccessibility() {
        guard !isRepairingAccessibility else { return }
        isRepairingAccessibility = true
        let bundleID = Bundle.main.bundleIdentifier ?? "talk.tap.app"
        Task {
            await Task.detached(priority: .userInitiated) {
                let reset = Process()
                reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                reset.arguments = ["reset", "Accessibility", bundleID]
                // Exit status is ignored: resetting a bundle with no entry is harmless.
                try? reset.run()
                reset.waitUntilExit()
            }.value
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            open(Self.accessibilitySettingsURL)
            // The reset revoked any grant this process held; this arms the poller that notices the new one.
            AppController.shared.setupHotkey()
            isRepairingAccessibility = false
        }
    }

    /// Relaunches TapTalk. A new instance is requested explicitly; asking for the running app
    /// only re-activates it, and terminating first can leave nothing running.
    func restartApp() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func currentMicrophoneAccess() -> MicrophoneAccess {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }
}
