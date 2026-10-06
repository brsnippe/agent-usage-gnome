# 0029. Installing on Cinnamon, without logging out

- Status: Accepted
- Date: 2026-10-06

## Context

The GNOME install is a git checkout plus the `agent-usage` command
([0015](0015-distribute-via-git.md)), and GNOME only loads new code when
it starts ([0014](0014-reloading-gnome-shell.md)). Cinnamon differs in two
ways that help:
- **Which applets are on which panel** is one setting,
  `org.cinnamon enabled-applets`. Each entry reads
  `panel:zone:order:uuid:instance`, and Cinnamon applies changes to it at
  once.
- **Cinnamon reloads an applet on request:** `org.Cinnamon.ReloadXlet`
  over D-Bus, from 6.0 up to 6.8.

## Decision

**The same commands.** The `get.sh` line, the clone in
`~/.local/share/agent-usage-gnome` and `agent-usage update/version/diagnose/uninstall`
all stay. `install.sh` hands over to `cinnamon/install.sh` in a Cinnamon
session (`XDG_CURRENT_DESKTOP` contains `Cinnamon`). `uninstall.sh` and
`diagnose.sh` do the same, or hand over when only the applet is installed.
The steps both installers share (packages, the version name, the usage
summary, purging data) moved into `scripts/common.sh`.

**`cinnamon/install.sh`:**
1. Checks for a Cinnamon 6.0+ session, and installs GNOME's apt packages.
2. Builds the applet into `~/.local/share/cinnamon/applets/agent-usage@local/`
   with `cinnamon/build-applet.sh`: Cinnamon's files, the collectors and
   icons, the stylesheet, and the rewritten shared modules
   ([0028](0028-shared-panel-code.md)). The version goes into
   `metadata.json` and the settings window.
3. Links `agent-usage-update` and `agent-usage`, and records the checkout,
   as on GNOME.
4. Collects usage, so the panel opens on fresh numbers.
5. **Loads it:**
   - **First install:** it adds the applet to the panel that has the status
     icons (the tray), as the first applet in its right-hand zone. It takes
     `next-applet-id` as the instance, as Cinnamon does. Cinnamon loads it
     at once.
   - **Already on a panel:** Cinnamon reloads it.
   - **Taken off the panel since:** an update leaves it off, and says how to
     add it back.
6. **Checks that it loaded,** through Looking Glass (`GetExtensionList`,
   the interface Cinnamon's own debugger uses), and says so.
   - **The error flag, not the status word:** Cinnamon translates its
     status words; *Loaded* is *Geladen* in Dutch.

**`cinnamon/diagnose.sh`** shows:
- the Cinnamon version and the Mint release;
- the applet's version, its panel entries and its settings;
- whether Cinnamon loaded it;
- its lines in Cinnamon's log (Looking Glass `GetErrorStack`, and
  `~/.xsession-errors`);
- the records, as on GNOME.

`cinnamon/cinnamon-state.py` asks Looking Glass on the scripts' behalf.

## Alternatives

- **Cinnamon Spices,** Cinnamon's applet site: public, reviewed, and an
  update channel of its own. It was left out for the same reasons as
  extensions.gnome.org ([0015](0015-distribute-via-git.md)).
- **Add the applet to the panel by hand:** one more step, and a first
  install that shows nothing.
- **Restart Cinnamon after installing:** it works, but it isn't needed.

## Consequences

- **No logout,** neither after installing nor after updating. The Update
  button's terminal finishes with the new version already in the panel.
- **The clone keeps the name `agent-usage-gnome`,** so existing installs
  keep updating.
- **`agent-usage version`** reads the applet's `version` from
  `metadata.json` (GNOME's is `version-name`).
- **`test/cli-test.sh`** runs the whole flow a second time as a Mint
  session, with stand-ins for `cinnamon`, `gsettings` and `gdbus`:
  - the panel entry, and the instance id it takes;
  - the reload on update, not being added twice;
  - an applet someone removed staying removed;
  - uninstalling.
