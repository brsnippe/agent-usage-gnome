# Agent Usage for macOS (in progress)

The macOS menu bar version of the panel. The plan is a native Swift app; so
far this folder holds its logic.

| Piece | What it does |
|---|---|
| `Sources/AgentUsageCore/` | Everything the panel decides without a screen, ported from the GNOME extension's `usage.js`, `updates.js`, `versions.js` and `terminals.js`. Also runs the collectors itself (`Collectors.swift`), since `agent-usage-update` needs bash 4 and a Mac has bash 3.2 |
| `Tests/AgentUsageCoreTests/` | The GNOME tests, ported check for check, plus tests for the collector runner and the macOS terminals |

`AgentUsageCore` uses Foundation only, so it builds and tests on Linux too:

```bash
cd macos
swift test
```

GitHub Actions runs the same on a Mac on every push.

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
