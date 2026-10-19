# Suwayomi deployment guide

Follow the [shared operating standards](../standards.md) and
[deployment runbook](../../RUNBOOK.md). Select site values and the Suwayomi release
channel in a local profile; this guide adds media and helper-specific choices.

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
- Use the shared [VM access procedure](../../RUNBOOK.md#5-configure-vm-access).
- Docker Compose application directory standardized as `/opt/suwayomi`.
- Suwayomi and optional request-helper containers.
- A large data disk or documented external mount when the library exceeds the
  practical size of the root disk.
- Bind Suwayomi to loopback.
- Caddy provides private HTTPS through a DNS-only hostname resolving to the
  Tailscale address.

## Update policy

Use the [shared guarded updater](../../RUNBOOK.md#8-configure-automatic-application-updates).
Set the Suwayomi channel explicitly and select compatible request-helper
channels. A preview-channel choice needs the profile's corresponding acceptance
and recovery policy.

## Persistent state

Document the database, configuration, downloads, library, and cache locations
separately. Back up irreplaceable configuration and database state. Large media
may use a different retention or replication policy based on whether it can be
downloaded again.

## Acceptance checks

Complete the [shared checks](../../RUNBOOK.md#10-validate-the-deployment), then verify:

- The web interface loads through private HTTPS.
- Existing library metadata and configuration remain after recreation.
- Download and request-helper integrations work.
- The update job pulls and recreates containers only when needed.
- A VM reboot restores the stack without exposing the application port on an
  unintended interface.
