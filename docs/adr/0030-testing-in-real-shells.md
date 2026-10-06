# 0030. Test the panels in real shells, in Docker

- Status: Accepted (extends [0017](0017-testing-without-gnome-shell.md))
- Date: 2026-10-06

## Context

Until now, GNOME code only ran on the maintainer's laptop
([0017](0017-testing-without-gnome-shell.md)), and no Mint machine was at
hand at all. The Cinnamon port also reshaped GNOME's code
([0028](0028-shared-panel-code.md)), which needed a retest.

Three things made real shells possible:
- **Docker** on the development machine and on GitHub's runners.
- **Mint's own Docker images** (`linuxmintd/mint21.3-amd64`, …), which
  install Cinnamon from Mint's repositories. Cinnamon runs on a virtual
  screen (Xvfb). Its Looking Glass D-Bus interface runs JavaScript inside
  Cinnamon (`Eval`), and its screenshot interface needs no permission.
- **GNOME Shell 46 and up runs headless** (`--headless --virtual-monitor`).
  Its hidden `--unsafe-mode` opens up `org.gnome.Shell.Eval` and screenshots.
  The only thing a container lacks for it is logind, and a stand-in that
  owns the name is enough.

## Decision

**Two smoke tests, each in the shell's own distribution:**

| Test | Where | Versions |
|---|---|---|
| `cinnamon/test/smoke-test.sh` | Mint's images | Mint 21.3 (Cinnamon 6.0), 22.3 (6.6), and 22.3 with 6.8's applet loading |
| `test/gnome/smoke-test.sh` | Ubuntu's images | 24.04 (GNOME 46), 26.04 (GNOME 50) |

**Each one, as a normal user:**
- installs with the real `install.sh`, then checks that the shell loaded
  the panel without errors;
- swaps in `test/fake-collector`, whose records fill every section, and
  refreshes;
- looks inside the shell to check:
  - the percentage in the bar, and the tabs;
  - the panel's eleven parts, and the header's buttons;
  - the problem card's **Sign in**;
  - the font;
  - that a right click opens a stand-in agent in the terminal from the
    settings;
  - that the shell logged no errors;
- saves screenshots of the panel (and of Cinnamon's settings window).

**The Cinnamon test also checks:**
- the applet is on the panel once;
- a settings change reaches the panel;
- a reinstall reloads it;
- no deprecation warnings.

**The GNOME test also checks** that nothing is in the top bar before there's
usage.

**Mint 23 before its release:** Mint already took the image's 6.8
development packages off its servers. The third Cinnamon variant therefore
puts 6.8's way of loading applets onto 6.6: the two commits that changed it,
fetched from Cinnamon's repository by hash, minus the removal of the old
loader. That's the part of 6.8 the applet depends on
([0028](0028-shared-panel-code.md)).

**Where they run:**
- **Locally:** `cinnamon/test/run-in-mint.sh` and
  `test/gnome/run-in-ubuntu.sh`. The image with the shell installed is kept,
  so later runs take seconds.
- **In CI:** the `cinnamon` and `gnome` jobs, with the screenshots as
  artifacts. Both run `prepare-*.sh`, which installs the shell, starts a
  system bus, creates a user and runs the test.

## Alternatives

- **Install Cinnamon and GNOME Shell on the development machine:** the
  reasons of [0017](0017-testing-without-gnome-shell.md) still hold, and
  the containers are throwaway.
- **Compare screenshots pixel by pixel:** fonts and shell versions change
  the rendering, so they're checked by eye, as on macOS
  ([0022](0022-testing-the-macos-app.md)).
- **Wait for a coworker's report:** it's still needed for what a container
  can't show, but not for whether it loads.

## Consequences

- **Found by these tests before anyone installed the port:**
  - **The panel's font.** St accepts a quoted family only as the first in a
    `font-family` list. The panel's second, quoted name made GNOME and
    Cinnamon drop the whole list, which is why the panel rendered in the
    system font on Ubuntu ([0003](0003-gnome-shell-extension.md)). The names
    are now unquoted.
  - **Cinnamon 6.6's settings don't watch their file;** the settings window
    tells Cinnamon over D-Bus. The test does the same.
  - **A session bus started before `XDG_RUNTIME_DIR` is set** leaves dconf's
    service and its readers looking in different places, and Cinnamon
    never sees `enabled-applets` change. Only a test environment can get
    this wrong; the tests set it first.
- **What's simulated:** clicks and keys go to the handlers through `Eval`,
  not through a pointer. Sleep, waking, the locked screen, real terminals
  and Mint's themes still need a person.
- **CI takes longer:** each job installs a shell, a few minutes.
- **Mint 23 itself** gets tested once its images can install Cinnamon 6.8.
