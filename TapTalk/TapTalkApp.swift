import SwiftUI

@main
struct TapTalkApp: App {
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("TapTalk", systemImage: "mic.fill") {
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
