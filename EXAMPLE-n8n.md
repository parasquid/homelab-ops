# Example: n8n

This is a sanitized, canonicalized example. It demonstrates the pattern and is
not a literal export of a live deployment.

## Profile characteristics

- Dedicated Debian VM with modest CPU, memory, and root disk allocations.
- Docker Compose application directory at `/opt/n8n`.
- n8n, an external n8n task runner, and PostgreSQL.
- n8n and its task runner use the same version or release channel.
- PostgreSQL stays within a selected major version.
- n8n binds to loopback; PostgreSQL and the runner broker remain internal to
  Compose.
- Caddy terminates private HTTPS on the VM's Tailscale address.
- A DNS-only hostname resolves to that Tailscale address.
- The editor and webhook base URLs use the external HTTPS hostname.
- Execution history is pruned according to the service profile.

## Persistent state

Persist both the n8n home directory and PostgreSQL data. The n8n encryption key
and database credentials are required recovery material and must be stored
outside the public repository.

A database backup without the matching n8n encryption key cannot fully recover
stored credentials. Treat them as one recovery set.

## Update considerations

Automatic updates may track the chosen stable n8n channel. Pull n8n and its task
runner together so their versions remain compatible. Keep PostgreSQL on its
selected major channel and handle future major migrations separately.

Because n8n updates may run database migrations, take the configured backup or
snapshot before updating and verify login, workflow loading, task-runner health,
and a small test workflow afterward.

## Acceptance checks

- Owner setup completes through the private HTTPS URL.
- A manual workflow executes successfully.
- A Code-node workflow uses the external task runner successfully.
- A webhook is reachable from another tailnet-connected device.
- The editor and database are unavailable through unintended LAN interfaces.
- The stack and saved workflows survive a VM reboot.
