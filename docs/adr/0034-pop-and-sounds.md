# 0034. The robot pops and sounds when a session wants you

- Status: Accepted
- Date: 2026-10-06

## Context

The session colors ([0031](0031-session-colors.md)) show what the agents
want, but only to someone who looks at the corner of the screen. While you
read in another window, or on another screen, an orange or green robot goes
unnoticed. The maintainer asked for an animation and sounds:

- **The animation:** the robot getting bigger and popping out, once.
- **The sounds:** two different ones, for a session that needs input and a
  session that's ready.
- **A setting:** both can be switched on and off.

What each platform offers:

- **GNOME and Cinnamon** both have mutter's sound player
  (`global.display.get_sound_player()`; Cinnamon's comes from Muffin, its
  fork of mutter). It plays a file through libcanberra, as an alert sound
  at the *System Sounds* volume.
  - **GNOME's** player is silent when `event-sounds` is off (*Alert Sound:
    None*).
  - **Cinnamon's** doesn't go by it in practice: Mint ships it off, and
    Cinnamon's own sounds play anyway.
- **libcanberra** reads WAV (8- or 16-bit PCM) and Ogg Vorbis. **macOS**
  plays WAV too.
- **Sound themes differ:** of the names a panel might use, only
  `dialog-warning` is in Ubuntu's Yaru, Mint's theme and freedesktop's alike.
  The rest fall back to freedesktop's, so they'd sound different on each
  machine. A Mac has its own sounds again.
- **Animations:**
  - **GNOME** makes Clutter's easing instant when animations are off, and
    switches them off without a graphics card.
  - **Cinnamon 6.6** does the same. **Cinnamon 6.0 to 6.4** don't, but say
    so in `Main.animations_enabled`.
- **A Mac's menu bar** cuts off anything drawn outside the status item's
  window, which is as tall as the menu bar and as wide as the item. AppKit
  manages the button layer's anchor and transform itself.

## Decision

- **Two switches,** under *Session colors* in the settings, on all three
  platforms. Both need session colors on: the same hooks report the
  sessions.

  | Setting | Key (GNOME/Mint · Mac) | Default |
  |---|---|---|
  | Pop the robot | `session-pop` · `sessionPop` | on |
  | Sounds | `session-sounds` · `sessionSounds` | off |

  - **The pop is on by default:** it's silent, and easy to switch off.
  - **The sounds are off:** a sound right after an update could surprise
    people in an open office.
- **When they fire** (`sessionAlert` in `sessions.js`, `Sessions.alert` in
  Swift):
  - **Per session:** a session that has started waiting for you, or
    finished a turn you haven't seen. That includes a second session
    finishing while the robot is already green.
  - **Each state once:** the panel keeps each session's state and `since`
    from the last look. The hooks keep `since` while the state stays the
    same, so a wait alerts once. A new wait, after `working`, alerts again.
  - **The colors' rules:** a subagent alerts when it waits, not when it
    finishes. A turn finished before `.seen` is quiet.
  - **Merged:** nothing alerts within 3 seconds of the last alert. Waiting
    beats ready at the same look.
  - **Quiet first look:** at start, after unlocking on GNOME (which
    re-enables the extension) and after switching session colors on, the
    panel only takes note. Nothing sounds for what was already going on.
  - **Quiet while locked:** GNOME switches extensions off then. The Cinnamon
    applet and the Mac app keep track, but stay quiet.
- **The pop on GNOME and Cinnamon:** `popActor` in `panel.js`.
  - **The movement:** it grows to 1.5× in 120 ms (ease-out), then springs
    back in 380 ms (`EASE_OUT_BACK`), around its centre.
  - **Plain Clutter easing,** the same in both shells. Only the drawing
    scales, so the bar around it doesn't move.
  - **The hosts** give it their icon. Cinnamon's checks
    `Main.animations_enabled` first, for 6.0 to 6.4.
- **The pop on a Mac:** a layer of its own over the robot.
  - **The button shows a blank image** of the robot's size while the pop
    runs, so the percentage stays put and unscaled.
  - **The movement:** 1 → 1.2 → 0.95 → 1 in 0.45 s. It only grows to 1.2×,
    so it stays inside the menu bar.
  - **Ends early** when the robot changes color. Not with *Reduce motion*
    on.
- **Our own sounds:** `waiting.wav` (a double blip, A5) and `ready.wav` (a
  rising chime, E5 then B5).
  - **Made by `scripts/make-sounds.py`** from sine waves with two
    overtones: nothing to license, and the same file every time.
  - **The format:** 16-bit PCM mono WAV at 44.1 kHz, which every platform
    plays. The loudest sample is at −6 dB, and each note fades out so it
    doesn't click.
  - **Where they live:** `agent-usage@local/sounds/`. The Cinnamon build
    and the Mac build copy them.
