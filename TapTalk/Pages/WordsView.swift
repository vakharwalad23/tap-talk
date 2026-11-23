import SwiftUI

struct WordsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var learned = LearnedCorrections.shared

    @State private var addingSegment = false
    @State private var newSegmentName = ""
    @State private var expandedSegments: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pageHeader

                learningSection

                dictionarySection
            }
            .padding(24)
        }
        .background(AppTheme.windowBg)
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Words")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppTheme.primary)
            Text("Words TapTalk replaces after transcribing")
                .font(.caption)
                .foregroundStyle(AppTheme.tertiary)
        }
        .padding(.bottom, 20)
    }

    private var learningSection: some View {
        SettingsSection("Learning") {
            SettingRow("Learn from my corrections") {
                Toggle("", isOn: $settings.learnCorrections)
                    .labelsHidden()
            }
            Text("When you fix a word TapTalk typed, it learns the fix after you make it twice.")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dictionarySection: some View {
        SettingsSection("Word Dictionary") {
            // Shown only once something is learned; no placeholder before that.
            if !learned.state.rules.isEmpty {
                LearnedGroupRow()
                if !settings.dictionarySegments.isEmpty || addingSegment {
                    Divider().background(AppTheme.divider)
                }
            }

            if settings.dictionarySegments.isEmpty && !addingSegment && learned.state.rules.isEmpty {
                Text("No segments yet. Add one to replace words in every transcription.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(settings.dictionarySegments.indices, id: \.self) { idx in
                segmentRow(idx: idx)
                if idx < settings.dictionarySegments.count - 1 {
                    Divider().background(AppTheme.divider)
                }
            }

            if addingSegment {
                if !settings.dictionarySegments.isEmpty {
                    Divider().background(AppTheme.divider)
                }
                addSegmentRow
            }

            Button(action: { addingSegment = true; newSegmentName = "" }) {
                Label("Add Segment", systemImage: "plus")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private func segmentRow(idx: Int) -> some View {
        let segment = settings.dictionarySegments[idx]
        let isExpanded = expandedSegments.contains(segment.name)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: { toggleExpand(segment.name) }) {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppTheme.tertiary)
                        Text(segment.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.primary)
                        Text("\(segment.entries.count) entries")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.tertiary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { settings.dictionarySegments[idx].isEnabled },
                    set: { settings.dictionarySegments[idx].isEnabled = $0 }
                ))
                .labelsHidden()

                Button(action: { settings.dictionarySegments.remove(at: idx) }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.danger.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(settings.dictionarySegments[idx].entries.indices, id: \.self) { eIdx in
                        entryRow(segIdx: idx, entryIdx: eIdx)
                    }
                    addEntryButton(segIdx: idx)
                }
                .padding(.leading, 20)
            }
        }
    }

    private func entryRow(segIdx: Int, entryIdx: Int) -> some View {
        HStack(spacing: 8) {
            TextField("From", text: Binding(
                get: {
                    guard segIdx < settings.dictionarySegments.count,
                          entryIdx < settings.dictionarySegments[segIdx].entries.count
                    else { return "" }
                    return settings.dictionarySegments[segIdx].entries[entryIdx].from
                },
                set: {
                    guard segIdx < settings.dictionarySegments.count,
                          entryIdx < settings.dictionarySegments[segIdx].entries.count
                    else { return }
                    settings.dictionarySegments[segIdx].entries[entryIdx].from = $0
                }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .frame(maxWidth: .infinity)
            .padding(6)
            .background(AppTheme.windowBg)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(AppTheme.divider, lineWidth: 1))

            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.tertiary)

            TextField("To", text: Binding(
                get: {
                    guard segIdx < settings.dictionarySegments.count,
                          entryIdx < settings.dictionarySegments[segIdx].entries.count
                    else { return "" }
                    return settings.dictionarySegments[segIdx].entries[entryIdx].to
                },
                set: {
                    guard segIdx < settings.dictionarySegments.count,
                          entryIdx < settings.dictionarySegments[segIdx].entries.count
                    else { return }
                    settings.dictionarySegments[segIdx].entries[entryIdx].to = $0
                }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .frame(maxWidth: .infinity)
            .padding(6)
            .background(AppTheme.windowBg)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(AppTheme.divider, lineWidth: 1))

            Button(action: { settings.dictionarySegments[segIdx].entries.remove(at: entryIdx) }) {
                Image(systemName: "minus.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.danger.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
    }

    private func addEntryButton(segIdx: Int) -> some View {
        Button(action: {
            settings.dictionarySegments[segIdx].entries.append(
                DictionaryEntry(from: "", to: "")
            )
        }) {
            Label("Add entry", systemImage: "plus")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondary)
        }
        .buttonStyle(.plain)
    }

    private var addSegmentRow: some View {
        HStack(spacing: 8) {
            TextField("Segment name (e.g. Tech, Personal)", text: $newSegmentName)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(7)
                .background(AppTheme.windowBg)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.accent.opacity(0.5), lineWidth: 1))

            Button("Add") {
                let name = newSegmentName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                settings.dictionarySegments.append(
                    DictionarySegment(name: name, isEnabled: true, entries: [])
                )
                expandedSegments.insert(name)
                addingSegment = false
                newSegmentName = ""
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .controlSize(.small)
            .disabled(newSegmentName.trimmingCharacters(in: .whitespaces).isEmpty)

            Button("Cancel") { addingSegment = false }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private func toggleExpand(_ name: String) {
        if expandedSegments.contains(name) {
            expandedSegments.remove(name)
        } else {
            expandedSegments.insert(name)
        }
    }
}
