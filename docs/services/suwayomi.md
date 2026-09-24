# Suwayomi deployment guide

Use this guide to build a private Suwayomi VM. Select site values and the
release channel in a local profile, then run the acceptance checks below.

## Decisions and consequences

- Use a dedicated VM so media storage and download activity do not affect
  unrelated services. An optional preview channel can then follow its own
  update and recovery policy.
- Keep the application private behind the same Tailscale, DNS-only Cloudflare,
  and Caddy pattern as other web services.
- Treat large media separately from configuration and database state. Media
  that can be downloaded again may use a different backup policy from the
  metadata needed to reconstruct the service.
- Choose the stable channel by default. Select preview only as an explicit
  profile exception, with health checks and retained previous images because
  preview updates have a higher regression risk.

## Profile characteristics

- Dedicated VM sized for the library and expected download activity.
- Administer the VM with key-only OpenSSH over Tailscale; leave Tailscale SSH
  disabled. When converting an existing VM, verify the approved key and the
  OpenSSH host key through the Proxmox guest agent, then test OpenSSH before
  disabling Tailscale SSH and again afterward.
- Docker Compose application directory standardized as `/opt/suwayomi`.
- Suwayomi and optional request-helper containers.
- A large data disk or documented external mount when the library exceeds the
  practical size of the root disk.
- Bind Suwayomi to loopback.
- Caddy provides private HTTPS through a DNS-only hostname resolving to the
  Tailscale address.

## Update policy

Set the release channel in the local profile. For a preview-channel variant,
select compatible helper channels and schedule an updater at the local
maintenance time. Have the updater perform:

```bash
docker compose pull
docker compose up -d
```

Wrap the updater in an overlap lock, bound its logs, and verify application
health before reporting success. Retain the previous image until the updated
service is healthy.

## Persistent state

Document the database, configuration, downloads, library, and cache locations
separately. Back up irreplaceable configuration and database state. Large media
may use a different retention or replication policy based on whether it can be
downloaded again.

## Acceptance checks

- The web interface loads through private HTTPS.
- Existing library metadata and configuration remain after recreation.
- Download and request-helper integrations work.
- The update job pulls and recreates containers only when needed.
- A VM reboot restores the stack without exposing the application port on an
  unintended interface.
