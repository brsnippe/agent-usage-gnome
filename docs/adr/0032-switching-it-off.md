# 0032. Switching it off: ⏻ in the panel

- Status: Accepted
- Date: 2026-10-06

## Context

There was no clear way to stop Agent Usage:

- **On a Mac** it's a menu bar app with no Dock icon. *Quit* was at the
  bottom of the settings window, and ⌘Q only worked while that window was in
  front. Most menu bar apps have Quit in the menu under their icon.
- **On GNOME** it isn't an app but an extension inside GNOME Shell. Stopping
  it means switching the extension off in the Extensions app.
- **On Linux Mint** it's an applet. The only way to stop it is to take it off
  the panel, through panel edit mode or System Settings → Applets.

On both Linux desktops the panel itself had no way to stop it. An empty panel
("No AI coding subscriptions found") had no buttons at all, not even ⚙. On a
Mac and on Mint you can open one, because the robot is always there.

Two things in the shells decided how it's done:

- **GNOME:** `Main.extensionManager.disableExtension(uuid)` does what the
  Extensions app does. It takes the extension out of `enabled-extensions`
  and puts it in `disabled-extensions`, which takes precedence, so it stays
  off after the next login. GNOME 46 has it.
- **Cinnamon:** its own *Remove* calls
  `AppletManager._removeAppletFromPanel(uuid, instanceId)`, from 6.0 on. It
  deletes the applet's settings only when the applet allows more than one
  instance. This one allows a single instance, so Cinnamon keeps its settings
  in `agent-usage@local.json`, whatever instance number it gets when it's
  added back.

## Decision

- **A ⏻ button after ⚙** in the panel's header, and the `q` key while the
  panel is open. An empty panel gets a row with just ⚙ and ⏻.
- **Each platform's own "off":**
  - **Mac:** quit (`NSApp.terminate`). It starts again at the next login, or
    from Spotlight or Finder. ⌘Q in the open panel quits too. The Quit
    button in the settings stays.
  - **GNOME:** switch the extension off, as the Extensions app would. The
    switch happens once the click is done, because it destroys the button.
  - **Mint:** take the applet off the panel, as Cinnamon's *Remove* does.
- **Asking first, on Linux only:** a card under the header, in the style of
  the problem card. It says what switching off means there, with
  **Switch off** and **Cancel**. Switch off gets the keyboard focus, so `q`
  and then Enter switch off. Closing the panel or pressing Cancel dismisses
  the card. On a Mac reopening is one search away, so it quits without
  asking, as menu bar apps do.
- **A notification** on Linux says how to switch it back on: the Extensions
  app or `gnome-extensions enable agent-usage@local` on GNOME, and on Mint
  right-click the panel, *Applets*, then *Agent Usage*.
- **Names:** *Quit (q)* on a Mac, *Switch off (q)* on Linux, for what the
  button does there.
- **Nothing else changes:** settings, usage data and the session colors'
  hooks stay. Switching off isn't uninstalling.

## Alternatives

- **A Mac-only button:** Linux already has the desktop's own switches. But
  they're buried, the panel is shared by GNOME and Cinnamon, and the three
  platforms have kept the same buttons so far.
- **Off until the next login only:** hide the robot and stop checking, but
  stay switched on. On GNOME the extension would have to remember it across
  the screen lock, which switches extensions off and on. And the only way
  back sooner would be logging out.
- **No question, anywhere:** on Linux, a stray click would leave you looking
  for the Extensions app or the Applets list.
- **A question on a Mac too:** reopening is easy there, and no other menu
  bar app asks.
- **A Quit line at the bottom of the panel,** like the last item in a menu:
  the bottom line already holds the details and the update notice.
- **Only a key:** nothing to see, so nobody would find it.
- **Removing the session colors' hooks on switching off:** turning it back
  on would then have to put them back, and in the meantime the agents
  wouldn't notice anything either way.

## Consequences

- **The host gets `quitPrompt()` and `quit()`** in `panel.js`. GNOME's and
  Cinnamon's each supply their own text and way of switching off.
- **Updates differ:** on GNOME an update or reinstall switches the extension
  back on, because `install.sh` enables it. On Mint an update leaves the
  applet off the panel, as it already did for one taken off by hand.
- **Rebuilding the panel moves the keyboard focus to the panel first.**
  Cinnamon closes a menu whose focus disappears, which happened when Cancel
  rebuilt the panel and destroyed the focused Switch off button.
- **`agent-usage diagnose`** on GNOME shows `disabled-extensions` too.
- **Tests:** the smoke tests open the card, cancel it, open it with `q`,
  switch off, and switch back on. That's `gnome-extensions enable` on GNOME,
  and adding the applet back on Mint, with its settings checked. Both take a
  screenshot of the card (`panel-switch-off`). The Mac's ⏻ shows in the
  `panel-claude` and `panel-empty` snapshots.
