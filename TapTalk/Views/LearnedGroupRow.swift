import SwiftUI
import TapTalkLearning

/// The Learned group on Words: fixes TapTalk learned, shown and edited like a dictionary segment.
struct LearnedGroupRow: View {
    @ObservedObject private var learned = LearnedCorrections.shared
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: { isExpanded.toggle() }) {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppTheme.tertiary)
                        Text("Learned")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.primary)
                        Text("\(learned.state.rules.count) entries")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.tertiary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { learned.state.isEnabled },
                    set: { learned.setEnabled($0) }
                ))
                .labelsHidden()
            }

            if isExpanded {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(learned.state.rules) { rule in
                        ruleRow(rule)
                    }
                }
                .padding(.leading, 20)
            }
        }
    }

    private func ruleRow(_ rule: LearnedRule) -> some View {
        HStack(spacing: 8) {
            ruleField("From", text: Binding(
                get: { rule.from },
                set: { learned.update(ruleID: rule.id, from: $0, to: rule.to) }
            ))

            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.tertiary)

            ruleField("To", text: Binding(
                get: { rule.to },
                set: { learned.update(ruleID: rule.id, from: rule.from, to: $0) }
            ))

            // Removing also keeps TapTalk from learning the same fix again.
            Button(action: { learned.remove(ruleID: rule.id) }) {
                Image(systemName: "minus.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.danger.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
    }

    private func ruleField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .frame(maxWidth: .infinity)
            .padding(6)
            .background(AppTheme.windowBg)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(AppTheme.divider, lineWidth: 1))
    }
}
