# Service deployment guides

These pages are build guides for reference service designs. They explain how
to make and verify a choice without reporting any site's current state.

Each page should explain:

- VM, storage, network, encryption, update, and backup options for the design;
- why those choices fit the service and what operational consequences follow;
- bootstrap and agent-access dependencies;
- generic failure modes and how to avoid or recover from them; and
- the acceptance checks that prove the design works.

The public page must not say which options a particular deployment selected,
what changed there, or which checks passed. Live domains, addresses, usernames,
VM IDs, credential-item names, workstation paths, secret values, and status
belong only in the ignored inventory and per-service handoff.

- [n8n](n8n.md)
- [Suwayomi](suwayomi.md)
- [Vaultwarden](vaultwarden.md)
