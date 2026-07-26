import Foundation
import ServiceManagement

enum TranscriptionEngine: String {
    case local
    case cloud
}

// Which local engine runs when transcriptionEngine == .local.
enum LocalEngine: String, CaseIterable {
    case parakeet     // FluidAudio / NVIDIA Parakeet (English/EU, punctuation)
    case nemotron     // FluidAudio / NVIDIA Nemotron 3.5 multilingual (Hindi and beyond)

    /// Model name, credited rather than described. Both engines are multilingual — they simply
    /// cover different language sets — so "Multilingual" was never a distinguishing label.
    var displayName: String {
        switch self {
        case .parakeet: return "Parakeet TDT"
        case .nemotron: return "Nemotron 3.5"
        }
    }

    /// What each engine actually covers, which is the real difference between them.
    var languageSummary: String {
        switch self {
        case .parakeet: return "English + 24 European"
        case .nemotron: return "Hindi + 100 languages"
        }
    }

    // Whether the engine lets the user pick a language. Engines that only auto-detect
    // (Parakeet) hide the picker and run in auto mode.
    var supportsLanguageSelection: Bool {
        switch self {
        case .parakeet: return false
        case .nemotron: return true
        }
    }

    // Label shown in place of the picker for auto-only engines.
    var autoLanguageLabel: String {
        switch self {
        case .parakeet: return "Auto · EU"
        case .nemotron: return "Auto"
        }
    }

    // Engines that can produce incremental hypotheses while audio is still arriving.
    // Drives the visibility of the Settings streaming toggle.
    var supportsStreaming: Bool {
        switch self {
        case .parakeet: return true   // Parakeet + EOU realtime endpointing model
        case .nemotron: return false  // batch only here; the EOU add-on is Parakeet-specific
        }
    }

    // Languages the engine's model can actually produce. Empty for auto-only engines,
    // which show a chip instead of a picker.
    var supportedLanguages: [(id: String?, label: String)] {
        switch self {
        case .parakeet: return []
        case .nemotron: return NemotronEngine.supportedLanguages
        }
    }
}

/// Which script Hindi dictation should be pasted in. Devanagari is what the engine produces;
/// Roman is what most people actually type into chat.
enum HindiScript: String, CaseIterable {
    case devanagari
    case roman
    case matchApp

    var label: String {
        switch self {
        case .devanagari: return "Devanagari"
        case .roman:      return "Roman"
        case .matchApp:   return "Match the app"
        }
    }
}

enum LLMBackend: String {
    case custom
    case local
}

/// What the rewrite pass should do. Independent toggles, composed into a single prompt and a
/// single LLM call. Empty means no rewrite runs at all, which is the default — every mode is
/// opt-in, so the smart hotkey does nothing until the user asks for something.
struct RewriteOptions: OptionSet, Sendable {
    let rawValue: Int

    /// Remove filler and disfluencies, fix grammar and punctuation. Wording is preserved.
    static let polish      = RewriteOptions(rawValue: 1 << 0)
    /// Resolve spoken self-corrections and drop abandoned starts, keeping only the final intent.
    static let restructure = RewriteOptions(rawValue: 1 << 1)
    /// Reformat to suit the app being typed into. The opinionated one.
    static let smart       = RewriteOptions(rawValue: 1 << 2)
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private static let apiKeyAccount    = "openai-api-key"
    private static let llmApiKeyAccount = "llm-api-key"

    @Published var selectedLanguage: String? {
        didSet { UserDefaults.standard.set(selectedLanguage, forKey: "selectedLanguage") }
    }

