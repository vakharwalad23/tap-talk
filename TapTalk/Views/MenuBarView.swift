import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuRow(title: "Open TapTalk", systemImage: "macwindow", shortcut: "o") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider()
                .padding(.vertical, 4)

            MenuRow(title: "Quit TapTalk", systemImage: "power", shortcut: "q") {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(width: 200)
    }
}

// Menu row with a native-style hover highlight (the .window MenuBarExtra style
// doesn't provide one for custom buttons).
private struct MenuRow: View {
    let title: String
    let systemImage: String
    let shortcut: KeyEquivalent
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.accentColor : Color.clear)
                )
                .foregroundStyle(isHovered ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
