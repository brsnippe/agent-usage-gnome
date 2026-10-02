# 0019. Read Claude Code's login from the macOS Keychain

- Status: Accepted
- Date: 2026-10-02

## Context

The Claude collector reads Claude Code's OAuth token from
`~/.claude/.credentials.json`. On macOS, Claude Code keeps it in the login
Keychain instead. The file only appears there when the Keychain refused the
write. Without a fix, a Mac shows no Claude limits.

The Keychain entry's name isn't fixed:

- **The default folder:** `Claude Code-credentials`.
- **With `CLAUDE_CONFIG_DIR` (or `CLAUDE_SECURESTORAGE_CONFIG_DIR`) set:**
  `Claude Code-credentials-` plus the first 8 hex digits of the folder's
  SHA-256. That's Claude Code's own rule, as reported in
  [thedotmack/claude-mem#4149](https://github.com/thedotmack/claude-mem/issues/4149).
- **Leftovers:** some versions used the hashed name for the default folder
  too, and a login that moved leaves the old entry behind, expired
  ([robinebers/openusage#423](https://github.com/robinebers/openusage/issues/423)).

## Decision

- **A patch of this project's own,** `patches/claude-macos-keychain.diff`,
  applied after the back-off patch ([0005](0005-collector-changes-as-patches.md)).
- **The lookup:** on macOS, the collector runs
  `/usr/bin/security find-generic-password -s <name> -w` for each candidate
  name:
  - for the default folder, both the plain and the hashed name;
  - with either variable set, only that folder's entry, as the CLI itself
    does.
- **The file still counts:** of all the logins found, Keychain and file, the
  one that expires last wins.
- **Hex:** `security -w` prints a secret holding non-ASCII text as hex, which
  is decoded.
- **The token goes nowhere but the limits request,** as before.
- **On Linux nothing changes:** there's no `security` to ask.

## Alternatives

- **Have the Swift app read the Keychain and pass the token on:** that splits
  the sign-in logic across two languages, and the collector would no longer
  work on its own on a Mac.
- **Only the plain name:** misses the hashed entries.

## Consequences

- **Tests:** `test/claude-keychain-test.py` replaces `security` with a fake
  one. It runs on Linux, and in CI with the Mac's own Python.
- **Reading is silent today.** Claude Code creates its entry with
  `/usr/bin/security`, which puts that tool on the entry's access list. If a
  Claude Code version binds the entry to its own signature instead, macOS
  will ask once, and the answer must be *Always Allow*. The coworker trial
  watches for this.
- **`CLAUDE_CONFIG_DIR` set only in a shell:** the app, started at login,
  doesn't see it and reads the default profile.
- **Not for upstream:** Omarchy runs on Linux only.
