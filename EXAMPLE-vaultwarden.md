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

## Hostnames and SMTP verification

Use `<component>.<service>.<base-domain>` for auxiliary private endpoints. A
sanitized deployment therefore uses `vaultwarden.example.invalid` for the
service and `mail.vaultwarden.example.invalid` for the Mailpit UI.

Caddy protects the Mailpit web UI with basic auth. Mailpit's SMTP listener is a
Compose-internal service with `smtp_auth: none`; it has no SMTP username or
password. Vaultwarden must omit its SMTP username and password and must never
reuse the UI credential. The recognizable failure for an incorrect auth setup
is `No compatible authentication mechanism was found`.

After the owner setup, send and accept a real Vaultwarden verification email
through the private site. A message visible in Mailpit proves capture only; it
does not exercise Vaultwarden's SMTP configuration or acceptance flow.

## Registration lifecycle

Bootstrap with `SIGNUPS_ALLOWED=true`, `SIGNUPS_VERIFY=true`, and an empty
`SIGNUPS_DOMAINS_WHITELIST=` while keeping `INVITATIONS_ALLOWED=true`. Recreate
only Vaultwarden, create the first owner through private HTTPS, accept the
real verification email, and confirm that owner can log in.

Then set `SIGNUPS_ALLOWED=false` with verification still enabled and the
whitelist still empty. Recreate only Vaultwarden, confirm the running flag is
false, verify that the backend rejects a new registration, and confirm the
existing owner login. The registration form may remain visible while the
backend rejects submissions.

Prefer invitations while general signups are closed. A temporary reopening is
`true -> recreate -> onboard -> false -> recreate`. A nonempty
`SIGNUPS_DOMAINS_WHITELIST` overrides the false signup flag for matching
domains. Admin UI values in `data/config.json` can override environment values,
so keep the protected environment authoritative unless deliberately changing
that source. See the upstream [environment template](https://github.com/dani-garcia/vaultwarden/blob/main/.env.template)
and [configuration implementation](https://github.com/dani-garcia/vaultwarden/blob/main/src/config.rs).

If an organization invitation targets a nonexistent new account while
`INVITATIONS_ALLOWED=false`, the backend can return `User does not exist`.
Check the running container policy rather than only the source environment.
Keep `SIGNUPS_ALLOWED=false`, set `INVITATIONS_ALLOWED=true`, recreate only
Vaultwarden, verify the running policy is `false:true` and health is good, then
retry the owner invitation. The normal organization flow requires no Admin UI
invite and no direct database write.

## Agent-scoped access

Use a separate account for each agent host. Invite it as an organization User
with organization-wide access disabled and assign only the agent-managed
collection with read/write access and no management permission. Keep personal
vault data and operator-only collections outside this account's scope.

The invited account completes signup through the invitation link first. The
organization owner then confirms the accepted member and checks its collection
assignment. Until that owner confirmation, the account can authenticate while
the CLI still reports no organizations or collections.

Keep the account bootstrap credential in a protected file outside the
repository. Use a supported web client to establish the account, then configure
the Bitwarden CLI with the private Vaultwarden URL. Pass the master password by
protected file or another non-command-line mechanism. After syncing, test that
the account can read and write a disposable item only in the intended
collection and cannot manage collections or see personal-vault items. Preserve
the bootstrap credential and all existing LUKS keys until another tested
recovery path exists and the operator explicitly approves removal.

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
