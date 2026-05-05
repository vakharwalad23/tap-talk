import AppKit

struct AppContextService {
    static func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    static func systemPrompt(appName: String?) -> String {
        let base = "You are a transcription assistant. Rewrite the following speech transcription to be clean and natural. Fix grammar, remove filler words, and output only the rewritten text with no explanation."
        guard let app = appName?.lowercased() else { return base }
        if app.contains("xcode") || app.contains("code") || app.contains("vim") || app.contains("neovim") {
            return "\(base) The user is in a code editor — be terse and precise, prefer technical language."
        }
        if app.contains("slack") || app.contains("messages") || app.contains("discord") || app.contains("telegram") || app.contains("whatsapp") {
            return "\(base) The user is in a messaging app — keep the tone casual and conversational."
        }
        if app.contains("mail") || app.contains("outlook") || app.contains("spark") {
            return "\(base) The user is writing an email — use a professional tone."
        }
        if app.contains("notes") || app.contains("notion") || app.contains("obsidian") || app.contains("bear") {
            return "\(base) The user is taking notes — preserve detail, use clear structure."
        }
        return base
    }
}
