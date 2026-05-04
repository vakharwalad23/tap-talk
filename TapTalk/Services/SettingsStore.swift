import Foundation
import ServiceManagement

enum TranscriptionEngine: String {
    case local
    case cloud
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private static let apiKeyAccount = "openai-api-key"

    @Published var selectedTier: UInt8 {
        didSet { UserDefaults.standard.set(Int(selectedTier), forKey: "selectedTier") }
    }

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

    @Published var cloudModel: String {
        didSet { UserDefaults.standard.set(cloudModel, forKey: "cloudModel") }
    }

    // In-memory only — loaded from Keychain on init
    @Published var apiKey: String = "" {
        didSet { persistApiKey(apiKey) }
    }

    private init() {
        let rawTier = UserDefaults.standard.integer(forKey: "selectedTier")
        selectedTier = rawTier > 0 ? UInt8(rawTier) : 1

        selectedLanguage = UserDefaults.standard.string(forKey: "selectedLanguage")

        let rawCode = UserDefaults.standard.integer(forKey: "hotkeyCode")
        hotkeyCode = rawCode > 0 ? UInt16(rawCode) : UInt16(0x36) // kVK_RightCommand

        launchAtLogin = (try? SMAppService.mainApp.status) == .enabled

        let rawEngine = UserDefaults.standard.string(forKey: "transcriptionEngine") ?? "local"
        transcriptionEngine = TranscriptionEngine(rawValue: rawEngine) ?? .local

        cloudModel = UserDefaults.standard.string(forKey: "cloudModel") ?? "whisper-1"

        apiKey = KeychainService.load(account: Self.apiKeyAccount) ?? ""
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
}
