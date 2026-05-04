import SwiftUI

struct ContentView: View {
    @State private var selectedTab = "main"
    @State private var recorder = Recorder()
    @State private var transcriber = Transcriber()
    @State private var manager: ModelManager

    init() {
        _manager = State(initialValue: ModelManager(modelsDir: Self.modelsDirectory()))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            MainView(recorder: recorder, transcriber: transcriber, manager: manager)
                .tabItem { Label("Record", systemImage: "mic") }
                .tag("main")

            modelsTab
                .tabItem { Label("Models", systemImage: "arrow.down.circle") }
                .tag("models")
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private var modelsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Models")
                .font(.title2)
                .fontWeight(.bold)

            ModelDownloader(manager: manager) {
                selectedTab = "main"
            }

            Spacer()
        }
        .padding(24)
    }

    static func modelsDirectory() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("talk.tap.app/models")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }
}
