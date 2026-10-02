# 0011. Limits are account-wide, token charts stay local, no sync

- Status: Accepted
- Date: 2026-10-02

## Context

With two machines in use, the question came up whether usage is shared
between them. It depends on the number:

- **Rate limits** (session, weekly) come from Anthropic's server for the
  signed-in account. Usage from every machine and client counts toward them,
  so all machines on one account should show the same percentages.
- **Token charts** (by day, today by model, all time) are counted from local
  files: Claude Code transcripts, the OpenCode database and Codex sessions.
  Each machine only sees its own.

Omarchy's widget has an optional sync. Each machine writes a snapshot of its
token counts (no credentials, no chat content, no limits) into a shared
folder, e.g. Syncthing or Dropbox. The panel adds them up.

## Decision

- **Keep the token charts local,** and don't port the sync for now.
- **Document** which numbers are shared and which aren't.

## Alternatives

- **Port the sync in Omarchy's file format.** Omarchy and Ubuntu machines
  could then share one folder and show combined totals. It was offered and
  not needed yet.

## Consequences

- **Different charts per machine** are expected. Different limits per machine
  (on the same account) mean something is stale
  ([0008](0008-rate-limit-back-off-and-stale-limits.md)).
- **Sync remains possible later** without changing the record format.
