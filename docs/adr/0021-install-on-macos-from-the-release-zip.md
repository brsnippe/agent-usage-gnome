# 0021. Install on macOS from the release zip

- Status: Accepted
- Date: 2026-10-02

## Context

On Linux, installs are a git clone ([0015](0015-distribute-via-git.md)), and
the update check asks git ([0016](0016-versions-releases-and-update-check.md)).
On a Mac, that doesn't carry over:

- **No git:** a fresh Mac has no git without Apple's developer tools.
- **Quarantine:** macOS marks an app downloaded in a browser as coming from
  the internet. Unless it's signed and notarized by Apple, macOS then refuses
  to open it.
- **No Apple account:** signing and notarizing need a paid Apple Developer
  account, and none is available.

## Decision

**Releases carry the app.** On a `vX.Y.Z` tag, CI builds
`Agent-Usage-macOS.zip` and attaches it to the GitHub release that
`scripts/release.sh` creates. The app is:
- **universal:** Apple silicon and Intel;
- **signed ad hoc:** Apple silicon runs no unsigned code, and an ad-hoc
  signature needs no account.

**Installing uses the same line as on Linux.** On a Mac, `get.sh`:
1. downloads `releases/latest/download/Agent-Usage-macOS.zip` with `curl`,
   which doesn't set the quarantine flag, so the ad-hoc signed app opens;
2. runs the downloaded app's own `agent-usage install`, which puts it in
   `~/Applications`. No admin password needed.

**The command lives inside the app.** `macos/agent-usage` is at
`Contents/Resources/bin` and is linked into `~/.local/bin`. It's written for
macOS's bash 3.2.

| Command | Does |
|---|---|
| `update [--reinstall] [--pause]` | install the newest release and restart the app |
| `version`, `latest` | the installed and newest versions |
| `diagnose` | what's needed to debug it (never a secret) |
| `uninstall [--purge]` | remove the app, the command and the login item; `--purge` also the data, settings and logs |
| `install <app>` | what `get.sh` runs |

It stops the app with `pkill`: quitting it through AppleScript would ask for
permission.

**Start at login:**
- through `SMAppService`, macOS 13's login items;
- **turned on by the app itself,** the first time it starts from an
  Applications folder. A copy opened from Downloads or a build folder leaves
  it alone;
- **turned off on uninstall:** `uninstall` asks the app to remove it
  (`--unregister-login-item`), since only the app can.

**Versions,** as in [0016](0016-versions-releases-and-update-check.md):
- `VERSION` on its tag, `VERSION-dev+<commit>` otherwise, written into
  `Info.plist` as `AgentUsageVersion`;
- the repository written as `AgentUsageRepository`, from the checkout's
  remote, so a fork checks its own releases.

**The update check:**
- **When:** once a day, starting a minute after launch.
- **How:** GitHub's releases API, since the repository is public. When the
  API's limit of 60 anonymous calls an hour runs out on a shared network (it
  did on GitHub's own CI Macs), it falls back to github.com's
  `/releases/latest` redirect, which has no such limit. `agent-usage latest`
  uses the redirect directly.
- **Update button:** runs `agent-usage update --pause` in the chosen
  terminal ([0020](0020-opening-the-agent-on-macos.md)). The app restarts
  at the end.

## Alternatives

- **Sign and notarize the app** ($99 a year): browser downloads would work.
  Worth revisiting if a company account turns up.
- **A Homebrew cask:** Homebrew is phasing out `--no-quarantine` and casks
  that fail macOS's Gatekeeper check, which an unnotarized app does.
- **Build from source on each Mac:** needs Apple's developer tools (well over
  a gigabyte) and minutes per install.
- **A git clone, as on Linux:** no git on a fresh Mac, and the app would
  still need building.

## Consequences

- **A browser download is blocked.** The README gives the
  `xattr -dr com.apple.quarantine` line that fixes it.
- **Python:** the collectors need Apple's Command Line Tools, or Homebrew's
  Python. The installer and the panel both say how to get it.
- **Tests:** `macos/test/cli-test.sh` installs, updates and uninstalls on
  GitHub's Macs, in a throwaway home folder
  ([0022](0022-testing-the-macos-app.md)).
- **Before the first release with a Mac build,** `get.sh` on a Mac stops
  with "Does the newest release have a macOS build?".
