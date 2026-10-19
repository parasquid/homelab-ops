# Service deployment guides

These pages are build guides for reference service designs. They explain how
to make and verify a choice without reporting any site's current state.

Read the [shared operating standards](../standards.md) first. Use the
[runbook](../../RUNBOOK.md) for common provisioning and recovery procedures.
The standards page owns shared requirements; each guide below owns only its
application's choices, exceptions, integrations, and additional checks. Combine
those checks with the runbook's shared acceptance procedure. Update the
canonical procedure when it changes and link it here instead of copying it.

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

- [Immich](immich.md)
- [n8n](n8n.md)
- [Persistent browser workspaces](browser-workspaces.md)
- [Seafile](seafile.md)
- [Suwayomi](suwayomi.md)
- [Vaultwarden](vaultwarden.md)
