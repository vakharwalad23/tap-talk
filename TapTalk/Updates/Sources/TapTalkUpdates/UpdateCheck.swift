import Foundation

/// The newest published TapTalk release, as much as an update notice needs.
public struct Release: Codable, Equatable, Sendable {
    /// Version number without the tag's leading "v".
    public let version: String
    public let pageURL: URL
    /// The first asset ending in ".dmg"; nil when the release has none.
    public let dmgURL: URL?
}

/// How this copy of TapTalk was installed, which decides the next step a notice offers.
public enum InstallSource: Equatable, Sendable {
    case homebrew
    /// A versioned cask such as taptalk@0.5.1, installed to stay on that version.
    case pinnedHomebrew
    case dmg
}

/// A newer release and the one action that gets it.
public struct UpdateNotice: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case copyCommand(String)
        case open(URL)
    }

    public let version: String
    public let action: Action
}

public enum UpdateError: Error {
    case invalidEndpoint
    case httpStatus(Int)
}

/// Decides whether a release is worth announcing. Pure, except `fetchLatestRelease`.
public enum UpdateCheck {
    public static let endpoint = "https://api.github.com/repos/vakharwalad23/tap-talk/releases/latest"
    public static let brewCommand = "brew upgrade --cask taptalk"
    public static let caskroomPath = "/opt/homebrew/Caskroom"
    private static let caskName = "taptalk"
    private static let requestTimeout: TimeInterval = 15

    public static func release(fromGitHubJSON data: Data) throws -> Release {
        let payload = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let dmg = payload.assets.first { $0.name.hasSuffix(".dmg") }
        return Release(version: stripped(payload.tagName), pageURL: payload.htmlURL, dmgURL: dmg?.browserDownloadURL)
    }

    /// Numeric dotted comparison. Anything that is not plain digits and dots, such as a
    /// "-beta" suffix, never counts as newer.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let new = components(candidate), let old = components(current) else { return false }
        let width = max(new.count, old.count)
        let padded = { (parts: [Int]) in parts + Array(repeating: 0, count: width - parts.count) }
        return padded(old).lexicographicallyPrecedes(padded(new))
    }

    /// Due after `interval`, when never checked, or when the stamp lies in the future (a clock set back).
    public static func isDue(lastCheck: Date?, now: Date, interval: TimeInterval) -> Bool {
        guard let lastCheck, lastCheck <= now else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    /// Release links come from a network answer; only https ones are handed to the system to open.
    public static func isOpenable(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
    }

    public static func installSource(caskroomEntries: [String]) -> InstallSource {
        if caskroomEntries.contains(caskName) { return .homebrew }
        if caskroomEntries.contains(where: { $0.hasPrefix(caskName + "@") }) { return .pinnedHomebrew }
        return .dmg
    }

    public static func notice(
        for release: Release, currentVersion: String, source: InstallSource, dismissedVersion: String?
    ) -> UpdateNotice? {
        guard source != .pinnedHomebrew,
              release.version != dismissedVersion,
              isNewer(release.version, than: currentVersion) else { return nil }
        switch source {
        case .homebrew:
            return UpdateNotice(version: release.version, action: .copyCommand(brewCommand))
        case .dmg, .pinnedHomebrew:
            return UpdateNotice(version: release.version, action: .open(release.dmgURL ?? release.pageURL))
        }
    }

    /// One unauthenticated GET; GitHub allows 60 an hour per address, and TapTalk asks once a day.
    public static func fetchLatestRelease(session: URLSession) async throws -> Release {
        guard let url = URL(string: endpoint) else { throw UpdateError.invalidEndpoint }
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TapTalk", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.httpStatus(status) }
        return try release(fromGitHubJSON: data)
    }

    private static func stripped(_ version: String) -> String {
        version.hasPrefix("v") ? String(version.dropFirst()) : version
    }

    private static func components(_ version: String) -> [Int]? {
        let parts = stripped(version).split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        return !parts.isEmpty && numbers.count == parts.count ? numbers : nil
    }
}

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let htmlURL: URL
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}
