# 0015. Distribute via git with `get.sh` and the `agent-usage` command

- Status: Accepted
- Date: 2026-10-02

## Context

Builds 1–6 were delivered as a tarball. Each one meant copying the file,
unpacking it and running `install.sh`, and the goal was something people can
install and update with one command. The options:

| Option | Install and update | Downsides |
|---|---|---|
| Git repository plus a small command | one command, then `agent-usage update` | updates are a command, not `apt upgrade` |
| `.deb` plus an apt repository | `apt install`, then `apt upgrade` | needs a signing key and apt hosting; installs system-wide with sudo, and a copy in the home folder would override it |
| extensions.gnome.org | GNOME's Extensions app, automatic updates | the review is strict about bundled scripts like the Python collectors; it's public; it needs a domain-based ID ([0013](0013-extension-id.md)) |

## Decision

**A git repository on GitHub. First install:**
```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/agent-usage-gnome/main/get.sh | bash
```
`get.sh` clones the repository into `~/.local/share/agent-usage-gnome`,
checks out the newest release tag and runs `install.sh`. Run from inside an
existing clone, it installs from that clone's remote instead.

**The `agent-usage` command** (`bin/agent-usage`, linked into
`~/.local/bin`):

| Command | Does |
|---|---|
| `update` | install the newest release |
| `update --main` | install the latest commit on `main` instead |
| `update --reinstall` | reinstall even when up to date |
| `update --pause` | wait for Enter at the end (used by the Update button) |
| `version` | show the installed and newest versions |
| `latest` | print the newest release |
| `diagnose` | run `diagnose.sh` |
| `uninstall` | remove the extension and the clone |

**Private, then public:** the repository started private. Then everyone
installing needed GitHub access, plus `gh auth login` with git credentials,
or an SSH key. It was later made public, so installing and updating need no
GitHub account at all.

## Alternatives

See the table above. The `.deb` and extensions.gnome.org routes cost more
than they give for a handful of users.

## Consequences

- **`update` won't touch a clone with local changes.**
- **`update` runs from the clone it updates.** The whole script is wrapped in
  `main()`, which bash reads in full before running. Checking out the new
  version therefore can't change the script while it runs.
- **Tarball installs still work** (`./install.sh`), but can't update
  themselves.
- **`test/cli-test.sh`** checks the whole flow against a local bare
  repository ([0017](0017-testing-without-gnome-shell.md)).
