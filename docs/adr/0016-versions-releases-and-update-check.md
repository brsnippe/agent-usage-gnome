# 0016. Versions, releases and the update check

- Status: Accepted
- Date: 2026-10-02

## Context

With installs coming from git ([0015](0015-distribute-via-git.md)), people
need to know which version they have, the maintainer needs a safe way to
release, and installs should find out about new releases without anyone
having to remember.

## Decision

**Versions:**
- **Tags:** semantic version tags `vX.Y.Z`, starting at **v0.6.0**. The 0.x
  signals a young project, and the 6 follows the six hand-delivered builds.
- **Files:** `VERSION` holds the current version, and `CHANGELOG.md` has one
  section per version.
- **In the installed extension:** `install.sh` writes a `version-name` into
  the installed `metadata.json`, which GNOME's Extensions app shows:
  - on a release tag: `X.Y.Z`;
  - otherwise: `VERSION-dev+<commit>`, plus `.dirty` if there are local
    changes.

**Releasing** with `scripts/release.sh X.Y.Z`. It refuses unless you're on a
clean `main` with a `## X.Y.Z` changelog section. It then:
1. runs every test;
2. writes `VERSION`, commits, tags `vX.Y.Z` and pushes;
3. creates the GitHub release with that changelog section as its notes.

**CI:** GitHub Actions runs on every push, pull request and tag, on Ubuntu
24.04:
- every shell script parses;
- the Python collectors compile;
- the JavaScript parses;
- the settings schema compiles;
- all test suites pass;
- on a tag, the tag matches `VERSION`.

**The update check:**
- **When:** once a day, starting a minute after login. Now every hour, and
  after waking from sleep ([0024](0024-check-for-releases-hourly.md)).
- **How:** the extension runs `agent-usage latest`, which calls
  `git ls-remote`. It never prompts for a password or host key, so it also
  works for private repositories through existing git access.
- **What you see:**
  - a newer release turns the panel's bottom line into *"vX.Y.Z available"*;
  - clicking it opens the settings;
  - the settings show the installed and newest versions, with an **Update**
    button that runs `agent-usage update --pause` in the chosen terminal
    ([0012](0012-configurable-agent-and-terminal.md));
  - a switch turns the check off.

## Alternatives

- **Ask GitHub's API for releases.** That needs a token for private
  repositories, and has rate limits of its own.
- **Check on every panel open:** needless network traffic.

## Consequences

- **Updates still need a reload** of GNOME Shell
  ([0014](0014-reloading-gnome-shell.md)). The Update button says so.
- **Only `vX.Y.Z` tags count as releases.** Other tags are ignored.
- **The macOS app checks GitHub's releases API instead,** now that the
  repository is public, and CI attaches the app to each release
  ([0021](0021-install-on-macos-from-the-release-zip.md)).
