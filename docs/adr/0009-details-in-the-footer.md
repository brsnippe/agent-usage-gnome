# 0009. Details in the footer instead of tooltips; scroll instead of overflow

- Status: Accepted
- Date: 2026-10-02

## Context

Omarchy's panel shows extra detail in tooltips:
- a day's prompts and sessions;
- a model's input, output and cache split.

GNOME Shell's toolkit (`St`) has no tooltips. And as sections were added, the
panel could grow taller than a small screen.

## Decision

- **Hover details:** hovering a row puts its detail in the panel's bottom
  line:
  - day rows: tokens, plus prompts and sessions for today;
  - all-time model rows: the in/out/cache split;
  - today's model rows: their share of the day;
  - header buttons: what they do.
- **The bottom line otherwise** shows *Updated HH:MM*, *Refreshing…*, or a
  new-release notice ([0016](0016-versions-releases-and-update-check.md)).
- **Scrolling:** the panel sits in an `St.ScrollView`. When there's room it
  takes its full height and looks unchanged. It only scrolls once the menu
  reaches the maximum height GNOME sets to keep panel menus on screen. That's
  the same mechanism GNOME's own scrollable menus use. Opening the panel or
  switching tabs scrolls back to the top.

## Alternatives

- **Hand-made tooltip popups:** more code, and they fight with the menu's
  pointer grab.
- **Show all details at once as extra lines:** the panel gets busy and much
  taller.

## Consequences

- Only one detail is visible at a time.
- The panel never changes size while you move the pointer.
