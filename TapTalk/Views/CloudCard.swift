import SwiftUI

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

// Catalog card for cloud transcription. Usable once an API key is saved; the key lives in the Keychain.
struct CloudCard: View {
    @ObservedObject private var settings = SettingsStore.shared
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 7) {
                Text("Cloud - OpenAI Whisper")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                Spacer()
                UseEngineControl(isInUse: settings.isCloudInUse, isEnabled: !settings.apiKey.isEmpty) {
                    settings.useCloud()
                    AppController.shared.fetchVoiceDetectorIfMissing()
                }
            }
            Text("Sends your audio to OpenAI with your own API key. Needs an internet connection.")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            // The model choice matters only once cloud is the engine in use.
            if settings.isCloudInUse {
                Divider().background(AppTheme.divider)
                cloudModelGrid
            }
            Divider().background(AppTheme.divider)
            apiKeyRow
        }
        .padding(14)
        .background(AppTheme.sectionBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.divider, lineWidth: 1))
        .onAppear { apiKeyInput = settings.apiKey }
        .onDisappear { testTask?.cancel() }
    }

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


    private var removesKey: Bool { apiKeyInput.isEmpty && !settings.apiKey.isEmpty }

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

                Button(apiKeySaved ? "Saved" : (removesKey ? "Remove" : "Save")) {
                    // Emptying the field and confirming deletes the key from the Keychain.
                    if removesKey {
                        settings.apiKey = ""
                        testStatus = .idle
                        return
                    }
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
                .tint(apiKeySaved ? AppTheme.success : (removesKey ? AppTheme.danger : AppTheme.accent))
                .controlSize(.small)
                .disabled(apiKeyInput == settings.apiKey)
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
}
