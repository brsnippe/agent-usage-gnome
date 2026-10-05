# 0026. The all-time token total in the All time heading

- Status: Accepted
- Date: 2026-10-05

## Context

The panel showed tokens by day, today by model and the top 4 models of all
time ([0010](0010-model-sections.md)), but no all-time total. Adding up the
four rows doesn't give it either: models past the fourth are left out.

The records already have what a total needs:

- **`modelUsage`:** the in/out/cache counts for every model, of which the
  panel shows 4.
- **`totalSessions`, `totalPrompts`, `activeDays`:** all-time counts the
  panel didn't use yet.

## Decision

- **The total goes in the heading:** `ALL TIME BY MODEL · 1.2B`. It's the
  sum over every model in `modelUsage`, counted like the rows: input,
  output, cache read and cache write.
- **Per agent:** each tab shows its own agent's total, like every other
  number in the panel.
- **Hovering the heading** puts the counts in the bottom line:
  *412 sessions · 9.8K prompts · 38 days*.
  - Counts above 999 are shortened the way tokens are.
  - Zeros are left out, and so are prompts and sessions for agents without
    prompt stats (`hasPromptStats: false`), as on the day rows.
  - With no counts at all, the heading has no hover.

## Alternatives

- **A *Total* row above the models,** like *Prepaid credits* under Balance:
  one more row of height for a single number.
- **A separate ALL TIME section** with the counts as rows: taller still.
- **One total across all agents:** the same number on every tab, unlike the
  rest of the panel.
- **Input and output only:** much smaller and closer to Claude Code's
  `/stats`, but it wouldn't add up to the model rows below it.
- **The total's in/out/cache split on the heading's hover:** with the counts
  it comes to about 70 characters, and the bottom line holds about 55. Each
  model row already shows its own split, so the counts got the space.

## Consequences

- **The total is mostly cache reads.** That's why it's far above `/stats`,
  and why it matches the rows.
- **"Prompts" are the collectors' count:** model replies with usage, not the
  messages you type. The *Today* hover counts them the same way.
- **For Codex, "all time" is about the last 30 days.** Its collector only
  reads Codex sessions and OpenCode usage from the last 30 days; only pi/omp
  sessions go back further. That was already true of the rows. The README
  says so.
- **`allTimeTotal`, `allTimeTitle` and `allTimeDetail`** are in `usage.js`
  and `Usage.swift`. `modelRows` still caps the list at 4.
