# 0028. One panel for GNOME and Cinnamon

- Status: Accepted
- Date: 2026-10-06

## Context

Most of `extension.js` (900 lines) isn't specific to GNOME. That covers
the sections, bars and footer; the timers, the update queue and the
release check; and the sign-in follow-up. It's St, Clutter, Cairo, GLib and
Gio, which Cinnamon has too. A Cinnamon copy would make three implementations
of the panel, with the Swift one ([0018](0018-native-macos-app.md)).

The catch is the module format. GNOME 45 and up loads extensions as ES
modules (`import`/`export`). Cinnamon loads applet code with its older
`imports` system, and the details changed in 6.8:

| Cinnamon | How an applet's files load | What a file exports |
|---|---|---|
| 6.0 to 6.6 | evaluated with `require()` in scope | every top-level name |
| 6.8 | the native importer; `require()` still works but logs a deprecation | only `var` and `function` declarations |

Neither understands `import` or `export`.

## Decision

**One panel, two thin hosts:**
- **`panel.js`:** the panel (sections, bars, footer, countdowns), and what
  drives it: the records and their folder monitor, the timers, the update
  queue, release checks, waking from sleep, following a sign-in. It calls a
  small **host** for what differs:
  - the icon and percentage in the bar;
  - closing the menu, keeping its keyboard focus, scrolling it;
  - the settings window, and what *vX.Y.Z available* does;
  - notifications, opening a desktop app, starting a program;
  - optionally, the desktop's own default terminal.
- **`extension.js` (GNOME) and `cinnamon/agent-usage@local/applet.js`:** the
  button in the bar, the menu around the panel, the settings, and the host.
- **The settings** reach the panel through Gio.Settings' methods.
  Cinnamon's applet settings get a small adapter with the same names.
- **The bars** are plain `St.DrawingArea`s with a repaint handler, not a
  registered GObject subclass. Cinnamon evaluates the file again when it
  reloads an applet, and a GObject type can only be registered once.
- **Pausing while locked** lives in the panel (`setLocked`). Only Cinnamon
  calls it ([0027](0027-cinnamon-applet-for-linux-mint.md)).

**The shared modules stay ES modules** (`usage.js`, `updates.js`,
`versions.js`, `terminals.js`, `panel.js`). GNOME and the tests use them as
they are. **`cinnamon/esm-to-cinnamon.py` rewrites them** when the applet is
built:

| ES module | For Cinnamon |
|---|---|
| `import Gio from 'gi://Gio';` | `const Gio = imports.gi.Gio;` |
| `import * as Usage from './usage.js';` | `const Usage = _load('usage');` |
| `import {isNewer} from './versions.js';` | `const {isNewer} = _load('versions');` |
| `export function f` | `function f` |
| `export const X` | `var X` |
| `export class C { … }` | `var C = class C { … };` |

- **`_load`:** a few lines that use 6.8's
  `getCurrentExtension().imports` when it exists, and `require()` before
  that. 6.8 then loads the applet without deprecation warnings.
- **Refusals:** anything else that imports or exports is refused: a
  default export, an export list, an import over several lines,
  `import.meta`, a dynamic `import()`. A new form fails when the applet is
  built, not in the panel.
- **A completeness check:** `cinnamon/build-applet.sh` checks that every
  module the applet or a rewritten module loads was built.
- **Generated, not committed:** the rewritten files are made at install
  time and never committed, so there's one source per module.

## Alternatives

- **A Cinnamon copy of `extension.js`:** GNOME stays untouched, but every
  panel change has to be made three times.
- **Write the shared modules in the old format:** GNOME's ES modules can't
  import those.
- **Dynamic `import()` from Cinnamon's side:** asynchronous at start-up,
  and nothing in Cinnamon's own applets uses it.
- **Commit the rewritten modules:** they would drift from the originals.

## Consequences

- **A panel change is made once for Linux,** and once more in Swift.
- **GNOME's code changed shape** without changing behaviour. A headless
  GNOME Shell now checks it in CI, on GNOME 46 and 50
  ([0030](0030-testing-in-real-shells.md)).
- **The shared modules keep to what the converter knows:**
  - imports on one line;
  - exported classes closing with a `}` on its own line;
  - no default exports.

  `test/cinnamon-modules-test.js` loads the rewritten modules both ways
  Cinnamon does and compares their exports and answers with the originals.
- **Shared stylesheet fixes reach both desktops,** such as the font
  ([0030](0030-testing-in-real-shells.md)).
