import SwiftUI
import Carbon.HIToolbox

struct CloudModelSpec {
    let id: String
    let name: String
    let provider: String
    let available: Bool
}

private let cloudModels: [CloudModelSpec] = [
    CloudModelSpec(id: "whisper-1",           name: "Whisper",           provider: "OpenAI",     available: true),
    CloudModelSpec(id: "gpt-4o-transcribe",   name: "GPT-4o Transcribe", provider: "OpenAI",     available: false),
    CloudModelSpec(id: "gemini-flash",        name: "Gemini Flash",      provider: "Google",     available: false),
    CloudModelSpec(id: "nova-3",              name: "Nova-3",            provider: "Deepgram",   available: false),
]

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var listening = false
    @State private var keyCapture = KeyCapture()
    @State private var apiKeyInput = ""
    @State private var apiKeySaved = false
    @State private var apiKeySaveError: String?
    @State private var testStatus: TestStatus = .idle
    @State private var testTask: Task<Void, Never>?

    enum TestStatus: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pageHeader

                SettingsSection("Transcription engine") {
                    enginePicker
                    if settings.transcriptionEngine == .local {
                        Divider().background(AppTheme.divider)
                        localEnginePicker
                        // Live-typing toggle is gated on the engine supporting streaming
                        // AND the realtime model being installed (EOU 120M for Parakeet).
                        if settings.localEngine.supportsStreaming, EouDownloadManager.shared.installed {
                            Divider().background(AppTheme.divider)
                            streamingToggle
                        }
                    }
                    if settings.transcriptionEngine == .cloud {
                        Divider().background(AppTheme.divider)
                        cloudModelGrid
                        Divider().background(AppTheme.divider)
                        apiKeyRow
                    }
                }

                SettingsSection("Startup") {
                    SettingRow("Launch at login") {
                        Toggle("", isOn: $settings.launchAtLogin)
                            .labelsHidden()
                    }
                }

                SettingsSection("Hotkey") {
                    SettingRow("Push-to-talk key") {
                        Button(listening ? "Press a key..." : keyName(settings.hotkeyCode)) {
                            startListening()
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(listening ? .orange : AppTheme.primary)
                    }
                    Divider().background(AppTheme.divider)
                    Button("Reset to Right Cmd") { applyKey(UInt16(kVK_RightCommand)) }
                        .foregroundStyle(AppTheme.secondary)
                        .font(.callout)
                }
            }
            .padding(24)
        }
        .background(AppTheme.windowBg)
        .onAppear { apiKeyInput = settings.apiKey }
        .onDisappear { keyCapture.stop(); testTask?.cancel() }
    }

    // MARK: Page header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppTheme.primary)
            Text("Engine, hotkey, and startup")
                .font(.caption)
                .foregroundStyle(AppTheme.tertiary)
        }
        .padding(.bottom, 20)
    }

    // MARK: Engine picker

    private var enginePicker: some View {
        HStack(spacing: 8) {
            engineButton(.local, label: "Local", sub: "On-device, private")
            engineButton(.cloud, label: "Cloud", sub: "OpenAI Whisper API")
        }
    }

    private func engineButton(_ engine: TranscriptionEngine, label: String, sub: String) -> some View {
        let active = settings.transcriptionEngine == engine
        return Button(action: { settings.transcriptionEngine = engine }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                Text(sub)
                    .font(.system(size: 10))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(active ? AppTheme.accent : AppTheme.sectionBg)
            .foregroundStyle(active ? AppTheme.windowBg : AppTheme.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.divider, lineWidth: active ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Streaming toggle (only for engines that can do live partial transcription)

    private var streamingToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            SettingRow("Live typing (stream as you speak)") {
                Toggle("", isOn: $settings.streamingEnabled).labelsHidden()
            }
            Text("Types words live into the focused app as Parakeet recognizes them. Uses the Parakeet Realtime (EOU) model. Off in Smart Mode.")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Local engine picker

    private var localEnginePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local model")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: LocalEngine.allCases.count), spacing: 8) {
                localEngineButton(.parakeet, label: LocalEngine.parakeet.displayName, sub: LocalEngine.parakeet.languageSummary)
                localEngineButton(.nemotron, label: LocalEngine.nemotron.displayName, sub: LocalEngine.nemotron.languageSummary)
            }

            // Only Nemotron produces Devanagari, so the choice is meaningless for Parakeet.
            if settings.localEngine == .nemotron {
                Divider().background(AppTheme.divider)
                hindiScriptPicker
            }
        }
        .padding(.top, 2)
    }

    private var hindiScriptPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hindi script")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.secondary)
            HStack(spacing: 8) {
                ForEach(HindiScript.allCases, id: \.self) { script in
                    scriptButton(script)
                }
            }
            Text(scriptHint)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // The picker is only meaningful for Hindi on Nemotron via the smart hotkey. Say which of
    // those is missing rather than leaving a control that quietly does nothing.
    private var scriptHint: String {
        guard settings.hindiScript == .roman else {
            return "Devanagari is what the model produces. Roman writes it the way people type in chat."
        }
        if settings.selectedLanguage != AppContextService.hindiLanguageCode {
            return "Roman applies to Hindi only - pick Hindi in the Record tab. Other languages are pasted as the model produces them."
        }
        return "Roman writes Hindi the way people type it in chat: main kal aaunga. Produced by the rewrite model, so it needs the smart hotkey."
    }

    private func scriptButton(_ script: HindiScript) -> some View {
        let active = settings.hindiScript == script
        return Button(action: { settings.hindiScript = script }) {
            Text(script.label)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(active ? AppTheme.accent : AppTheme.sectionBg)
                .foregroundStyle(active ? AppTheme.windowBg : AppTheme.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.divider, lineWidth: active ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private func localEngineButton(_ le: LocalEngine, label: String, sub: String) -> some View {
        let active = settings.localEngine == le
        return Button(action: { settings.localEngine = le }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                Text(sub)
                    .font(.system(size: 10))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(active ? AppTheme.accent : AppTheme.sectionBg)
            .foregroundStyle(active ? AppTheme.windowBg : AppTheme.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.divider, lineWidth: active ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Cloud model grid

    private var cloudModelGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(cloudModels, id: \.id) { model in
                    cloudModelTile(model)
                }
            }
        }
        .padding(.top, 2)
    }

    private func cloudModelTile(_ model: CloudModelSpec) -> some View {
        let selected = settings.cloudModel == model.id && model.available

        return Button(action: {
            guard model.available else { return }
            settings.cloudModel = model.id
        }) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.name)
                        .font(.system(size: 11, weight: .semibold))
                    Text(model.provider)
                        .font(.system(size: 10))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(selected ? AppTheme.accent : AppTheme.windowBg)
                .foregroundStyle(
                    model.available
                        ? (selected ? AppTheme.windowBg : AppTheme.primary)
                        : AppTheme.tertiary
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selected ? AppTheme.accent : AppTheme.divider, lineWidth: 1)
                )
                .opacity(model.available ? 1.0 : 0.6)

                if !model.available {
                    Text("Soon")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(AppTheme.windowBg)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(AppTheme.tertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!model.available)
    }

    // MARK: API key + test

    private var apiKeyRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OpenAI API key")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.secondary)

            HStack(spacing: 8) {
                SecureField("sk-...", text: $apiKeyInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .background(AppTheme.windowBg)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppTheme.divider, lineWidth: 1)
                    )

                Button(apiKeySaved ? "Saved" : "Save") {
                    do {
                        try KeychainService.save(key: apiKeyInput, account: "openai-api-key")
                        settings.apiKey = apiKeyInput
                        apiKeySaved = true
                        apiKeySaveError = nil
                        testStatus = .idle
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { apiKeySaved = false }
                    } catch {
                        apiKeySaveError = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(apiKeySaved ? AppTheme.success : AppTheme.accent)
                .controlSize(.small)
                .disabled(apiKeyInput == settings.apiKey || apiKeyInput.isEmpty)
            }

            if let err = apiKeySaveError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.danger)
            }

            HStack(spacing: 10) {
                Button(action: runConnectionTest) {
                    HStack(spacing: 6) {
                        if testStatus == .testing {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "network")
                                .font(.system(size: 11))
                        }
                        Text(testStatus == .testing ? "Testing..." : "Test connection")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.bordered)
                .foregroundStyle(AppTheme.primary)
                .disabled(settings.apiKey.isEmpty || testStatus == .testing)

                testStatusBadge
            }
        }
    }

    @ViewBuilder
    private var testStatusBadge: some View {
        switch testStatus {
        case .idle:
            EmptyView()
        case .testing:
            EmptyView()
        case .success(let msg):
            Label(msg, systemImage: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.success)
        case .failure(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.danger)
        }
    }

    private func runConnectionTest() {
        testTask?.cancel()
        testStatus = .testing
        let key = settings.apiKey
        testTask = Task.detached {
            do {
                let result = try testCloudConnection(apiKey: key)
                await MainActor.run { testStatus = .success(result) }
            } catch {
                await MainActor.run { testStatus = .failure(error.localizedDescription) }
            }
        }
    }

    // MARK: Shared helpers



    private func startListening() {
        listening = true
        keyCapture.start { code in
            applyKey(code)
            listening = false
        }
    }

    private func applyKey(_ code: UInt16) {
        settings.hotkeyCode = code
        AppController.shared.setupHotkey()
    }

    private func keyName(_ code: UInt16) -> String { AppTheme.keyLabel(for: code) }
}
