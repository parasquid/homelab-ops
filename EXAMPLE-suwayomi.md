# Example: Suwayomi

This is a sanitized, canonicalized example. It captures useful behavior from an
existing deployment while applying the runbook's current security defaults.

## Profile characteristics

- Dedicated VM sized for the library and expected download activity.
- Docker Compose application directory standardized as `/opt/suwayomi`.
- Suwayomi and optional request-helper containers.
- A large data disk or documented external mount when the library exceeds the
  practical size of the root disk.
- Suwayomi binds to loopback under the current standard.
- Caddy provides private HTTPS through a DNS-only hostname resolving to the
  Tailscale address.

## Update policy

This service intentionally follows Suwayomi's preview channel. Its helper
containers follow their selected rolling channels. A daily update job performs:

```bash
docker compose pull
docker compose up -d
```

The canonical implementation should add an overlap lock, bounded logging, and a
post-update health check. Preview is an explicit exception; other applications
default to their stable channel.

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
