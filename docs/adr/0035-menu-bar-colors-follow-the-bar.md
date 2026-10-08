# 0035. The Mac's menu bar colours follow the bar they're drawn on

- Status: Accepted
- Date: 2026-10-08

## Context

The first trial on a coworker's Mac ([0022](0022-testing-the-macos-app.md))
turned up the percentage's colour. The Mac runs macOS 27 in light mode with
a dark wallpaper, on two screens. The faded percentage, while the limits
were stale ([0008](0008-rate-limit-back-off-and-stale-limits.md)), came out
dark grey on the dark menu bar. A first fix made it grey on the active
screen and white on the other.

What the menu bar does:

- **Light or dark with the wallpaper,** not with the system setting (since
  macOS 11). Light mode with a dark wallpaper gives a dark bar with white
  text. Each screen's bar decides for itself.
- **Dynamic system colours** like `labelColor` resolve when the bar draws
  them, in that bar's appearance. A fixed `NSColor` is drawn as it is, on
  every bar.
- **`withAlphaComponent` on a dynamic colour** resolves it right away, in
  the app's own appearance (light mode: black), and returns a fixed colour.
  v0.15.0 faded the percentage that way, so every bar got black at 55%.
- **`secondaryLabelColor`,** the system's own faded label, is an opaque mid
  grey in a vibrant dark appearance and white at 55% in a plain dark one.
  The bar on the active screen drew it one way, the other screen's bar the
  other.
- **The robot's session colours** ([0031](0031-session-colors.md)) are
  Kanagawa's `#ffa066` and `#98bb6c`, chosen for GNOME's always-dark bar.
  On a light bar they read at 2.0:1 and 2.2:1 against white.

## Decision

- **A dynamic colour for everything that depends on the bar,** made with
  `NSColor(name:dynamicProvider:)` and resolved when each bar draws it. The
  provider picks by `bestMatch(from: [.aqua, .darkAqua])`, so the vibrant
  appearances count as their plain ones.

  | What | Dark bar | Light bar |
  |---|---|---|
  | The faded percentage | white at 140/255, GNOME's fade | black at 140/255 |
  | The robot while a session waits | Kanagawa wave `#ffa066` | Kanagawa lotus `#cc6d00` (3.6:1 on white) |
  | The robot once a session is done | Kanagawa wave `#98bb6c` | Kanagawa lotus `#6f894e` (3.9:1 on white) |

  Kanagawa's lotus palette is its light theme, so the colours stay the
  theme's.
- **What stays fixed:** the usual percentage is `labelColor`, the system's
  own; red is `#c34043` on both bars (5.1:1 on white), and faded red is red
  with alpha, which is fixed already.
- **The tinted robot resolves its tint while it draws.** Its drawing handler
  runs in the appearance of the bar that shows it, and the image isn't
  cached, so one bar's colour isn't kept for another's. The pop
  ([0034](0034-pop-and-sounds.md)) renders the robot in the button's
  appearance before it animates.
- **The snapshots fix the colours per bar** (`resolved(in:)`), so CI's
  `menubar.png` shows the dark and the light bar each with its own.

## Alternatives

- **`secondaryLabelColor` for the fade:** differs between a vibrant and a
  plain appearance, so between screens.
- **`appearsDisabled` on the button:** AppKit's own dimming, but it dims the
  robot too, and its session colour with it. GNOME fades only the number.
- **Resolve against `button.effectiveAppearance` and redraw on change:** one
  appearance for all screens, while each screen's bar draws the item in its
  own.
- **The darker colours on every bar:** on a dark bar the wave colours read
  well and match GNOME.

## Consequences

- **The Mac's label is appearance-aware per screen,** not only per system
  setting. Anything added to it should be a dynamic colour or a fixed one
  that reads on both.
- **Two palettes for the robot** in `Theme`, wave and lotus.
- **The light-bar colours haven't been seen on a real light bar yet;** the
  snapshot shows them. Open item.
- **No automated test:** a test can't draw the menu bar. The colours were
  checked by resolving them in each appearance (aqua, dark aqua, vibrant
  light, vibrant dark) and reading the components.
