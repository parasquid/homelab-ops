# Example: Vaultwarden

This is a sanitized, canonicalized example. It describes a reusable private
password-manager pattern rather than a live deployment.

## Profile characteristics

- A dedicated Debian VM runs Vaultwarden and Mailpit with Docker Compose.
- Vaultwarden's web service is reachable only through Caddy on the VM's
  Tailscale address. Cloudflare holds a DNS-only record for the private
  hostname; it does not proxy traffic or provide public ingress.
- Mailpit captures SMTP inside the Compose network. Its SMTP port is never
  published to the LAN or tailnet. Its UI is optional and follows the same
  private Caddy path.
- Docker state, application data, Mailpit data, Compose configuration, and
  protected environment files live on a separate guest LUKS data disk.

## Locked boot and recovery

The OS disk boots Debian and Tailscale, but the encrypted mount deliberately
keeps Docker, Caddy, Vaultwarden, and Mailpit stopped. A local helper passes a
per-service key from outside the repository over standard input, opens the
mapper, mounts the data disk, and starts the stack. A separate recovery
passphrase and off-VM LUKS header backup are required recovery material.

## Updates and backups

The selected application channel is updated daily at 03:00 local time after a
mount check and health verification. Keep the previous image until the update
is healthy. Same-disk encrypted rollback snapshots can undo a bad update, but
they are not external disaster recovery; an explicit off-host backup plan is a
separate requirement.

## Owner and credential handoff

The operator creates the owner account through private HTTPS and chooses the
signup policy after bootstrap. Protected local files supply bootstrap
credentials. After owner setup, Vaultwarden is the primary agent-managed
credential store. Its own authoritative LUKS recovery material stays outside
Vaultwarden. Local-file bootstrap is supported now; a gopass adapter is an
optional future integration and is not implemented.
