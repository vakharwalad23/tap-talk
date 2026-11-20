import AppKit
import Combine
import TapTalkUpdates

/// Asks GitHub for the newest release once a day, only while the user has said yes, and holds the
/// notice the Record page and the menu bar show. Every failure is silent and waits a day.
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    @Published private(set) var notice: UpdateNotice?

    private static let checkInterval: TimeInterval = 86_400
    // Hourly due-checks survive sleep, which a single 24 h timer would sleep through.
    private static let tickInterval: TimeInterval = 3_600
    private enum Key {
        static let lastCheck = "updateLastCheck"
        static let latestRelease = "updateLatestRelease"
        static let dismissedVersion = "updateDismissedVersion"
    }

    private let settings = SettingsStore.shared
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var consentObserver: AnyCancellable?
    private var isChecking = false

    private init() {}

    func start() {
        guard consentObserver == nil else { return }
        // Delivered after the property changes; @Published emits before its new value is stored.
        consentObserver = settings.$updateCheckConsent
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { consent in MainActor.assumeIsolated { UpdateService.shared.apply(consent) } }
    }

    func dismiss() {
        defaults.set(notice?.version, forKey: Key.dismissedVersion)
        notice = nil
    }

    func perform(_ action: UpdateNotice.Action) {
        switch action {
        case .copyCommand(let command):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        case .open(let url):
            NSWorkspace.shared.open(url)
        }
    }

    private func apply(_ consent: UpdateCheckConsent) {
        guard consent == .on else {
            timer?.invalidate()
            timer = nil
            notice = nil
            return
        }
        if timer == nil {
            let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { _ in
                MainActor.assumeIsolated { UpdateService.shared.checkIfDue() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        showCachedNotice()
        checkIfDue()
    }

    // A relaunch inside the 24 h window shows the last answer without asking GitHub again.
    private func showCachedNotice() {
        guard let data = defaults.data(forKey: Key.latestRelease),
              let release = try? JSONDecoder().decode(Release.self, from: data) else { return }
        Task {
            let source = await Task.detached { Self.installSource() }.value
            publish(release, source: source)
        }
    }

    private func checkIfDue() {
        guard settings.updateCheckConsent == .on, !isChecking else { return }
        let lastCheck = defaults.object(forKey: Key.lastCheck) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastCheck) >= Self.checkInterval else { return }
        isChecking = true
        Task {
            let result = await Task.detached { () -> (Release, InstallSource)? in
                guard let release = try? await UpdateCheck.fetchLatestRelease(session: .shared) else { return nil }
                return (release, Self.installSource())
            }.value
            isChecking = false
            // Turned off while the request was in flight: the answer is dropped unseen.
            guard settings.updateCheckConsent == .on else { return }
            // Stamped on failure too, so an offline Mac waits a day instead of retrying hourly.
            defaults.set(Date(), forKey: Key.lastCheck)
            guard let (release, source) = result else { return }
            if let data = try? JSONEncoder().encode(release) {
                defaults.set(data, forKey: Key.latestRelease)
            }
            publish(release, source: source)
        }
    }

    private func publish(_ release: Release, source: InstallSource) {
        guard settings.updateCheckConsent == .on else { return }
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        notice = UpdateCheck.notice(
            for: release, currentVersion: current, source: source,
            dismissedVersion: defaults.string(forKey: Key.dismissedVersion))
    }

    // ponytail: Apple Silicon Homebrew prefix only; an Intel-prefix install reads as a DMG install.
    private nonisolated static func installSource() -> InstallSource {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: UpdateCheck.caskroomPath)) ?? []
        return UpdateCheck.installSource(caskroomEntries: entries)
    }
}
