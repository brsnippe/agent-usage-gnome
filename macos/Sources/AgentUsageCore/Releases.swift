import Foundation

// The update check. A Mac install comes from a release zip, not from git, so
// it asks GitHub's API for the newest release instead of `git ls-remote`.

public enum Releases {
    private static let remote = Pattern(#"^(?:https://|ssh://git@|git@)github\.com[:/]([^/\s]+)/([^/\s]+?)(?:\.git)?/?$"#)

    /// `owner/name` from a GitHub remote URL, over https or ssh.
    public static func repository(fromRemote url: String) -> String? {
        guard let groups = remote.groups(url.trimmingCharacters(in: .whitespacesAndNewlines)),
              let owner = groups[0], let name = groups[1] else {
            return nil
        }
        return "\(owner)/\(name)"
    }

    /// Where GitHub answers with the newest release: drafts and pre-releases
    /// don't count.
    public static func latestURL(repository: String) -> URL? {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")
    }

    /// The fallback when the API refuses: GitHub allows 60 anonymous API calls
    /// an hour per address, which shared networks run out of. This page
    /// redirects to the newest release's tag, without that limit.
    public static func pageURL(repository: String) -> URL? {
        URL(string: "https://github.com/\(repository)/releases/latest")
    }

    /// The version in the address `pageURL` redirects to
    /// (`…/releases/tag/v0.7.0`), or nil when there's no release yet.
    public static func latestVersion(fromPage url: URL) -> String? {
        let parts = url.path.split(separator: "/")
        guard parts.count >= 2, parts[parts.count - 2] == "tag" else {
            return nil
        }
        var tag = String(parts[parts.count - 1])
        guard Versions.parse(tag) != nil else {
            return nil
        }
        if tag.hasPrefix("v") {
            tag.removeFirst()
        }
        return tag
    }

    /// The version GitHub's answer names, without its `v`, or nil when it
    /// isn't a release version.
    public static func latestVersion(fromAPI data: Data) -> String? {
        guard let answer = try? JSONDecoder().decode(JSONValue.self, from: data),
              answer["draft"] != .bool(true), answer["prerelease"] != .bool(true) else {
            return nil
        }
        var tag = JS.text(answer["tag_name"]).trimmingCharacters(in: .whitespaces)
        guard Versions.parse(tag) != nil else {
            return nil
        }
        if tag.hasPrefix("v") {
            tag.removeFirst()
        }
        return tag
    }

    /// The settings window's version line.
    public static func status(installed: String, latest: Result<String, ReleaseCheckError>) -> (text: String, updateAvailable: Bool) {
        let shown = installed.isEmpty ? "an unknown version" : "v\(installed)"
        switch latest {
        case .failure(let error):
            return ("\(shown) · couldn't check: \(error.message)", false)
        case .success(let version) where Versions.isNewer(version, than: installed):
            return ("\(shown) · v\(version) is available", true)
        case .success:
            return ("\(shown) · up to date", false)
        }
    }
}

public struct ReleaseCheckError: Error, Equatable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }
}
