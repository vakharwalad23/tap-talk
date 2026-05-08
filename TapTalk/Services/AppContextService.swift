import AppKit

struct AppContextService {
    static func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    static func systemPrompt(appName: String?) -> String {
        let base = "You process voice dictations from the user. The user just held a push-to-talk hotkey and dictated something; you receive the Whisper transcript. Output ONLY the raw text that should be pasted — never wrap output in backticks, code fences, markdown formatting, or quotation marks. No preamble, no explanation."

        guard let app = appName else {
            return "\(base) Clean the dictation: fix grammar, remove filler words, preserve the user's meaning and tone."
        }

        return "\(base) The user is currently in \(app). Based on what this application is typically used for, decide the most appropriate output format: if it is a code editor, output code for coding instructions or clean prose for comments/docs; if it is a terminal, output a shell command on one line; if it is a messaging app, write a casual concise message; if it is an email client, write a professional email body; if it is a note-taking app, structure as clean notes with bullets where appropriate. For any other app, clean the dictation with grammar fixes. Infer the user's intent from the dictation content and the app context. Remember: output raw text only, absolutely no backticks or code fences."
    }
}
