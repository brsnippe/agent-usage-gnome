# 0004. Count OpenCode v2 usage by applying the upstream fixes

- Status: Accepted
- Date: 2026-10-02

## Context

The collectors also count Claude and OpenAI usage that went through
OpenCode. They read it from `~/.local/share/opencode/opencode.db`, but only
from the v1 `message` table. OpenCode v2 writes to `session_message` instead,
and the row shape differs:

- The role is in the `type` column, not in `data.role`.
- The provider and model sit under `data.model` (`providerID`, `id`).
- `data.tokens` and `data.time.created` are unchanged.

So none of OpenCode v2's usage was counted. This was reported as
[omacom/omarchy#13893](https://github.com/omacom/omarchy/issues/13893). Fixes
came from two PRs:

- [#13894](https://github.com/omacom/omarchy/pull/13894) for the Claude
  collector. It reads both tables and keys v2 sessions as `opencode-v2:<id>`.
- The already open [#7686](https://github.com/omacom/omarchy/pull/7686) for
  the Codex collector. It also reads v2, and limits OpenCode usage to the
  last 30 days.

## Decision

Apply both PRs exactly as written, as patch files on top of Omarchy 4.0.4
([0005](0005-collector-changes-as-patches.md)).

**Verification:** the patched Claude collector was run against a real
OpenCode v2 database.
- It counted 74 prompts where the unpatched one counted 1.
- Its per-message token sums matched OpenCode's own per-message figures.
- OpenCode's per-session totals came out slightly higher, because they also
  include replies from OpenCode's own models. The collector correctly
  leaves those out.

## Alternatives

- **Write a fix of our own:** that would diverge from what upstream is
  likely to merge.
- **Wait for the merge:** usage through OpenCode v2 would stay invisible
  until then.

## Consequences

- **Codex:** OpenCode usage on the OpenAI provider only counts the last 30
  days, by #7686's design.
- **OpenCode Zen and Go:** usage on OpenCode's own providers (e.g.
  `big-pickle`) is counted by neither collector.
- **After the merge:** switch to Omarchy's collectors (see the README and
  [0005](0005-collector-changes-as-patches.md)).
