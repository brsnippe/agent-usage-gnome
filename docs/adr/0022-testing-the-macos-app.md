# 0022. Test the macOS app without a Mac

- Status: Accepted
- Date: 2026-10-02

## Context

As with GNOME ([0017](0017-testing-without-gnome-shell.md)), the
development machine can't run the target. This time there isn't even a
target machine at hand: the maintainer has no Mac, coworkers do.

## Decision

**The logic in `AgentUsageCore`,** Foundation only, with XCTest:
- **Where it runs:** on Linux with Swift 6.3 through mise (on Arch it needs
  a few library symlinks, see `macos/README.md`), and on macOS in CI.
- **What it covers:**
  - the GNOME tests, ported check for check;
  - the collector runner, with shell scripts as fake collectors, including
    one that hangs;
  - the terminals, on a fake Mac;
  - the release check.
- **Parity:** during the port, `usage.js` and the Swift code were run over
  the same real records and gave identical output.

**GitHub's Macs as the build machine.** The macOS job runs on every push and
pull request:

| Step | Checks |
|---|---|
| `swift test` | the logic |
| collector tests with `/usr/bin/python3` | Python 3.9, as a Mac has it |
| `macos/build-app.sh --zip` | it compiles for both architectures, and the signature verifies |
| `--snapshot` | PNGs (artifact `snapshots`) of the panel from sample records, the menu bar label and the settings window |
| the app starts and collects | the real app finds Python and its collectors, and their records land |
| `macos/test/cli-test.sh` | install, update and uninstall, in a throwaway home folder |

The app zip is kept too (artifact `Agent-Usage-macOS`), for early testers.

**Work on a branch,** with a draft pull request, so the many CI round trips
don't land on `main`.

**What only a person can check:** clicking, how the panel window behaves,
the terminals, Keychain prompts, start at login, sleep and wake. A coworker
installs a release and sends `agent-usage diagnose` and a screenshot.

## Alternatives

- **Rent a Mac in the cloud:** it costs money, and CI covers most of what it
  would.
- **Skip the automated tests:** every round trip would then go through a
  coworker.

## Consequences

- **Snapshots are checked by eye,** not compared pixel by pixel: fonts and
  macOS versions change the rendering.
- **The settings snapshot puts the real window on screen,** because
  SwiftUI's `ImageRenderer` can't draw AppKit's controls.
- **Found by these checks before any Mac user saw the app:**
  - a hung collector that ignored SIGTERM;
  - GitHub's API limit for the update check;
  - layout problems in the settings window;
  - a command wrapping across two lines in the panel.
