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

                settingsSection("Transcription engine") {
                    enginePicker
                    if settings.transcriptionEngine == .local {
                        Divider().background(AppTheme.divider)
                        localEnginePicker
                    }
                    if settings.transcriptionEngine == .cloud {
                        Divider().background(AppTheme.divider)
                        cloudModelGrid
                        Divider().background(AppTheme.divider)
                        apiKeyRow
                    }
                }

                settingsSection("Startup") {
                    settingRow("Launch at login") {
                        Toggle("", isOn: $settings.launchAtLogin)
                            .labelsHidden()
                    }
                }

                settingsSection("Hotkey") {
                    settingRow("Push-to-talk key") {
                        Button(listening ? "Press a key…" : keyName(settings.hotkeyCode)) {
                            startListening()
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(listening ? .orange : AppTheme.primary)
                    }
                    Divider().background(AppTheme.divider)
                    Button("Reset to Right ⌘") { applyKey(UInt16(kVK_RightCommand)) }
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

    // MARK: Local engine picker (Whisper vs Parakeet)

    private var localEnginePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local model")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.secondary)
            HStack(spacing: 8) {
                localEngineButton(.whisper, label: "Whisper", sub: "99 languages")
                localEngineButton(.parakeet, label: "Parakeet", sub: "Faster · English/EU")
            }
        }
        .padding(.top, 2)
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
                SecureField("sk-…", text: $apiKeyInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .background(AppTheme.windowBg)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppTheme.divider, lineWidth: 1)
                    )

                Button(apiKeySaved ? "Saved ✓" : "Save") {
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
                        Text(testStatus == .testing ? "Testing…" : "Test connection")
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

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
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

    private func settingRow<Content: View>(_ label: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.primary)
            Spacer()
            trailing()
        }
    }

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

final class KeyCapture {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var onCapture: ((UInt16) -> Void)?

    func start(onCapture: @escaping (UInt16) -> Void) {
        stop()
        self.onCapture = onCapture

        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue
        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: keyCaptureCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        tap = t
        source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    func stop() {
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        tap = nil
        source = nil
        onCapture = nil
    }

    fileprivate func deliver(_ code: UInt16) {
        let cb = onCapture
        stop()
        cb?(code)
    }
}

private func keyCaptureCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo, type == .flagsChanged else {
        return Unmanaged.passRetained(event)
    }
    let capture = Unmanaged<KeyCapture>.fromOpaque(userInfo).takeUnretainedValue()
    let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    guard !event.flags.isEmpty else { return Unmanaged.passRetained(event) }
    DispatchQueue.main.async { capture.deliver(code) }
    return Unmanaged.passRetained(event)
}
