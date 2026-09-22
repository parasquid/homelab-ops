# n8n service notes

This is a sanitized, canonicalized example. It demonstrates the pattern and is
not a literal export of a live deployment.

## Decisions and consequences

- Use a dedicated VM because n8n has a database, an execution runner, generated
  credentials, and its own update lifecycle. The VM boundary also makes the
  encrypted data disk and recovery procedure independent of other services.
- Use PostgreSQL and the external task runner rather than the smallest possible
  single-container deployment. This matches the intended long-running service
  shape and makes runner behavior an explicit acceptance check.
- Use Caddy with a Cloudflare DNS challenge for private HTTPS. The DNS record is
  DNS-only and resolves to a Tailscale address, so the service remains reachable
  only from the tailnet. This keeps certificate management independent of
  Tailscale Serve and creates no public webhook endpoint.
- Put state and secrets on a separate guest LUKS disk. Debian and Tailscale can
  boot for recovery, while Docker and the application wait for a deliberate
  remote unlock. This protects a copied data disk but leaves the running VM and
  its OS bootstrap within the Proxmox and Tailscale trust boundaries.
- Track the stable application channel with automatic daily updates, while
  keeping PostgreSQL within one selected major version. This reduces routine
  maintenance, but database migrations still require a manual backup or
  snapshot first.
- Keep reusable credentials in the agent-managed Vaultwarden collection after
  bootstrap. Protected local copies remain until the operator explicitly
  approves their removal after the corresponding recovery path has passed.

Private-only access means workflows can call external services, but public
services cannot call n8n webhooks unless a separate, explicitly public ingress
design is added.

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

Use n8n's current `N8N_WEBHOOK_URL` environment variable for the public-facing
webhook base URL. Keep the editor URL and protocol settings aligned with the
same private HTTPS hostname.

## Encryption pattern

For stolen-image protection, attach a separate LUKS data disk and place Docker's
data root, `/opt/n8n`, PostgreSQL data, the n8n encryption key, database
credentials, and the Caddy API-token environment file on it. Keep the unique
automation key outside the repository and VM, with a separate recovery
passphrase and protected LUKS header backup.

After reboot, Debian and Tailscale start from the OS disk. n8n, PostgreSQL, its
task runner, Docker, and Caddy remain stopped until the encrypted disk is
remotely unlocked and mounted.

## Persistent state

Persist both the n8n home directory and PostgreSQL data. The n8n encryption key
and database credentials are required recovery material and must be stored
outside the public repository.

When using the upstream PostgreSQL initialization example, install its shell
script with mode `0755`. Confirm from the first-start logs that the application
role and database were created before n8n starts. If the script was skipped,
fix its permissions; recreate the PostgreSQL volume only while the deployment
is still known to contain no user data.

A database backup without the matching n8n encryption key cannot fully recover
stored credentials. Treat them as one recovery set.

The upstream PostgreSQL initialization script must create the same application
role password that Compose supplies to n8n. If the database initializes but n8n
reports authentication failures, compare the protected inputs through local
container channels without printing them, repair the application role, and
record the mismatch. Do not recreate a database volume that may contain user
data.

## Agent and MCP access

Enable [n8n's instance-level MCP server](https://docs.n8n.io/connect/connect-to-n8n-mcp-server/)
from Compose with
`N8N_MCP_MANAGED_BY_ENV=true` and `N8N_MCP_ACCESS_ENABLED=true`. Environment
management makes the setting reproducible and read-only in the n8n UI, as
described in n8n's [environment-managed settings](https://docs.n8n.io/deploy/host-n8n/configure-n8n/manage-settings-using-environment-variables/#mcp).
Keep automatic workflow exposure disabled; expose only workflows that an MCP
client must operate.

An n8n MCP API key is tied to the n8n user that created it. Store it as a login
item password in the agent-managed Vaultwarden collection. Configure Codex with
the private `/mcp-server/http` URL and the tracked
`scripts/vaultwarden-http-headers.sh` helper, using an ignored mode-`0600`
configuration copied from `vaultwarden-http-headers.conf.example`. The Codex
configuration then contains only the endpoint and helper command; the helper
retrieves the token at connection time using Codex's documented
[`http_headers_helper`](https://learn.chatgpt.com/docs/extend/mcp) support. Set
the MCP client to prompt for tools that can write.

Test the helper by piping its output directly to a structural validator. Never
print the returned JSON, because its `Authorization` value is the live token.
Verify the MCP initialize exchange and tool catalog through private HTTPS, then
confirm at least one deliberately exposed workflow is discoverable. Rotating
the n8n MCP key invalidates the old value and requires updating the vault item.

## Update considerations

Automatic updates may track the chosen stable n8n channel. Pull n8n and its task
runner together so their versions remain compatible. Keep PostgreSQL on its
selected major channel and handle future major migrations separately.

Run the updater at the local 03:00 maintenance time only after confirming that
the encrypted data mount is present. Use a non-overlapping lock, wait for the
Compose health checks and n8n health endpoint, and retain the previous image
until the updated stack is healthy. A locked post-reboot VM therefore leaves
the updater harmlessly stopped until the data disk is unlocked and mounted.

Because n8n updates may run database migrations, take the configured backup or
snapshot before updating and verify login, workflow loading, task-runner health,
and a small test workflow afterward.

Resolve the physical Compose directory before running update commands. Calling
Compose through a compatibility symlink can change the inferred project name,
create a second set of empty named volumes, and break relative secret paths.
Set the project name explicitly and remove an accidental parallel project only
after proving that its containers and volumes contain no service data.

## Acceptance checks

- Owner setup completes through the private HTTPS URL.
- A manual workflow executes successfully.
- A Code-node workflow uses the external task runner successfully.
- A webhook is reachable from another tailnet-connected device.
- The instance-level MCP endpoint authenticates through the Vaultwarden-backed
  header helper, exposes its tool catalog, and limits workflow execution to
  workflows deliberately marked available in MCP.
- The editor and database are unavailable through unintended LAN interfaces.
- After a VM reboot, the stack remains stopped while locked, then returns with
  its saved workflows after remote unlock.
