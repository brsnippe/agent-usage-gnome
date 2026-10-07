# AGENTS.md

Omarchy's Agents panel (Claude Code / Codex limits and token stats) shipped three ways: a GNOME Shell extension, a Cinnamon applet, and a native macOS app. No package manager or build step on Linux: GJS ES modules, Python collectors, bash scripts. `macos/` is a SwiftPM package. Design rationale lives in `docs/adr/` (index: `docs/adr/README.md`).

## How the code is shared

- `agent-usage@local/` is the GNOME extension **and** the shared source. `panel.js`, `usage.js`, `sessions.js`, `terminals.js`, `updates.js`, `versions.js`, `stylesheet.css` serve both GNOME and Cinnamon. `extension.js` (GNOME) and `cinnamon/agent-usage@local/applet.js` are thin hosts. GNOME-only imports (`resource:///org/gnome/shell/...`) go in the hosts, never in shared modules.
- The Cinnamon applet is generated at install time by `cinnamon/build-applet.sh DEST [VERSION]`, which rewrites the shared modules with `cinnamon/esm-to-cinnamon.py`. Never commit generated output. The converter only handles a few forms in shared modules:
  - imports on a single line;
  - exported classes closing with `}` on its own line;
  - no default exports, export lists, `import.meta` or dynamic `import()`.
  
  A new shared module has to be added to `MODULES` in `build-applet.sh`.
- Don't register GObject classes in `panel.js`. Cinnamon re-evaluates the file when the applet reloads, and a GType can only be registered once.
- `macos/Sources/AgentUsageCore/` ports the shared JS logic to Swift. A logic change in `usage.js`/`sessions.js`/`updates.js`/`versions.js`/`terminals.js` needs the same change in Swift, and in both test suites (`test/*-test.js` and `macos/Tests/AgentUsageCoreTests/`).
- Settings exist in four places: the gschema, `prefs.js`, `cinnamon/agent-usage@local/settings-schema.json` and `macos/Sources/AgentUsage/Settings.swift`. `test/cinnamon-settings-test.js` checks that keys, defaults and ranges match GNOME's.
- `agent-usage-update` runs every `agent-usage-*` in `agent-usage@local/bin/` as a collector. Keep anything else (e.g. hooks) out of `bin/`.
- Root `install.sh`, `uninstall.sh` and `diagnose.sh` hand over to `cinnamon/` when they run in a Cinnamon session.

## Collectors are patched upstream files

`agent-usage@local/bin/agent-usage-{claude,codex}` are Omarchy v4.0.4 plus `patches/*.diff`, and nothing else (ADR 0005). Make a change as a patch, then regenerate and check byte-for-byte:

```bash
curl -fsSL https://raw.githubusercontent.com/omacom/omarchy/v4.0.4/bin/omarchy-agent-usage-claude -o claude
for p in pr-13894-claude-opencode-v2 claude-limits-backoff claude-macos-keychain claude-sign-in-refused; do patch claude < patches/$p.diff; done
cmp claude agent-usage@local/bin/agent-usage-claude
# codex: omarchy-agent-usage-codex + pr-7686-codex-opencode-v2, codex-sign-in
```

`agent-usage-update` is the one exception: it's the project's own rewrite. The collectors and `hooks/agent-usage-session` must still run on **Python 3.9**, the version in macOS Command Line Tools and on the CI Mac. Keep `from __future__ import annotations`, and avoid syntax newer than 3.9.

## Working on the Omarchy dev machine

- GNOME Shell and Cinnamon aren't installed here, and `install.sh` refuses to run. To see real shell behavior, use the Docker smoke tests below.
- Omarchy's own widget reads `~/.local/state/omarchy/agents/usage/`, and shares `~/.cache/omarchy/agent-usage/` with these collectors. Before running a collector or `agent-usage-update` by hand, set `XDG_STATE_HOME` and `XDG_CACHE_HOME` to a temp dir.
- Don't run `hooks/agent-usage-session install` against the real home. It edits `~/.claude/settings.json` and `~/.config/opencode/plugins/`.

## Tests

Run from the repo root. This is the fast suite that `scripts/release.sh` and CI run; each test prints `ok`/`FAIL` lines and exits non-zero on failure:

```bash
for t in test/*-test.js; do gjs -m "$t"; done      # single: gjs -m test/usage-test.js
for t in test/*-test.py; do python3 "$t"; done
node test/opencode-plugin-test.mjs
test/cli-test.sh                                   # install/update/uninstall against a local bare repo, stand-in GNOME tools
```

Two CI checks are worth running locally after touching shared modules or the schema:

```bash
cinnamon/build-applet.sh /tmp/applet 0.0.0 && for f in /tmp/applet/*.js; do cp "$f" /tmp/check.cjs; node --check /tmp/check.cjs; done
glib-compile-schemas --strict --dry-run agent-usage@local/schemas
```

On this Arch machine, a plain `swift test` fails because mise has no global swift. Use:

```bash
(cd macos && LD_LIBRARY_PATH=~/.local/share/swift-compat-libs mise exec swift@6.3.3 -- swift test)
```

The `libxml2 ... no version information` warnings are harmless. Only `AgentUsageCore` builds on Linux. The app target, `build-app.sh` and the snapshots only run in CI's macOS job, so push to a branch with a PR to get them.

**Smoke tests (Docker):** `test/gnome/run-in-ubuntu.sh 24.04|26.04` and `cinnamon/test/run-in-mint.sh mint21.3|mint22.3|mint22.3-loader6.8`.
- They are the only way to run `panel.js`, `extension.js`, `applet.js` and the stylesheet for real. The unit tests don't load them.
- The first run builds a cached `agent-usage-test:*` image, which takes minutes.
- Screenshots go to `test/gnome/snapshots/` and `cinnamon/snapshots/` (gitignored). Check them by eye.

## Conventions

- A design change gets a new `docs/adr/NNNN-*.md`. Add it to the table in `docs/adr/README.md`, and update that file's open items. User-visible behavior is documented in `README.md`.
- Docs use short, plain sentences, bold-lead bullets and tables. Match that style.
- Commits: a plain title, then a prose paragraph that often ends with "See ADR NNNN."
- Only `scripts/release.sh X.Y.Z` writes `VERSION`. It needs a `## X.Y.Z` section in `CHANGELOG.md` and a clean `main`, and it pushes and creates the GitHub release. Don't run it unless asked. CI checks that the tag matches `VERSION`, and attaches the macOS zip on tags.
