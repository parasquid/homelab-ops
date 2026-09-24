# n8n deployment guide

Use this guide to build a private n8n VM. Select site values in a local profile
and verify the result with the acceptance checks below.

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
- Use the VM administrator's approved key with OpenSSH over the tailnet for
  maintenance and remote unlock. Keep Tailscale SSH disabled so routine agent
  access does not depend on interactive Tailscale SSH checks.
- Put state and secrets on a separate guest LUKS disk. Debian and Tailscale can
  boot for recovery, while Docker and the application wait for a deliberate
  remote unlock. This protects a copied data disk but leaves the running VM and
  its OS bootstrap within the Proxmox and Tailscale trust boundaries.
- Track the stable application channel with automatic daily updates, while
  keeping PostgreSQL within one selected major version. This reduces routine
  maintenance. Database migrations may run during updates; follow the profile's
  backup policy and record when no rollback point exists.
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

Use n8n's current `N8N_WEBHOOK_URL` environment variable for the HTTPS webhook
base URL presented to tailnet clients. Keep the editor URL and protocol
settings aligned with the same private HTTPS hostname.

### Restricted URL-fetch helper

When a workflow must fetch user-supplied URLs, run the fetcher as a separate
Compose service with no published host port. Attach n8n and the fetcher to a
dedicated `internal: true` bridge; attach only the fetcher to a second bridge
for outbound DNS and HTTPS. Do not attach the fetcher to the application
default network, where it could reach the database or runner. Use a
health-checked, resource-limited Node LTS container with a read-only source
mount and root filesystem, dropped capabilities, no-new-privileges, bounded
logs, and an explicit ephemeral `/tmp`.

Keep the fetcher's requested URL out of n8n Code and generic HTTP Request nodes.
Resolve and validate every DNS answer, pin a public address for the request,
disable automatic redirects and validate each target before requesting it,
enforce a total deadline and response byte cap, strictly decode UTF-8, and
reject control-heavy or known binary payloads even when they claim to be HTML.
Also reject unexpected content types or encodings. A separate fetcher failure
must leave the n8n service healthy; the workflow should return a generic
unavailable result without continuing to storage. Keep the Compose override
beside the base Compose file so the standard update command loads,
health-checks, and restarts the helper with the rest of the project.

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
`scripts/vaultwarden-http-headers-cached.py` helper, using an ignored mode-`0600`
configuration copied from `vaultwarden-http-headers-fast.conf.example`. Fill in
both the exact collection name used by the cache's syncing helper and the exact
collection and item IDs used by the fast fallback. The Codex configuration
then contains only the endpoint and helper command; the helper
retrieves the token at connection time using Codex's documented
[`http_headers_helper`](https://learn.chatgpt.com/docs/extend/mcp) support. Set
the MCP client to prompt for tools that can write.

Codex limits HTTP header helpers to 10 seconds. Use the fast helper with
the protected configuration based on
`vaultwarden-http-headers-fast.conf.example`; pin the exact Vaultwarden
collection and item IDs there. The helper checks the configured server,
account, collection membership, and item name, and reads the local
encrypted CLI vault without a per-call sync. Bootstrap or resync that CLI
vault with the general helper before first use and after key rotation.

For faster connection startup, configure the cached helper to read an in-memory
header from a separate user service over an owner-only Unix socket. Sync and
refresh the exact Vaultwarden item every 15 minutes without writing the header
to disk or exposing a TCP listener. Configure the client to fall back to
`scripts/vaultwarden-http-headers-fast.sh` if the cache is unavailable after
three local cache reads, with two short retries. Set a 100 ms timeout for each
cache read and wait 50 ms and 100 ms between retries before invoking the fast
direct helper. Keep the cache service independent of Codex remote-control
startup, because Vaultwarden
may be locked after reboot. After key rotation, restart the cache service
and reconnect the MCP client to pick up the new header. Scope this cache to
the selected n8n header; use the Vaultwarden service note's scoped-credential
pattern if another agent credential needs a cache.

Test the helper by piping its output directly to a structural validator. Never
print the returned JSON, because its `Authorization` value is the live token.
Verify the MCP initialize exchange and tool catalog through private HTTPS, then
confirm at least one deliberately exposed workflow is discoverable. Rotating
the n8n MCP key invalidates the old value and requires updating the vault item.

### Codex discovery timing and recovery

Codex's optional MCP discovery grace period defaults to 1000 ms. A dynamic
Vaultwarden-backed header helper can exceed that short grace period even when
the n8n endpoint is reachable and authenticated. The symptom is a missing n8n
server or tool catalog in Codex, not necessarily an n8n authentication error.

Set the root-level Codex option before any TOML table and keep n8n's own startup
timeout finite:

```toml
mcp_optional_startup_grace_ms = 0

[mcp_servers.n8n]
startup_timeout_sec = 45
```

The zero global grace makes Codex wait up to the bounded per-server timeout; it
does not disable timeout protection. Keep the MCP client configured to prompt
for write-capable tools. Do not place the global option inside
`[mcp_servers.n8n]`, add a duplicate, or weaken the protected configuration's
`0600` mode.

The setting is read when the Codex remote-control runtime starts. Apply it only
at a safe checkpoint with the actual user-runtime restart. That restart
disconnects the active remote-control task, so checkpoint, reconnect with a new
task after the service is healthy, and then verify that native n8n tools appear.
Do not claim the change is active from a file edit or a unit reload alone.

For verification, let the configured MCP client invoke
`scripts/vaultwarden-http-headers-cached.py` and perform `initialize`, the initialized
notification, and then `tools/list`. Reuse the returned session identifier when
the server supplies one; otherwise follow its stateless HTTP behavior. A helper
result may be piped directly to the client or a structural pass/fail validator,
but must never be printed or saved: the JSON contains the live `Authorization`
value. Record only successful request status and that the catalog is present,
then confirm a write-capable tool still prompts for approval. Do not print
headers, session identifiers, raw JSON-RPC responses, or unredacted client logs.

If discovery still fails, first confirm the single root-level setting and an
actual runtime restart/new task. Next check the protected helper configuration,
credential scope, and endpoint reachability without exposing header output. If
the helper is slow, adjust only the finite per-server timeout approved by the
profile. To roll back, remove the root-level option to restore Codex's 1000 ms
default (or restore its prior approved value), restart the runtime, and
reconnect with a new task.

## Update considerations

Automatic updates may track the chosen stable n8n channel. Pull n8n and its task
runner together so their versions remain compatible. Keep PostgreSQL on its
selected major channel and handle future major migrations separately.

Run the updater at the local 03:00 maintenance time only after confirming that
the encrypted data mount is present. Use a non-overlapping lock, wait for the
Compose health checks and n8n health endpoint, and retain the previous image
until the updated stack is healthy. A locked post-reboot VM therefore leaves
the updater harmlessly stopped until the data disk is unlocked and mounted.

Because n8n updates may run database migrations, follow the profile's backup
choice. Take a backup or snapshot first when one is configured. When backups
are deferred, the automatic update still runs at its configured time without
a database rollback point; a retained container image cannot undo a database
migration. Afterward, verify login, workflow loading, task-runner health, and
a small test workflow.

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
- After the Codex runtime restart and a new task, native n8n MCP tools are
  discoverable, `initialize` and `tools/list` pass through the helper, and
  write-capable tools still require approval without exposing header material.
- The editor and database are unavailable through unintended LAN interfaces.
- After a VM reboot, the stack remains stopped while locked, then returns with
  its saved workflows after remote unlock.
