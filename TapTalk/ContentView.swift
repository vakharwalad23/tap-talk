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

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $selection)
            Divider()
                .background(AppTheme.divider)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.windowBg)
        .preferredColorScheme(.light)
        .frame(minWidth: 520, minHeight: 420)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .record:
            RecordView()
        case .models:
            ModelsPage(onModelReady: { selection = .record })
        case .settings:
            SettingsView()
        case .privacy:
            PrivacyView()
        case .about:
            AboutView()
        }
    }

    static func modelsDirectory() -> String {
        AppController.modelsDirectory()
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
                .padding(.vertical, 6)
                .background(
                    selection == item ? AppTheme.accent.opacity(0.07) : Color.clear
                )
        }
        .buttonStyle(.plain)
    }
}

struct ModelsPage: View {
    var onModelReady: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Models")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.primary)
                    Text("Run entirely on your device — no internet required.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.tertiary)
                }

                ModelDownloader(manager: AppController.shared.manager, onModelChanged: {
                    AppController.shared.refresh()
                    onModelReady()
                })

                Spacer()
            }
            .padding(24)
        }
        .background(AppTheme.windowBg)
    }
}
