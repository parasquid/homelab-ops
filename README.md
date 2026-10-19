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
2. Read the [shared operating standards](docs/standards.md) and, if present,
   the ignored `AGENTS.local.md` and `inventory.local.yaml`.
3. Copy `.env.example` to `.env`, fill it locally, and set mode `0600`.
4. Copy the local context templates, fill them with site-specific facts, and
   set both files to mode `0600`.
5. Copy `SERVICE-PROFILE.example.yaml` to a local profile and describe the
   service.
6. Follow [RUNBOOK.md](RUNBOOK.md).
7. Read the matching page under [`docs/services/`](docs/services/) for the
   design decisions, consequences, gotchas, and acceptance checks.

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
OpenSSH over Tailscale, Caddy, and Cloudflare DNS validation. LXC, public ingress,
clustered applications, and full infrastructure-as-code are intentionally out
of scope until a real deployment needs them.

## Service deployment guides

- [Immich](docs/services/immich.md) shows a private photo library with separate
  media and database storage, compatible container releases, and guarded updates.
- [n8n](docs/services/n8n.md) shows a stateful web application with a
  database and a version-coupled task runner.
- [Suwayomi](docs/services/suwayomi.md) shows a media-oriented application
  with an optional preview-channel variant and guarded daily container updates.
- [Vaultwarden](docs/services/vaultwarden.md) shows a private password
  manager with internal Mailpit capture, guest LUKS, and a locked-boot handoff.
- [Codex Remote Control](docs/codex-remote-control.md) documents a reusable
  immutable-Linux and per-user systemd setup for the standalone Codex CLI.
- [Claude Code Remote Control](docs/claude-remote-control.md) covers making
  a workstation a Remote Control host with a supervised per-user systemd unit,
  plus its update, verification, and failure-mode checks.
- [Cloudflare Workers Builds](docs/cloudflare-workers-builds.md) covers
  reusable Hugo build diagnosis, authorized deployment, and live verification.
- [Static blog retirement](docs/static-blog-retirement.md) covers article and
  media mapping, redirect previews, hostname cutover, and recovery.

The notes are build guides: they explain reference choices, their tradeoffs,
setup steps, and acceptance checks. They do not report a deployment's chosen
values, status, history, or test results. Those facts belong in ignored local
profiles, inventory, and handoffs.

The [standards page](docs/standards.md) is the entry point for shared access,
LUKS, Vaultwarden/Bitwarden CLI, DNS credentials, and maintenance requirements.
The runbook owns procedures; service and topic guides link those procedures
and describe only their additional behavior.

Before publishing, copy `.publication-denylist.example` to the ignored
`.publication-denylist`, add one exact site-specific value per line, set mode
`0600`, and run:

```bash
./scripts/check-publication.sh
```

The check rejects tracked local/private paths, scans every tracked file for the
ignored exact-value denylist, and checks common secret patterns. Review tracked
Markdown separately for deployment-state prose; a value scan cannot detect a
sanitized diary. Do not embed live identifiers in the repository.

The [Vaultwarden LUKS provider procedure](RUNBOOK.md#vaultwarden-backed-luks-unlock)
documents `scripts/unlock-from-vaultwarden.sh` and its configuration template.
The [HTTP-header provider and cache procedure](RUNBOOK.md#http-credentials-and-scoped-caches)
documents the header helpers, their protected references, rotation, and failure
behavior. Use those canonical procedures instead of maintaining per-service
copies of the credential workflow.

## Security

Do not commit `.env`, API tokens, passwords, Tailscale authentication keys,
application encryption keys, certificates, private keys, database dumps, or
live deployment inventories. A public repository is not a secret store.
