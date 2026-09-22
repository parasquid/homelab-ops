# Homelab Ops

An agent-facing runbook for deploying private services as virtual machines on a
Proxmox homelab. It captures repeatable house conventions while leaving
service-specific choices in a small deployment profile.

The default pattern is:

```text
Proxmox VM -> Debian -> Docker Compose -> loopback application port
                                              ^
                                              |
Tailscale -> DNS-only hostname -> Caddy HTTPS-+
```

Services are private to the tailnet unless their profile explicitly requires
another exposure mode.

## Start here

1. Read [AGENTS.md](AGENTS.md).
2. If present, read the ignored `AGENTS.local.md` and `inventory.local.yaml`.
3. Copy `.env.example` to `.env`, fill it locally, and set mode `0600`.
4. Copy the local context templates, fill them with site-specific facts, and
   set both files to mode `0600`.
5. Copy `SERVICE-PROFILE.example.yaml` to a local profile and describe the
   service.
6. Follow [RUNBOOK.md](RUNBOOK.md).
7. Use the n8n, Suwayomi, and Vaultwarden examples as patterns rather than
   literal exports.

```bash
cp .env.example .env
chmod 600 .env
cp AGENTS.local.md.example AGENTS.local.md
cp inventory.local.yaml.example inventory.local.yaml
chmod 600 AGENTS.local.md inventory.local.yaml
cp SERVICE-PROFILE.example.yaml SERVICE-PROFILE.local.yaml
```

The local `.env`, `AGENTS.local.md`, `inventory.local.yaml`, and other
`*.local.yaml` files are ignored by Git. They may contain site-specific values,
but secret values must never be printed in logs, chat, or deployment records.

## Repository scope

Version 1 covers full virtual machines, Debian cloud images, Docker Compose,
Tailscale SSH, Caddy, and Cloudflare DNS validation. LXC, public ingress,
clustered applications, and full infrastructure-as-code are intentionally out
of scope until a real deployment needs them.

## Examples

- [EXAMPLE-n8n.md](EXAMPLE-n8n.md) shows a stateful web application with a
  database and a version-coupled task runner.
- [EXAMPLE-suwayomi.md](EXAMPLE-suwayomi.md) shows a media-oriented application
  following a rolling preview channel with daily container updates.
- [EXAMPLE-vaultwarden.md](EXAMPLE-vaultwarden.md) shows a private password
  manager with internal Mailpit capture, guest LUKS, and a locked-boot handoff.

The examples are sanitized and canonicalized. They document useful patterns,
not the exact configuration or inventory of any live system.

Before publishing, copy `.publication-denylist.example` to the ignored
`.publication-denylist`, add one exact site-specific value per line, set mode
`0600`, and run:

```bash
./scripts/check-publication.sh
```

The check rejects tracked local/private paths, scans every tracked file for the
ignored exact-value denylist, and checks common secret patterns. It does not
embed live identifiers in the repository.

The repository includes the generic
[`scripts/unlock-from-vaultwarden.sh`](scripts/unlock-from-vaultwarden.sh)
helper and [`unlock-from-vaultwarden.conf.example`](unlock-from-vaultwarden.conf.example).
Copy the configuration template to an ignored location, fill in the local
references, and set it to mode `0600`. The configuration is sourced as trusted
Bash; it must be operator-controlled and contain secret references rather than
secret values.

## Security

Do not commit `.env`, API tokens, passwords, Tailscale authentication keys,
application encryption keys, certificates, private keys, database dumps, or
live deployment inventories. A public repository is not a secret store.
