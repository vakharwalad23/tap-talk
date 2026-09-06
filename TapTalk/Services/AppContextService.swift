import AppKit
import ApplicationServices
import os

/// What TapTalk knows about where the text is going.
struct AppContext {
    let name: String
    let bundleID: String?
    /// Focused window title. Often the only way to tell Gmail from YouTube in the same browser.
    let windowTitle: String?
}

struct AppContextService {
    static func currentContext() -> AppContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return AppContext(
            name: app.localizedName ?? "an application",
            bundleID: app.bundleIdentifier,
            windowTitle: focusedWindowTitle(pid: app.processIdentifier)
        )
    }

    // MARK: Window title

    /// Reads the focused window's title over the Accessibility API - already granted for the
    /// hotkey and paste, so this needs no additional permission.
    ///
    /// The messaging timeout is the important part: an AX request to a hung application blocks
    /// the caller indefinitely by default, and this runs on the key-up->paste path. A quarter
    /// second is far above a healthy app's response and far below anything a user would notice.
    private static func focusedWindowTitle(pid: pid_t) -> String? {
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.25)

        var windowRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef)
                == .success,
            let window = windowRef, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }

        var titleRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                window as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success,
            let title = titleRef as? String
        else { return nil }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Long titles are usually breadcrumb chains; the leading part carries the signal.
        return String(trimmed.prefix(120))
    }

    // MARK: Prompt

    /// Builds the rewrite instruction from the enabled options.
    ///
    /// Clause order is fixed - base, polish, restructure, app context, closing - so the prompt is
    /// byte-identical for a given (options, app, title) triple. Order is deliberate beyond
    /// readability: everything variable lives in the app-context clause, which sits last, so the
    /// stable prefix a server-side cache can reuse is as long as possible. Moving the app context
    /// earlier would invalidate the cache on every window-title change.
    static func systemPrompt(
        context: AppContext?, options: RewriteOptions, romanize: Bool = false
    ) -> String {
        // Romanization outranks everything, for the same reason match-the-app outranks the
        // cleanup modes: this model does one job well and none when given two. Measured - folding
        // the transliteration into the destination clause returned Devanagari 3/3, and appending
        // it as a rival clause did the same.
        //
        // Little is lost. Romanized Hindi chat text is inherently casual, which is most of what
        // the destination clause would have contributed for the apps this is used in.
        if romanize { return romanizeClause }

        var parts: [String] = [base]

        // Match-the-app supersedes the cleanup modes rather than stacking with them.
        //
        // Measured against the shipped 1.5B model, any cleanup clause placed alongside the
        // destination clause caused it to be ignored entirely - the model anchored on "tidy this
        // text" and echoed the dictation instead of acting on it. Reproduced 3/3 with Polish, 3/3
        // with Restructure, and 3/3 with the destination clause moved first, so it is a capability
        // limit of a small model following a multi-part instruction, not a wording problem.
        //
        // Nothing is lost by the precedence: rewriting a dictation into an email inherently drops
        // fillers and honours self-corrections. Verified 3/3 on a dictation containing both.
        if options.contains(.smart) {
            parts.append(smartClause(context))
        } else {
            if options.contains(.polish) { parts.append(polishClause) }
            if options.contains(.restructure) { parts.append(restructureClause) }
        }

        parts.append(closing)
        return parts.joined(separator: " ")
    }

    /// Transliteration instruction, few-shot rather than descriptive.
    ///
    /// The examples are the whole reason this works. Described in prose the model translated to
    /// English, dropped words and changed the verb person; shown five worked pairs it became
    /// stable and correct across runs. They also teach the two things a rule-based transform
    /// cannot do: drop the inherent schwa (कल -> "kal", not "kala") and leave English loanwords
    /// as English (मीटिंग -> "meeting", not "mitinga").
    private static let romanizeClause = """
        Transliterate Hindi (Devanagari) into Roman script exactly as Hindi speakers type in chat. \
        Never translate. Keep English words in English. No diacritics.

        मैं कल आऊँगा -> main kal aaunga
        यार मीटिंग कब है -> yaar meeting kab hai
        मुझे लगता है यह ठीक है -> mujhe lagta hai yeh theek hai
        कैफे में मिलते हैं -> cafe mein milte hain
        अगले हफ्ते तक finish हो जाएगा -> agle hafte tak finish ho jayega

        Output only the transliteration - no preamble, no quotation marks.
        """

    private static let base =
        "You process voice dictations from the user. The user just held a push-to-talk hotkey "
        + "and dictated something; you receive the speech-to-text transcript."

    private static let polishClause =
        "Remove filler words and disfluencies (um, uh, er, like, you know, I mean). Fix grammar, "
        + "capitalization and punctuation. Otherwise keep the user's own wording and tone - do "
        + "not paraphrase, do not make it more formal, do not add anything they did not say."

    // The failure mode this guards against is subtle: a half-corrected sentence that keeps both
    // the mistake and the correction reads as confident and wrong. The examples are worth their
    // tokens, and they sit inside the cacheable prefix.
    private static let restructureClause =
        "The speaker corrects themselves mid-dictation. Keep only what they settled on and "
        + "silently drop what they retracted, along with abandoned starts and repeated phrases. "
        + "If they state something and then revise it, the revised version is the only one that "
        + "may appear in the output. "
        + "Example: \"tomorrow I have a meeting at 10am, no wait, the meeting is at 11am\" "
        + "becomes \"Tomorrow I have a meeting at 11am.\" - note that 10am appears nowhere. "
        + "Example: \"can you send me the, actually can you send me the invoice\" "
        + "becomes \"Can you send me the invoice?\""

    private static func smartClause(_ context: AppContext?) -> String {
        guard let context else {
            return "Clean the dictation: fix grammar, remove filler words, preserve the user's "
                + "meaning and tone."
        }

        var clause = "The user is dictating into \(context.name)"
        if let title = context.windowTitle {
            // Handed over raw rather than parsed. A title like
            // "Inbox (12) - you@gmail.com - Gmail - Google Chrome" tells the model far more than
            // any regex would extract, and title formats differ per app and per browser.
            clause += ", with the current window titled \"\(title)\""
        }
        clause += ". "
        clause += guidance(for: context)
        clause += " Match the register and format that destination expects. If the window title "
            + "names a specific site or document, weigh that over the application itself - a "
            + "browser showing a mail client should be written like email, not like a web page. "
            + "Infer intent from the dictation content as well as the destination; when the two "
            + "disagree, follow the dictation."
        return clause
    }

    /// Category guidance keyed on bundle identifier. Bundle IDs are stable and locale-independent,
    /// unlike `localizedName`, which differs on a non-English system.
    private static func guidance(for context: AppContext) -> String {
        switch category(for: context.bundleID) {
        case .terminal:
            return "This is a terminal: output a single shell command on one line, no prose, no "
                + "explanation, no code fence."
        case .editor:
            return "This is a code editor: output code when the dictation describes code, or "
                + "clean prose when it describes a comment, commit message or documentation. "
                + "Never wrap code in a fence."
        case .messaging:
            return "This is a messaging app: write a casual, concise message. No greeting or "
                + "sign-off unless dictated. Keep it to what a person would actually type."
        case .email:
            return "This is an email client: write a clear, professional message body. Do not "
                + "invent a subject line, greeting or signature unless the user dictated one."
        case .notes:
            return "This is a note-taking app: structure as clean notes, using short bullets "
                + "when the dictation lists several things."
        case .documents:
            return "This is a document editor: write well-formed prose in complete sentences."
        case .browser:
            return "This is a web browser, so the window title is the best clue to the real "
                + "destination - a search box, a mail client, a social post, a code review, or a "
                + "long-form document all want different registers."
        case .unknown:
            return "Judge from the destination and the dictation what format fits best; when "
                + "nothing suggests otherwise, clean the dictation and fix its grammar."
        }
    }

    private enum Category {
        case terminal, editor, messaging, email, notes, documents, browser, unknown
    }

    private static func category(for bundleID: String?) -> Category {
        guard let id = bundleID?.lowercased() else { return .unknown }

        // Prefix matching so version- and channel-specific IDs (JetBrains, browser betas,
        // Electron rebuilds) resolve without an exhaustive list.
        func matches(_ needles: [String]) -> Bool {
            needles.contains { id == $0 || id.hasPrefix($0) }
        }

        if matches([
            "com.apple.terminal", "com.googlecode.iterm2", "dev.warp", "co.zeit.hyper",
            "net.kovidgoyal.kitty", "io.alacritty", "com.mitchellh.ghostty", "com.tabby",
        ]) { return .terminal }

        if matches([
            "com.microsoft.vscode", "com.visualstudio.code", "com.apple.dt.xcode",
            "com.jetbrains", "com.sublimetext", "dev.zed.zed", "com.todesktop",
            "com.exafunction.windsurf", "org.vim", "org.gnu.emacs", "com.panic.nova",
        ]) { return .editor }

        if matches([
            "com.tinyspeck.slackmacgap", "com.hnc.discord", "net.whatsapp", "com.apple.mobilesms",
            "org.telegram", "com.microsoft.teams", "ru.keepcoder.telegram", "com.signal",
        ]) { return .messaging }

        if matches([
            "com.apple.mail", "com.readdle.smartemail", "com.superhuman", "com.missiveapp",
            "com.microsoft.outlook", "com.bloop.airmail",
        ]) { return .email }

        if matches([
            "com.apple.notes", "notion.id", "md.obsidian", "com.agiletortoise.drafts",
            "net.shinyfrog.bear", "com.reflect", "com.electron.logseq", "com.craft",
        ]) { return .notes }

        if matches([
            "com.apple.iwork.pages", "com.microsoft.word", "com.apple.textedit",
            "com.google.docs", "org.libreoffice",
        ]) { return .documents }

        // Browsers are not matched against a list. macOS already knows which applications are
        // browsers - they are the ones registered to open https - so ask it instead of trying
        // to keep pace with Arc, Dia, Comet, Zen, Orion and whatever ships next month.
        // Checked last so a specific category always wins over the generic browser answer.
        if isBrowser(id) { return .browser }

        return .unknown
    }

    /// Whether the bundle identifier belongs to an application registered to open https.
    ///
    /// Queried live rather than cached: Launch Services answers in ~0.2 ms once warm, so there is
    /// no reason to hold a snapshot that goes stale the moment a browser is installed. The first
    /// call after launch costs ~12 ms, which `warmUp()` absorbs off the dictation path.
    private static func isBrowser(_ bundleID: String) -> Bool {
        guard let https = URL(string: "https://example.com") else { return false }
        return NSWorkspace.shared.urlsForApplications(toOpen: https)
            .contains { Bundle(url: $0)?.bundleIdentifier?.lowercased() == bundleID }
    }

    /// Whether this transcript should be romanized.
    ///
    /// Every condition has to hold, and each rules out a way this could fire when it should not:
    ///
    /// - **Roman requested.** The setting is the user's explicit instruction.
    /// - **Local transcription.** The cloud engine is a different model with its own output.
    /// - **Nemotron selected.** Parakeet cannot produce Devanagari at all, so a stale `roman`
    ///   setting left over from using Nemotron must not follow the user back to Parakeet.
    /// - **Hindi selected.** This is the condition that actually bites: **Marathi is written in
    ///   Devanagari too**, so a script check alone would romanize Marathi with a prompt whose
    ///   examples are entirely Hindi. The transliteration is language-specific, not script-specific.
    /// - **Devanagari present.** English dictation costs nothing even with Roman selected.
    static func shouldRomanize(
        _ text: String,
        script: HindiScript,
        transcriptionEngine: TranscriptionEngine,
        localEngine: LocalEngine,
        language: String?
    ) -> Bool {
        guard script == .roman,
              transcriptionEngine == .local,
              localEngine == .nemotron,
              language == hindiLanguageCode
        else { return false }
        return containsDevanagari(text)
    }

    /// The language key Nemotron recognizes for Hindi, and the only one the few-shot
    /// transliteration examples cover.
    static let hindiLanguageCode = "hi"

    /// Devanagari block. One pass, no allocation - this runs on the paste path.
    static func containsDevanagari(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0900...0x097F).contains($0.value) }
    }

    /// Records what the rewrite actually resolved, so a wrong result can be traced to the
    /// destination, the category or the enabled modes without guessing.
    ///
    /// The window title's *content* is deliberately not logged - it can hold document names and
    /// email subjects, and unlike the model call this would persist in the system log. Its
    /// presence and length are enough to tell a failed Accessibility read from a bad category.
    nonisolated static func logResolvedContext(_ context: AppContext?, options: RewriteOptions) {
        var modes: [String] = []
        if options.contains(.smart) { modes.append("smart") }
        if options.contains(.polish) { modes.append("polish") }
        if options.contains(.restructure) { modes.append("restructure") }

        let app = context?.name ?? "none"
        let bundle = context?.bundleID ?? "none"
        let cat = context.map { String(describing: category(for: $0.bundleID)) } ?? "none"
        let titleLen = context?.windowTitle?.count ?? -1

        Logger(subsystem: "talk.tap.app", category: "context").notice(
            """
            rewrite app=\(app, privacy: .public) bundle=\(bundle, privacy: .public) \
            category=\(cat, privacy: .public) titleChars=\(titleLen, privacy: .public) \
            modes=\(modes.joined(separator: "+"), privacy: .public)
            """
        )
    }

    /// Primes the Launch Services handler lookup so the first dictation does not pay for it.
    nonisolated static func warmUp() {
        guard let https = URL(string: "https://example.com") else { return }
        _ = NSWorkspace.shared.urlsForApplications(toOpen: https)
    }

    private static let closing =
        "Output ONLY the raw text that should be pasted - never wrap output in backticks, code "
        + "fences, markdown formatting, or quotation marks. No preamble, no explanation."
}