- **Playing them:**
  - **GNOME and Cinnamon:** `play_from_file` on mutter's player, which keeps
    GNOME's *Alert Sound: None*.
  - **Mac:** `AudioServicesPlaySystemSound`, which is silent with *Play user
    interface sound effects* off.
- **Play buttons, to try them:** *Input needed* and *Session ready*, under
  the switches in each settings window. They play a sound exactly as an
  alert does, at the same volume, also with *Sounds* switched off.
  - **GNOME:** the settings window is a process of its own, without the
    shell's sound player, so it asks GNOME Shell over D-Bus. While it's on,
    the extension exports `PlaySound(s)` on the shell's connection
    (`org.gnome.Shell`, path `/io/github/brsnippe/AgentUsage`, interface
    `io.github.brsnippe.AgentUsage`). An unknown sound gets an error back.
    With the extension off, the window says so.
  - **Cinnamon:** the settings window's buttons call the applet's
    `playWaiting` and `playReady`, inside Cinnamon.
  - **Mac:** the settings window is part of the app.

## Alternatives

- **Only when the robot changes color:** a second session finishing while
  it's green would be silent.
- **One switch for both, or one per sound:** the maintainer picked two, a
  pop and sounds.
- **The sound theme's sounds** (`message-new-instant`, `complete`; Ping and
  Glass on a Mac): nothing to ship, but they'd sound different on every
  machine, and the theme may not have them.
- **A desktop notification per turn:** a banner for every finished turn
  piles up in the message tray.
- **`actor.ease()`:** GNOME has it, and Cinnamon since 5.4. Plain easing is
  the same in both, without depending on either shell's additions.
- **`NSSound` on a Mac:** it plays whatever the sound settings say.
- **Scaling the Mac's button:** that scales the percentage too, and AppKit
  resets the layer's anchor and transform.
- **Following Mint's `event-sounds`:** Mint ships it off, so nobody on Mint
  would hear anything.
- **A player in GNOME's settings window** (`Gtk.MediaFile`): no D-Bus, but
  it plays at the window's own volume, also with alert sounds off. Trying a
  sound there wouldn't tell you whether you'll hear the alert.

## Consequences

- **Settings in four places** get two more keys: the gschema, `prefs.js`,
  `settings-schema.json` and the Mac's `Settings`. The Mac settings window
  is 90 points taller, with the play buttons.
- **GNOME Shell has a D-Bus method of ours:** any program in the session
  can have it play one of the two sounds while the extension is on. It can't
  do anything else.
- **An agent's own bell rings too:** Claude Code can ring the terminal's
  bell when it's done, and then you hear both.
- **The Mac app logs each alert** (`session alert: ready`), which CI checks
  for.
- **Tests:**
  - **The rules:** `test/sessions-test.js` and `SessionsTests.swift`, the
    same cases.
  - **The files:** `test/sounds-test.py` checks they're what the script
    makes, in the right format, short and quiet at both ends.
  - **GNOME's smoke test** (46 and 50) records the robot's size at every
    step and each sound played (for real too, into a machine without
    speakers):
    - with GNOME's animations off, as there without a graphics card, the
      pop is instant;
    - with them on, it grows to 1.5× and springs back;
    - the second alert comes after 3 seconds, so it isn't merged.
  - **Cinnamon's smoke test** (6.0, 6.6, 6.8's loading) does the same, with
    animations switched off and on by hand: Cinnamon 6.0 in the container
    has them on, without a graphics card.
  - **Screenshots:** both take `topbar-pop`, the robot at its biggest.
  - **The play buttons:**
    - **GNOME's smoke test** calls `PlaySound` as the settings window does.
      Both sounds play with *Sounds* off, an unknown one is refused without
      a line in the shell's log, nothing answers while the extension is
      switched off, and it answers again once it's back.
    - **Cinnamon's** presses them through `org.Cinnamon.activateCallback`,
      as its settings window does.
    - **The Mac's** show in the settings snapshot.
  - **Mac CI:** the app sees a session finish, logs the alert and keeps
    running.
- **Not seen yet:**
  - anyone hearing the sounds at a real volume;
  - the Mac's pop at all, since CI can't take a screenshot mid-animation;
  - GNOME's settings window with its play buttons, which the test images
    can't open: they don't have GNOME's Extensions app.
