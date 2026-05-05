import SwiftUI
import Carbon.HIToolbox

struct IntelligenceView: View {
    @ObservedObject private var settings = SettingsStore.shared

    // Dictionary editing
    @State private var addingSegment = false
    @State private var newSegmentName = ""
    @State private var expandedSegments: Set<String> = []

    // LLM
    @State private var llmApiKeyInput = ""
    @State private var llmApiKeySaved = false
    @State private var llmTestStatus: LLMTestStatus = .idle
    @State private var llmTestTask: Task<Void, Never>?

    // Local model + binary download
    @State private var localModelInstalled = false
    @State private var localBinaryInstalled = false
    @State private var localModelProgress: Double = 0
    @State private var localBinaryProgress: Double = 0
    @State private var localDownloadStatus: LocalDownloadStatus = .idle
    @State private var localDownloadTask: Task<Void, Never>?

    enum LocalDownloadStatus: Equatable {
        case idle, downloadingModel, downloadingBinary, ready, failed(String)
    }

    // Smart hotkey
    @State private var listeningSmartKey = false
    @State private var smartKeyCapture = KeyCapture()

    enum LLMTestStatus: Equatable {
        case idle, testing
        case success(String), failure(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pageHeader

                dictionarySection
                aiSection
                smartHotkeySection
            }
            .padding(24)
        }
        .background(AppTheme.windowBg)
        .onAppear {
            llmApiKeyInput = settings.llmApiKey
            localModelInstalled = AppController.shared.manager.isLlmInstalled(modelId: "qwen2.5-1.5b")
            localBinaryInstalled = LlamaServerManager.shared.isBinaryInstalled()
            if localModelInstalled && localBinaryInstalled { localDownloadStatus = .ready }
        }
        .onDisappear { smartKeyCapture.stop(); llmTestTask?.cancel(); localDownloadTask?.cancel() }
    }

    // MARK: Page header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Intelligence")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppTheme.primary)
            Text("Dictionary, AI rewriting, and smart hotkey")
                .font(.caption)
                .foregroundStyle(AppTheme.tertiary)
        }
        .padding(.bottom, 20)
    }

    // MARK: Dictionary

    private var dictionarySection: some View {
        intelligenceSection("Word Dictionary") {
            if settings.dictionarySegments.isEmpty && !addingSegment {
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
                VStack(alignment: .leading, spacing: 6) {
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
                get: { settings.dictionarySegments[segIdx].entries[entryIdx].from },
                set: { settings.dictionarySegments[segIdx].entries[entryIdx].from = $0 }
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
                get: { settings.dictionarySegments[segIdx].entries[entryIdx].to },
                set: { settings.dictionarySegments[segIdx].entries[entryIdx].to = $0 }
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

    // MARK: AI Rewriting

    private var aiSection: some View {
        intelligenceSection("AI Rewriting") {
            settingRow("Enable AI rewriting") {
                Toggle("", isOn: $settings.llmEnabled).labelsHidden()
            }

            if settings.llmEnabled {
                Divider().background(AppTheme.divider)

                backendPicker

                if settings.llmBackend == .custom {
                    Divider().background(AppTheme.divider)
                    customEndpointFields
                } else {
                    Divider().background(AppTheme.divider)
                    localBackendSection
                }
            }
        }
    }

    private var backendPicker: some View {
        HStack(spacing: 8) {
            backendButton(.custom, label: "Custom Endpoint", sub: "Ollama, LM Studio, OpenAI")
            backendButton(.local,  label: "Local (Qwen)",    sub: "On-device, private")
        }
    }

    private func backendButton(_ backend: LLMBackend, label: String, sub: String) -> some View {
        let active = settings.llmBackend == backend
        return Button(action: { settings.llmBackend = backend }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 12, weight: .semibold))
                Text(sub).font(.system(size: 10))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(active ? AppTheme.accent : AppTheme.sectionBg)
            .foregroundStyle(active ? AppTheme.windowBg : AppTheme.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.divider, lineWidth: active ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private var customEndpointFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Base URL")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.secondary)
                TextField("http://localhost:11434", text: $settings.llmEndpointURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .background(AppTheme.windowBg)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.divider, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Model")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.secondary)
                TextField("llama3.2", text: $settings.llmModel)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .background(AppTheme.windowBg)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.divider, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("API Key (optional)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.secondary)

                HStack(spacing: 8) {
                    SecureField("sk-… or leave empty for local", text: $llmApiKeyInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(8)
                        .background(AppTheme.windowBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.divider, lineWidth: 1))

                    Button(llmApiKeySaved ? "Saved ✓" : "Save") {
                        settings.llmApiKey = llmApiKeyInput
                        llmApiKeySaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { llmApiKeySaved = false }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(llmApiKeySaved ? AppTheme.success : AppTheme.accent)
                    .controlSize(.small)
                    .disabled(llmApiKeyInput == settings.llmApiKey)
                }
            }

            HStack(spacing: 10) {
                Button(action: runLLMTest) {
                    HStack(spacing: 6) {
                        if llmTestStatus == .testing {
                            ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "network").font(.system(size: 11))
                        }
                        Text(llmTestStatus == .testing ? "Testing…" : "Test connection")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.bordered)
                .foregroundStyle(AppTheme.primary)
                .disabled(settings.llmEndpointURL.isEmpty || llmTestStatus == .testing)

                llmTestBadge
            }
        }
    }

    private var localBackendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Model row
            localAssetRow(
                title: "Qwen 2.5 1.5B Instruct",
                subtitle: "~986 MB · Whisper-quality on-device",
                installed: localModelInstalled,
                progress: localDownloadStatus == .downloadingModel ? localModelProgress : nil,
                onDownload: { startLocalDownload(phase: .model) },
                onDelete: { deleteLocalModel() },
                downloading: localDownloadStatus == .downloadingModel
            )

            Divider().background(AppTheme.divider)

            // Server binary row
            localAssetRow(
                title: "llama-server binary",
                subtitle: "~30 MB · Metal-accelerated inference",
                installed: localBinaryInstalled,
                progress: localDownloadStatus == .downloadingBinary ? localBinaryProgress : nil,
                onDownload: { startLocalDownload(phase: .binary) },
                onDelete: { deleteLlamaBinary() },
                downloading: localDownloadStatus == .downloadingBinary
            )

            if case .ready = localDownloadStatus {
                Label("Ready · using Metal GPU", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.success)
            }

            if case .failed(let msg) = localDownloadStatus {
                Label(msg, systemImage: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.danger)
            }
        }
    }

    private func localAssetRow(
        title: String,
        subtitle: String,
        installed: Bool,
        progress: Double?,
        onDownload: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        downloading: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiary)
                }
                Spacer()
                if installed {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.success)
                            .font(.system(size: 13))
                        Button("Delete", action: onDelete)
                            .foregroundStyle(AppTheme.danger)
                            .font(.system(size: 12))
                            .buttonStyle(.plain)
                    }
                } else if downloading {
                    Button("Cancel") {
                        localDownloadTask?.cancel()
                        localDownloadStatus = .idle
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundStyle(AppTheme.secondary)
                } else {
                    Button("Download", action: onDownload)
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.58, green: 0.42, blue: 1.0))
                        .controlSize(.small)
                }
            }

            if let p = progress {
                ProgressView(value: p)
                    .progressViewStyle(.linear)
                    .tint(Color(red: 0.58, green: 0.42, blue: 1.0))
                Text(String(format: "%.0f%%", p * 100))
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiary)
            }
        }
    }

    private enum LocalPhase { case model, binary }

    private func startLocalDownload(phase: LocalPhase) {
        let manager = AppController.shared.manager
        localDownloadTask?.cancel()
        localDownloadTask = Task {
            do {
                if phase == .model && !localModelInstalled {
                    await MainActor.run { localDownloadStatus = .downloadingModel; localModelProgress = 0 }
                    let cb = LlmProgressBridge { info in
                        let p = info.totalBytes > 0 ? Double(info.bytesDownloaded) / Double(info.totalBytes) : 0
                        DispatchQueue.main.async { self.localModelProgress = p }
                    }
                    // downloadLlm is blocking Rust — run off MainActor
                    try await Task.detached { try manager.downloadLlm(modelId: "qwen2.5-1.5b", callback: cb) }.value
                    await MainActor.run { localModelInstalled = true }
                }

                if phase == .binary && !localBinaryInstalled {
                    await MainActor.run { localDownloadStatus = .downloadingBinary; localBinaryProgress = 0 }
                    try await LlamaServerManager.shared.downloadBinary(
                        to: LlamaServerManager.shared.binaryPath(),
                        onProgress: { p in DispatchQueue.main.async { self.localBinaryProgress = p } }
                    )
                    await MainActor.run { localBinaryInstalled = true }
                }

                await MainActor.run {
                    if localModelInstalled && localBinaryInstalled {
                        localDownloadStatus = .ready
                    } else {
                        localDownloadStatus = .idle
                    }
                }
            } catch {
                await MainActor.run { localDownloadStatus = .failed(error.localizedDescription) }
            }
        }
    }

    private func deleteLocalModel() {
        LlamaServerManager.shared.stop()
        try? AppController.shared.manager.deleteLlm(modelId: "qwen2.5-1.5b")
        localModelInstalled = false
        if localDownloadStatus == .ready { localDownloadStatus = .idle }
    }

    private func deleteLlamaBinary() {
        LlamaServerManager.shared.stop()
        let path = LlamaServerManager.shared.binaryPath()
        try? FileManager.default.removeItem(atPath: path)
        localBinaryInstalled = false
        if localDownloadStatus == .ready { localDownloadStatus = .idle }
    }

    @ViewBuilder
    private var llmTestBadge: some View {
        switch llmTestStatus {
        case .idle, .testing:
            EmptyView()
        case .success(let msg):
            Label(msg, systemImage: "checkmark.circle.fill")
                .font(.system(size: 11)).foregroundStyle(AppTheme.success)
        case .failure(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .font(.system(size: 11)).foregroundStyle(AppTheme.danger)
        }
    }

    private func runLLMTest() {
        llmTestTask?.cancel()
        llmTestStatus = .testing
        let snap = settings
        llmTestTask = Task.detached {
            do {
                let msg = try await testLLMConnection(settings: snap)
                await MainActor.run { llmTestStatus = .success(msg) }
            } catch {
                await MainActor.run { llmTestStatus = .failure(error.localizedDescription) }
            }
        }
    }

    // MARK: Smart Hotkey

    private var smartHotkeySection: some View {
        intelligenceSection("Smart Hotkey") {
            settingRow("Enable smart hotkey") {
                Toggle("", isOn: Binding(
                    get: { settings.smartHotkeyEnabled },
                    set: {
                        settings.smartHotkeyEnabled = $0
                        AppController.shared.setupHotkey()
                    }
                ))
                .labelsHidden()
            }

            if settings.smartHotkeyEnabled {
                Divider().background(AppTheme.divider)
                settingRow("Smart key") {
                    Button(listeningSmartKey ? "Press a key…" : keyName(settings.smartHotkeyCode)) {
                        startListeningSmartKey()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(listeningSmartKey ? .orange : AppTheme.primary)
                }
                Divider().background(AppTheme.divider)
                Button("Reset to Left ⌥") { applySmartKey(UInt16(kVK_Option)) }
                    .foregroundStyle(AppTheme.secondary)
                    .font(.callout)

                Text("Hold smart key → transcribe + AI rewrite based on active app")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiary)
                    .padding(.top, 2)
            }
        }
    }

    private func startListeningSmartKey() {
        listeningSmartKey = true
        smartKeyCapture.start { code in
            applySmartKey(code)
            listeningSmartKey = false
        }
    }

    private func applySmartKey(_ code: UInt16) {
        settings.smartHotkeyCode = code
        AppController.shared.setupHotkey()
    }

    private func keyName(_ code: UInt16) -> String { AppTheme.keyLabel(for: code) }

    // MARK: Layout helpers

    private func intelligenceSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
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
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.divider, lineWidth: 1))
        }
        .padding(.bottom, 20)
    }

    private func settingRow<Content: View>(_ label: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.primary)
            Spacer()
            trailing()
        }
    }
}
