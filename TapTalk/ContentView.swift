import SwiftUI

enum NavItem: String, CaseIterable {
    case record   = "Record"
    case models   = "Models"
    case settings = "Settings"
    case privacy  = "Privacy"
    case about    = "About"
}

struct ContentView: View {
    @State private var selection: NavItem = .record
    @State private var recorder = Recorder()
    @State private var transcriber = Transcriber()
    @State private var manager: ModelManager

    init() {
        _manager = State(initialValue: ModelManager(modelsDir: Self.modelsDirectory()))
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $selection)
            Divider()
                .background(AppTheme.divider)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.windowBg)
        .frame(minWidth: 520, minHeight: 420)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .record:
            RecordView(recorder: recorder, transcriber: transcriber, manager: manager)
        case .models:
            ModelsPage(manager: manager, onModelReady: { selection = .record })
        case .settings:
            SettingsView()
        case .privacy:
            PrivacyView()
        case .about:
            AboutView()
        }
    }

    static func modelsDirectory() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("talk.tap.app/models")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }
}

struct SidebarView: View {
    @Binding var selection: NavItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TapTalk")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.primary)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 16)

            ForEach(NavItem.allCases, id: \.self) { item in
                navButton(item)
            }

            Spacer()
        }
        .frame(width: 140)
        .background(AppTheme.sidebarBg)
    }

    private func navButton(_ item: NavItem) -> some View {
        Button(action: { selection = item }) {
            Text(item.rawValue)
                .font(.system(size: 13, weight: selection == item ? .medium : .regular))
                .foregroundStyle(selection == item ? AppTheme.primary : AppTheme.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    selection == item
                        ? AppTheme.accent.opacity(0.06)
                        : Color.clear
                )
        }
        .buttonStyle(.plain)
    }
}

struct ModelsPage: View {
    let manager: ModelManager
    var onModelReady: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Models")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppTheme.primary)

            ModelDownloader(manager: manager, onModelChanged: onModelReady)

            Spacer()
        }
        .padding(24)
        .background(AppTheme.windowBg)
    }
}
