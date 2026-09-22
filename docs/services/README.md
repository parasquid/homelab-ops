# Service notes

These pages record the reusable decisions behind each service shape. They are
sanitized references for operators and agents, not exports of live systems.

Each page should explain:

- the selected VM, storage, network, encryption, update, and backup shape;
- why those choices fit the service and what operational consequences follow;
- bootstrap and agent-access dependencies;
- failures or gotchas worth avoiding on the next deployment; and
- the acceptance checks that prove the design works.

Live domains, addresses, usernames, VM IDs, credential-item names, paths tied
to one workstation, secret values, and transient health output belong only in
the ignored inventory and per-service handoff.

- [n8n](n8n.md)
- [Suwayomi](suwayomi.md)
- [Vaultwarden](vaultwarden.md)
