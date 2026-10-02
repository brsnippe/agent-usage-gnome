# 0010. All-time top 4 models, plus today by model

- Status: Accepted
- Date: 2026-10-02

## Context

Like Omarchy's, the panel listed the top 4 models by **all-time** tokens. On
a machine with a long history, the newest model was missing (Opus 5.5 among
Opus 5, 4.8, 4.7 and 4.5). It was in use every day, but its all-time total
was still below the fourth model's. That's correct behaviour, but it hid
what was being used now.

The records already include today's tokens per model (`todayTokensByModel`),
for Claude and Codex. They have only a total per model, not the
input/output/cache split.

## Decision

- **Keep the all-time list as Omarchy has it** (top 4, split on hover),
  renamed **All time by model**.
- **Add Today by model:**
  - every model with tokens today, heaviest first, up to 6;
  - the same row style;
  - the share of the day's total on hover, which still counts models past
    the cap;
  - hidden when today has no usage yet.

## Alternatives

- **Always include today's models in the all-time list.** It mixes two time
  frames, and a model used yesterday would still drop out at midnight.
- **Have the extension remember per-model usage for the last 7 days.** That
  needs its own state file, which starts empty.
- **Show every model, with scrolling.** The panel gets long with a long
  history.

## Consequences

- There is no per-model breakdown between "today" and "all time".
- The panel is taller, so it can scroll on small screens
  ([0009](0009-details-in-the-footer.md)).
