import AppKit
import ApplicationServices

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

    /// Reads the focused window's title over the Accessibility API — already granted for the
    /// hotkey and paste, so this needs no additional permission.
    ///
    /// The messaging timeout is the important part: an AX request to a hung application blocks
    /// the caller indefinitely by default, and this runs on the key-up→paste path. A quarter
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
    /// Clause order is fixed — base, polish, restructure, app context, closing — so the prompt is
    /// byte-identical for a given (options, app, title) triple. Order is deliberate beyond
    /// readability: everything variable lives in the app-context clause, which sits last, so the
    /// stable prefix a server-side cache can reuse is as long as possible. Moving the app context
    /// earlier would invalidate the cache on every window-title change.
    static func systemPrompt(context: AppContext?, options: RewriteOptions) -> String {
        var parts: [String] = [base]

        // Match-the-app supersedes the cleanup modes rather than stacking with them.
        //
        // Measured against the shipped 1.5B model, any cleanup clause placed alongside the
        // destination clause caused it to be ignored entirely — the model anchored on "tidy this
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

    private static let base =
        "You process voice dictations from the user. The user just held a push-to-talk hotkey "
        + "and dictated something; you receive the speech-to-text transcript."

    private static let polishClause =
        "Remove filler words and disfluencies (um, uh, er, like, you know, I mean). Fix grammar, "
        + "capitalization and punctuation. Otherwise keep the user's own wording and tone — do "
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
        + "becomes \"Tomorrow I have a meeting at 11am.\" — note that 10am appears nowhere. "
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
            + "names a specific site or document, weigh that over the application itself — a "
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
                + "destination — a search box, a mail client, a social post, a code review, or a "
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
        // browsers — they are the ones registered to open https — so ask it instead of trying
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

    /// Primes the Launch Services handler lookup so the first dictation does not pay for it.
    nonisolated static func warmUp() {
        guard let https = URL(string: "https://example.com") else { return }
        _ = NSWorkspace.shared.urlsForApplications(toOpen: https)
    }

    private static let closing =
        "Output ONLY the raw text that should be pasted — never wrap output in backticks, code "
        + "fences, markdown formatting, or quotation marks. No preamble, no explanation."
}
