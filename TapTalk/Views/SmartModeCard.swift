import SwiftUI

// Everything about Smart Mode on one card: the switch, what it does, and which model runs it.
// The switch also arms the Smart key; the key itself is chosen in Settings.
struct SmartModeCard: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var installer = LocalIntelligenceInstaller.shared

    @State private var llmApiKeyInput = ""
    @State private var llmApiKeySaved = false
    @State private var llmTestStatus: LLMTestStatus = .idle
    @State private var llmTestTask: Task<Void, Never>?

    enum LLMTestStatus: Equatable {
        case idle, testing
        case success(String), failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 7) {
                Text("Smart Mode")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                Spacer()
                Toggle("", isOn: $settings.llmEnabled).labelsHidden()
            }
            Text("Rewrites what you dictate with an AI model, on this Mac or at a server you choose.")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            // Off builds nothing below the switch: the page pays only for what is shown.
            if settings.llmEnabled {
                Divider().background(AppTheme.divider)
                rewriteModes
                Divider().background(AppTheme.divider)
                backendPicker
                Divider().background(AppTheme.divider)
                if settings.llmBackend == .custom {
                    customEndpointFields
                } else {
                    localBackendSection
                }
                Divider().background(AppTheme.divider)
                Text("Hold \(AppTheme.keyLabel(for: settings.smartHotkeyCode)) to rewrite. Change the key in Settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondary)
            }
        }
        .padding(14)
        .background(AppTheme.sectionBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.divider, lineWidth: 1))
        .onAppear { llmApiKeyInput = settings.llmApiKey }
        .onDisappear { llmTestTask?.cancel() }
    }

    // Independent toggles - any combination runs as a single rewrite pass. All start off, so
    // the section states plainly when the Smart key would do nothing.
    private var rewriteModes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What the Smart key does")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.secondary)

            modeToggle(
                .polish,
                label: "Polish",
                sub: "Removes um, uh and false starts. Fixes grammar, keeps your wording."
            )
            modeToggle(
                .restructure,
                label: "Restructure",
                sub: "You said 10am then corrected to 11am - only 11am is pasted."
            )
            modeToggle(
                .smart,
                label: "Match the app",
                sub: "Casual in Slack, a shell command in Terminal, prose in Notes."
            )

            if settings.rewriteOptions.isEmpty {
                Text("Nothing enabled - the Smart key pastes the plain transcript.")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiary)
                    .padding(.top, 2)
            } else if settings.rewriteOptions.contains(.smart) {
                Text("Match the app already removes filler and resolves corrections, so it replaces the other two while it's on.")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private func modeToggle(_ option: RewriteOptions, label: String, sub: String) -> some View {
        // Superseded toggles stay operable - turning Match-the-app off restores them - but read
        // as inactive so the UI never claims an effect the prompt does not have.
        let superseded = option != .smart && settings.rewriteOptions.contains(.smart)
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(superseded ? AppTheme.tertiary : AppTheme.primary)
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { settings.rewriteOptions.contains(option) },
                set: { on in
                    if on { settings.rewriteOptions.insert(option) }
                    else { settings.rewriteOptions.remove(option) }
                }
            ))
            .labelsHidden()
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
                    SecureField("sk-... or leave empty for local", text: $llmApiKeyInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(8)
                        .background(AppTheme.windowBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.divider, lineWidth: 1))

                    Button(llmApiKeySaved ? "Saved" : "Save") {
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
                        Text(llmTestStatus == .testing ? "Testing..." : "Test connection")
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
            combinedLocalRow

            if case .ready = installer.status {
                Label("Ready - using Metal GPU", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.success)
            }

            if case .failed(let msg) = installer.status {
                Label(msg, systemImage: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.danger)
            }
        }
        // Checked only when the local model is on screen; Smart Mode off does no disk work.
        .onAppear { installer.reconcileFromDisk() }
    }

    private var combinedLocalRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local Intelligence")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.primary)
                    Text(localRowSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiary)
                }
                Spacer()
                trailingControl
            }

            if case .downloading(let frac, _, _) = installer.status {
                ProgressView(value: frac)
                    .progressViewStyle(.linear)
                    .tint(Color(red: 0.58, green: 0.42, blue: 1.0))
                Text(progressLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiary)
            }
        }
    }

    private var localRowSubtitle: String {
        switch installer.status {
        case .ready:
            return "On-device - running locally with Metal GPU"
        case .preparing, .downloading:
            return "Setting up local intelligence..."
        default:
            let pending = installer.pendingDownloadBytes()
            if pending == 0 {
                return "On-device - runs offline"
            }
            return "On-device - ~\(formatBytes(pending)) download, runs offline"
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch installer.status {
        case .idle:
            Button("Download") { installer.install() }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.58, green: 0.42, blue: 1.0))
                .controlSize(.small)
        case .preparing:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                Text("Preparing...")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiary)
            }
        case .downloading:
            Button("Cancel") { installer.cancel() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(AppTheme.secondary)
        case .ready:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.success)
                    .font(.system(size: 13))
                Button("Remove") { installer.remove() }
                    .foregroundStyle(AppTheme.danger)
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
            }
        case .failed:
            Button("Retry") { installer.retry() }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.58, green: 0.42, blue: 1.0))
                .controlSize(.small)
        }
    }

    private var progressLabel: String {
        guard case .downloading(let frac, let done, let total) = installer.status else { return "" }
        let pct = Int((frac * 100).rounded())
        return "Setting up local intelligence...  \(pct)% - \(formatBytes(done)) / \(formatBytes(total))"
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1024 {
            return String(format: "%.2f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
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
}
