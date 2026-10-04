import Foundation
import XCTest

@testable import AgentUsageCore

final class ReleasesTests: XCTestCase {
    func testRepositoryFromRemote() {
        XCTAssertEqual([
            "https://github.com/brsnippe/agent-usage-gnome.git",
            "https://github.com/brsnippe/agent-usage-gnome",
            "git@github.com:brsnippe/agent-usage-gnome.git",
            "ssh://git@github.com/brsnippe/agent-usage-gnome.git",
            " https://github.com/brsnippe/agent-usage/ \n",
        ].map(Releases.repository(fromRemote:)), [
            "brsnippe/agent-usage-gnome", "brsnippe/agent-usage-gnome", "brsnippe/agent-usage-gnome", "brsnippe/agent-usage-gnome",
            "brsnippe/agent-usage",
        ])
        XCTAssertNil(Releases.repository(fromRemote: "https://gitlab.com/someone/thing.git"), "only GitHub has the releases API this uses")
        XCTAssertNil(Releases.repository(fromRemote: "/home/me/bare.git"))
        XCTAssertEqual(Releases.latestURL(repository: "brsnippe/agent-usage-gnome")?.absoluteString,
                       "https://api.github.com/repos/brsnippe/agent-usage-gnome/releases/latest")
    }

    func testLatestVersion() {
        func answer(_ json: String) -> String? {
            Releases.latestVersion(fromAPI: Data(json.utf8))
        }
        XCTAssertEqual(answer(#"{"tag_name": "v0.7.0", "draft": false, "prerelease": false, "name": "v0.7.0"}"#), "0.7.0")
        XCTAssertEqual(answer(#"{"tag_name": "0.7.1"}"#), "0.7.1", "a tag without its v")
        XCTAssertNil(answer(#"{"tag_name": "v0.8.0", "prerelease": true}"#), "pre-releases don't count")
        XCTAssertNil(answer(#"{"tag_name": "v0.8.0", "draft": true}"#), "neither do drafts")
        XCTAssertNil(answer(#"{"message": "Not Found", "documentation_url": "https://docs.github.com"}"#), "no releases yet")
        XCTAssertNil(answer(#"{"tag_name": "nightly"}"#), "a tag that isn't a version")
        XCTAssertNil(answer("<html>rate limited</html>"))
    }

    func testLatestVersionFromTheReleasePage() {
        func page(_ address: String) -> String? {
            Releases.latestVersion(fromPage: URL(string: address)!)
        }
        XCTAssertEqual(Releases.pageURL(repository: "brsnippe/agent-usage-gnome")?.absoluteString,
                       "https://github.com/brsnippe/agent-usage-gnome/releases/latest")
        XCTAssertEqual(page("https://github.com/brsnippe/agent-usage-gnome/releases/tag/v0.7.0"), "0.7.0")
        XCTAssertNil(page("https://github.com/brsnippe/agent-usage-gnome/releases"), "no release: GitHub stays on the list")
        XCTAssertNil(page("https://github.com/brsnippe/agent-usage-gnome/releases/latest"), "no redirect at all")
        XCTAssertNil(page("https://github.com/brsnippe/agent-usage-gnome/releases/tag/nightly"))
    }

    func testStatusLine() {
        XCTAssertEqual(Releases.status(installed: "0.6.0", latest: .success("0.7.0")).text, "v0.6.0 · v0.7.0 is available")
        XCTAssertTrue(Releases.status(installed: "0.6.0", latest: .success("0.7.0")).updateAvailable)
        XCTAssertEqual(Releases.status(installed: "0.7.0", latest: .success("0.7.0")).text, "v0.7.0 · up to date")
        XCTAssertFalse(Releases.status(installed: "0.7.0-dev+abc", latest: .success("0.7.0")).updateAvailable,
                       "a development build isn't behind its own release")
        XCTAssertEqual(Releases.status(installed: "", latest: .failure(ReleaseCheckError("offline"))).text, "an unknown version · couldn't check: offline")
    }

    func testSettingsChoices() {
        let mac = Machine(
            findProgram: { ["opencode", "claude"].contains($0) ? "/opt/homebrew/bin/\($0)" : nil },
            findApp: { ["Terminal.app", "Ghostty.app", "Claude.app"].contains($0.appName) ? "/Applications/\($0.appName)" : nil },
            shell: "/bin/zsh",
            home: "/Users/me"
        )
        XCTAssertEqual(Terminals.agentChoices(on: mac).map(\.label), [
            "OpenCode", "OpenCode (desktop app) (not installed)", "Claude Code", "Claude (desktop app)", "Codex (not installed)", "Custom…",
        ])
        XCTAssertEqual(Terminals.agentChoices(on: mac).map(\.id), ["opencode", "opencode-desktop", "claude", "claude-desktop", "codex", "custom"],
                       "the GNOME schema's ids")
        XCTAssertEqual(Terminals.terminalChoices(current: "auto", on: mac).map(\.label), ["Automatic (Terminal)", "Terminal", "Ghostty", "Custom…"],
                       "the installed terminals, in list order")
        XCTAssertEqual(Terminals.terminalChoices(current: "kitty", on: mac).map(\.label),
                       ["Automatic (Terminal)", "Terminal", "Ghostty", "Kitty (not installed)", "Custom…"],
                       "a chosen terminal that's gone stays in the list, marked")
    }
}
