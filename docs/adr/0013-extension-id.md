# 0013. Extension ID `agent-usage@local`

- Status: Accepted (supersedes the ID of the first extension build)
- Date: 2026-10-02

## Context

GNOME requires every extension to have a unique ID in the form
`name@domain`. By convention, the domain is one the author controls. The
first extension build used an ID based on the maintainer's GitHub domain.

- **What the ID is for:** it's only a name. It sets the extension's folder
  name and its entry in GNOME's list of enabled extensions. It isn't used to
  store or send anything.
- **Why change it:** the extension was going to be installed by colleagues
  too, and a personal name in every install wasn't wanted.

## Decision

- **The new ID** is `agent-usage@local`.
- **Migration:** `install.sh` removes earlier IDs (`OLD_UUIDS`) along with
  their enabled entries and command links.
- **Settings survive** the rename. They're stored under the settings schema
  `org.gnome.shell.extensions.agent-usage`, which doesn't depend on the ID.

## Alternatives

- **A company domain** (`agent-usage@<company domain>`): the conventional
  choice inside an organisation.
- **Keep the first ID:** it works the same.

## Consequences

- **extensions.gnome.org:** the extension couldn't be published there under
  this ID. That needs a domain you control
  ([0015](0015-distribute-via-git.md)).
- **Old IDs stay in the code:** `uninstall.sh` removes both the old and new
  IDs.