    @Published var hotkeyCode: UInt16 {
        didSet { UserDefaults.standard.set(Int(hotkeyCode), forKey: "hotkeyCode") }
    }

    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin(launchAtLogin) }
    }

    @Published var transcriptionEngine: TranscriptionEngine {
        didSet { UserDefaults.standard.set(transcriptionEngine.rawValue, forKey: "transcriptionEngine") }
    }

    @Published var localEngine: LocalEngine {
        didSet { UserDefaults.standard.set(localEngine.rawValue, forKey: "localEngine") }
    }

    @Published var streamingEnabled: Bool {
        didSet { UserDefaults.standard.set(streamingEnabled, forKey: "streamingEnabled") }
    }

    @Published var cloudModel: String {
        didSet { UserDefaults.standard.set(cloudModel, forKey: "cloudModel") }
    }

    // In-memory only — loaded from Keychain on init
    @Published var apiKey: String = "" {
        didSet { persistApiKey(apiKey) }
    }

    @Published var llmEnabled: Bool {
        didSet { UserDefaults.standard.set(llmEnabled, forKey: "llmEnabled") }
    }

    @Published var rewriteOptions: RewriteOptions {
        didSet { UserDefaults.standard.set(rewriteOptions.rawValue, forKey: "rewriteOptions") }
    }

    @Published var hindiScript: HindiScript {
        didSet { UserDefaults.standard.set(hindiScript.rawValue, forKey: "hindiScript") }
    }

    @Published var llmBackend: LLMBackend {
        didSet { UserDefaults.standard.set(llmBackend.rawValue, forKey: "llmBackend") }
    }

    @Published var llmEndpointURL: String {
        didSet { UserDefaults.standard.set(llmEndpointURL, forKey: "llmEndpointURL") }
    }

    @Published var llmModel: String {
        didSet { UserDefaults.standard.set(llmModel, forKey: "llmModel") }
    }

    // In-memory only — loaded from Keychain on init
    @Published var llmApiKey: String = "" {
        didSet { persistLLMApiKey(llmApiKey) }
    }

    @Published var smartHotkeyEnabled: Bool {
        didSet { UserDefaults.standard.set(smartHotkeyEnabled, forKey: "smartHotkeyEnabled") }
    }

    @Published var smartHotkeyCode: UInt16 {
        didSet { UserDefaults.standard.set(Int(smartHotkeyCode), forKey: "smartHotkeyCode") }
    }

    @Published var dictionarySegments: [DictionarySegment] {
        didSet { persistDictionarySegments(dictionarySegments) }
    }

    private init() {
        selectedLanguage = UserDefaults.standard.string(forKey: "selectedLanguage")

        let rawCode = UserDefaults.standard.integer(forKey: "hotkeyCode")
        hotkeyCode = rawCode > 0 ? UInt16(rawCode) : UInt16(0x36) // kVK_RightCommand

        launchAtLogin = (try? SMAppService.mainApp.status) == .enabled

        let rawEngine = UserDefaults.standard.string(forKey: "transcriptionEngine") ?? "local"
        transcriptionEngine = TranscriptionEngine(rawValue: rawEngine) ?? .local

        let rawLocalEngine = UserDefaults.standard.string(forKey: "localEngine") ?? "parakeet"
        localEngine = LocalEngine(rawValue: rawLocalEngine) ?? .parakeet

        streamingEnabled = UserDefaults.standard.bool(forKey: "streamingEnabled")

        cloudModel = UserDefaults.standard.string(forKey: "cloudModel") ?? "whisper-1"

        apiKey = KeychainService.load(account: Self.apiKeyAccount) ?? ""

        llmEnabled = UserDefaults.standard.bool(forKey: "llmEnabled")

        // Every mode is opt-in: absent key means none enabled, and the rewrite is skipped.
        rewriteOptions = RewriteOptions(
            rawValue: UserDefaults.standard.integer(forKey: "rewriteOptions")
        )

        let rawScript = UserDefaults.standard.string(forKey: "hindiScript") ?? "devanagari"
        hindiScript = HindiScript(rawValue: rawScript) ?? .devanagari

        let rawLLMBackend = UserDefaults.standard.string(forKey: "llmBackend") ?? "custom"
        llmBackend = LLMBackend(rawValue: rawLLMBackend) ?? .custom

        llmEndpointURL = UserDefaults.standard.string(forKey: "llmEndpointURL") ?? ""
        llmModel = UserDefaults.standard.string(forKey: "llmModel") ?? "llama3.2"

        llmApiKey = KeychainService.load(account: Self.llmApiKeyAccount) ?? ""

        smartHotkeyEnabled = UserDefaults.standard.bool(forKey: "smartHotkeyEnabled")

        let rawSmartCode = UserDefaults.standard.integer(forKey: "smartHotkeyCode")
        smartHotkeyCode = rawSmartCode > 0 ? UInt16(rawSmartCode) : UInt16(0x3A) // kVK_Option

        if let data = UserDefaults.standard.data(forKey: "dictionarySegments"),
           let decoded = try? JSONDecoder().decode([DictionarySegment].self, from: data) {
            dictionarySegments = decoded
        } else {
            dictionarySegments = []
        }
    }

    private func applyLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Not critical
        }
    }

    private func persistApiKey(_ key: String) {
        if key.isEmpty {
            KeychainService.delete(account: Self.apiKeyAccount)
        } else {
            try? KeychainService.save(key: key, account: Self.apiKeyAccount)
        }
    }

    private func persistLLMApiKey(_ key: String) {
        if key.isEmpty {
            KeychainService.delete(account: Self.llmApiKeyAccount)
        } else {
            try? KeychainService.save(key: key, account: Self.llmApiKeyAccount)
        }
    }

    private func persistDictionarySegments(_ segments: [DictionarySegment]) {
        if let data = try? JSONEncoder().encode(segments) {
            UserDefaults.standard.set(data, forKey: "dictionarySegments")
        }
    }
}
