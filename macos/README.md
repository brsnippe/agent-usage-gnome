# Agent Usage for macOS

The menu bar version of the panel. How to install and use it is in the main
[README](../README.md#macos); why it's built this way is in
[docs/adr/0018](../docs/adr/0018-native-macos-app.md) to
[0022](../docs/adr/0022-testing-the-macos-app.md). This page is about
working on it.

| Piece | What it does |
|---|---|
| `Sources/AgentUsageCore/` | Everything the panel decides without a screen, ported from the GNOME extension's `usage.js`, `updates.js`, `versions.js` and `terminals.js`, plus the collector runner (`Collectors.swift`) and the update check's parsing (`Releases.swift`). Foundation only |
| `Sources/AgentUsage/` | The app: `StatusController` (menu bar item, panel window, keys), `PanelView` (the panel in SwiftUI), `AppModel` (records, timers, collectors, sleep and lock), `Settings`, `System` (login item, release check, main menu), `Snapshot` |
| `Tests/AgentUsageCoreTests/` | The GNOME tests, ported check for check, plus the collector runner, the macOS terminals and the release check |
| `Resources/` | `Info.plist` (`@VERSION@` and friends are filled in by `build-app.sh`), the icons as PDFs, JetBrains Mono |
| `build-app.sh [--zip]` | Builds `build/Agent Usage.app`, and with `--zip` `build/Agent-Usage-macOS.zip` |
| `agent-usage` | The `agent-usage` command, bundled at `Contents/Resources/bin/` |
| `test/cli-test.sh` | Installs, updates and uninstalls the built zip in a throwaway home (on a Mac) |

## Testing the logic, anywhere

`AgentUsageCore` uses Foundation only, so it builds and tests on Linux too;
the app target is only defined on macOS:

```bash
cd macos
swift test
```

On Arch, Swift's Linux build looks for Ubuntu's library names. Install it with
mise and point it at the same libraries under Arch's names:

```bash
mkdir -p ~/.local/share/swift-compat-libs && cd ~/.local/share/swift-compat-libs
ln -sf /usr/lib/libncursesw.so.6 libncurses.so.6
ln -sf /usr/lib/libformw.so.6 libform.so.6
ln -sf /usr/lib/libpanelw.so.6 libpanel.so.6
ln -sf /usr/lib/libxml2.so.16 libxml2.so.2
LD_LIBRARY_PATH=~/.local/share/swift-compat-libs mise install swift@6.3.3
cd ~/agent-usage/macos
LD_LIBRARY_PATH=~/.local/share/swift-compat-libs mise exec swift@6.3.3 -- swift test
```

The `libxml2.so.2: no version information available` warnings that prints come
from Swift's own test runner and are harmless.

## Building and trying the app, on a Mac

Needs Xcode (for the universal build and XCTest):

```bash
macos/build-app.sh
open "macos/build/Agent Usage.app"                       # the menu bar app
"macos/build/Agent Usage.app/Contents/MacOS/AgentUsage" --snapshot /tmp/shots   # PNGs of the panel
"macos/build/Agent Usage.app/Contents/MacOS/AgentUsage" --settings              # opens the settings
```

A copy run from the build folder doesn't add itself to the login items; only
one in an Applications folder does.

Without a Mac, push to a branch with a pull request: GitHub's macOS job
builds the app, runs every test, and keeps the panel's PNGs (`snapshots`)
and the app (`Agent-Usage-macOS`) as artifacts of the run.

## Changing the panel

The panel exists twice: `agent-usage@local/usage.js` for GNOME and
`Sources/AgentUsageCore/Usage.swift` here. A change to one needs the same
change to the other, and to both tests. The icons come from the GNOME SVGs:

```bash
rsvg-convert -f pdf -o macos/Resources/Icons/claude.pdf agent-usage@local/icons/claude.svg
```
