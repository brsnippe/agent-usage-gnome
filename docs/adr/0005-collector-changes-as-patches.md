# 0005. Changes to Omarchy's collectors live only as patch files

- Status: Accepted
- Date: 2026-10-02

## Context

The collectors come from Omarchy ([0001](0001-port-omarchy-agents-widget.md)),
which keeps improving them. This project needs some changes on top of them:

- the two upstream fixes ([0004](0004-count-opencode-v2-usage.md));
- changes of its own: the rate-limit back-off
  ([0008](0008-rate-limit-back-off-and-stale-limits.md)), and reading Claude
  Code's login from the macOS Keychain for the macOS app.

## Decision

- **The rule:** `agent-usage@local/bin/agent-usage-claude` and
  `agent-usage-codex` are Omarchy 4.0.4 plus the diffs in `patches/`, and
  nothing else.
- **The patches:**

  | Patch | Collector | Origin |
  |---|---|---|
  | `pr-13894-claude-opencode-v2.diff` | Claude | upstream PR |
  | `pr-7686-codex-opencode-v2.diff` | Codex | upstream PR |
  | `claude-limits-backoff.diff` | Claude | this project, applies after #13894 |
  | `claude-macos-keychain.diff` | Claude | this project, applies after the back-off |

- **Checking it:** when a collector changes, rebuild it from Omarchy 4.0.4
  plus the patches and compare it to the bundled file with `cmp`.
- **The wrapper** (`agent-usage-update`) is the one exception. It's a small
  rewrite of Omarchy's, which only finds the collectors next to itself.

## Alternatives

- **Edit the collectors freely.** That's simpler at first, but nobody could
  tell later what differs from upstream, or what to keep when upstream moves.

## Consequences

- **The README** explains how to switch once the PRs are merged. Take
  Omarchy's Codex collector as is. Take Omarchy's Claude collector and
  reapply `claude-limits-backoff.diff`, then `claude-macos-keychain.diff`.
- **Tests:** `test/claude-limits-test.py` and `test/claude-keychain-test.py`
  exercise the own patches.
