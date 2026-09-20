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
2. Copy `.env.example` to `.env`, fill it locally, and set mode `0600`.
3. Copy `SERVICE-PROFILE.example.yaml` to a local profile and describe the
   service.
4. Follow [RUNBOOK.md](RUNBOOK.md).
5. Use the n8n and Suwayomi examples as patterns rather than literal exports.

```bash
cp .env.example .env
chmod 600 .env
cp SERVICE-PROFILE.example.yaml SERVICE-PROFILE.local.yaml
```

The local `.env` and `*.local.yaml` files are ignored by Git. They may contain
site-specific values, but secret values must never be printed in logs, chat, or
deployment records.

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

The examples are sanitized and canonicalized. They document useful patterns,
not the exact configuration or inventory of any live system.

## Security

Do not commit `.env`, API tokens, passwords, Tailscale authentication keys,
application encryption keys, certificates, private keys, database dumps, or
live deployment inventories. A public repository is not a secret store.
