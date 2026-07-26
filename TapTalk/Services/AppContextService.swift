import AppKit

struct AppContextService {
    static func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    /// Builds the rewrite instruction from the enabled options.
    ///
    /// Clause order is fixed — base, polish, restructure, app context — so the prompt is
    /// byte-identical for a given (app, options) pair. That stability is what lets the LLM
    /// server reuse a cached prefix instead of re-reading the whole instruction every time.
    /// Reordering these, or interpolating anything variable, silently costs that.
    static func systemPrompt(appName: String?, options: RewriteOptions) -> String {
        var parts: [String] = [base]

        if options.contains(.polish) { parts.append(polishClause) }
        if options.contains(.restructure) { parts.append(restructureClause) }

        if options.contains(.smart) {
            parts.append(appName.map(smartClause) ?? smartClauseNoApp)
        }

        parts.append(closing)
        return parts.joined(separator: " ")
    }

    private static let base =
        "You process voice dictations from the user. The user just held a push-to-talk hotkey "
        + "and dictated something; you receive the speech-to-text transcript."

    private static let polishClause =
        "Remove filler words and disfluencies (um, uh, er, like, you know, I mean). Fix grammar, "
        + "capitalization and punctuation. Otherwise keep the user's own wording and tone — do "
        + "not paraphrase, do not make it more formal, do not add anything they did not say."

    // The failure mode this guards against is subtle: a half-corrected sentence that keeps both
    // the mistake and the correction reads as confident and wrong. The examples are worth their
    // tokens, and they sit inside the cached prefix.
    private static let restructureClause =
        "The speaker corrects themselves mid-dictation. Keep only what they settled on and "
        + "silently drop what they retracted, along with abandoned starts and repeated phrases. "
        + "If they state something and then revise it, the revised version is the only one that "
        + "may appear in the output. "
        + "Example: \"tomorrow I have a meeting at 10am, no wait, the meeting is at 11am\" "
        + "becomes \"Tomorrow I have a meeting at 11am.\" — note that 10am appears nowhere. "
        + "Example: \"can you send me the, actually can you send me the invoice\" "
        + "becomes \"Can you send me the invoice?\""

    private static func smartClause(_ app: String) -> String {
        "The user is currently in \(app). Based on what this application is typically used for, "
        + "decide the most appropriate output format: if it is a code editor, output code for "
        + "coding instructions or clean prose for comments/docs; if it is a terminal, output a "
        + "shell command on one line; if it is a messaging app, write a casual concise message; "
        + "if it is an email client, write a professional email body; if it is a note-taking app, "
        + "structure as clean notes with bullets where appropriate. For any other app, clean the "
        + "dictation with grammar fixes. Infer the user's intent from the dictation content and "
        + "the app context."
    }

    private static let smartClauseNoApp =
        "Clean the dictation: fix grammar, remove filler words, preserve the user's meaning and tone."

    private static let closing =
        "Output ONLY the raw text that should be pasted — never wrap output in backticks, code "
        + "fences, markdown formatting, or quotation marks. No preamble, no explanation."
}
