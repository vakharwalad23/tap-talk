import AppKit
import SwiftUI

@main
struct TapTalkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var recordingState = AppRecordingState.shared

    init() {
        // Setup runs at launch regardless of window state.
        // Dispatch ensures the main run loop is ready for Timer/hotkey registration.
        DispatchQueue.main.async {
            AppController.shared.setup()
        }
    }

    var body: some Scene {
        MenuBarExtra("TapTalk", systemImage: recordingState.isRecording ? "waveform.badge.mic" : "waveform") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: "main") {
            ContentView()
        }
        .defaultSize(width: 520, height: 480)
        .windowStyle(.hiddenTitleBar)
    }
}

// Shared observable for menu bar + pill feedback
final class AppRecordingState: ObservableObject {
    static let shared = AppRecordingState()
    @Published var isRecording = false
    private init() {}
}

// Stops the llama-server subprocess on quit so it doesn't outlive TapTalk and hold port 8899.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        LlamaServerManager.shared.stop()
    }
}
