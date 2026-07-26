import SwiftUI

/// The bordered, titled card every settings page is built from.
///
/// Both settings pages had their own byte-identical copy under different names, which is how the
/// two drifted apart by a line of formatting. One definition means a change to the card shape
/// lands everywhere at once.
struct SettingsSection<Content: View>: View {
    private let title: String
    private let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .background(AppTheme.sectionBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppTheme.divider, lineWidth: 1)
            )
        }
        .padding(.bottom, 20)
    }
}

/// A labelled row with its control pushed to the trailing edge.
struct SettingRow<Content: View>: View {
    private let label: String
    private let trailing: () -> Content

    init(_ label: String, @ViewBuilder trailing: @escaping () -> Content) {
        self.label = label
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.primary)
            Spacer()
            trailing()
        }
    }
}
