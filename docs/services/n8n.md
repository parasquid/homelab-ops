# n8n deployment guide

Follow the [shared operating standards](../standards.md) and
[deployment runbook](../../RUNBOOK.md). This guide adds n8n-specific component,
workflow, integration, and acceptance requirements. Select site values in a local
profile; this reference selects the shared guest-LUKS data pattern.

## Decisions and consequences

- Use a dedicated VM because n8n has a database, an execution runner, generated
  credentials, and its own update lifecycle. The VM boundary also makes the
  encrypted data disk and recovery procedure independent of other services.
- Use PostgreSQL and the external task runner rather than the smallest possible
  single-container deployment. This matches the intended long-running service
  shape and makes runner behavior an explicit acceptance check.
- Keep n8n's encryption key with its database recovery set. Use the shared
  [credential provider](../../RUNBOOK.md#retrieve-a-service-credential) for
  agent-managed secrets after bootstrap.

Use the [shared access and key-recovery procedure](../../RUNBOOK.md#recover-a-vms-approved-openssh-key-through-proxmox)
when the guest rejects the approved workstation key.

Private-only access means workflows can call external services, but public
services cannot call n8n webhooks unless a separate, explicitly public ingress
design is added.

## Profile characteristics

- Docker Compose application directory at `/opt/n8n`.
- n8n, an external n8n task runner, and PostgreSQL.
- n8n and its task runner use the same version or release channel.
- PostgreSQL stays within a selected major version.
- n8n binds to loopback; PostgreSQL and the runner broker remain internal to
  Compose.
- The editor and webhook base URLs use the external HTTPS hostname.
- Execution history is pruned according to the service profile.

Use n8n's current `N8N_WEBHOOK_URL` environment variable for the HTTPS webhook
base URL presented to tailnet clients. Keep the editor URL and protocol
settings aligned with the same private HTTPS hostname.

## Private static operator portal

Serve private static pages from the existing Caddy instance on an auxiliary
hostname such as `pages.<service>.<base-domain>`. Mount each product at its own
path prefix, such as `/<application>/`, and keep the host root generic so
future pages can coexist. This needs no additional application process
unless a concrete server-side requirement cannot be handled by static assets
and n8n workflows. Check the exact hostname for existing A, AAAA, and CNAME
records before creating a DNS-only A record to the VM's Tailscale IPv4 address.
Use the existing private DNS-01 certificate path, bind the site to the Tailscale
address, and use tailnet ACLs to limit HTTPS access to intended operators. Do
not add public ingress or portal Basic Auth; the tailnet ACL is the access
boundary.

Keep the built assets under the encrypted application-data mount and bind them
into Caddy read-only. Point `root` and `file_server` only at the intended
static asset directory for each path prefix. Keep Compose files, secrets,
Caddy state, and other service data out
of the web root. Render event-supplied text through text nodes or escaped HTML.
If source formatting is needed, convert it to a bounded subset and render only
explicitly allowed elements and safe URLs. Check repeated conversion and literal
punctuation as well as hostile tags and links. Do not inject raw source HTML.

The browser should call same-origin `/<application>/api/...` routes. Configure one
explicit Caddy method-and-path route for each implemented portal operation,
rewriting it to that operation's named production n8n webhook. Proxy only to
n8n's loopback listener through host networking or another verified narrow
path. Return 404 for unmatched `/api/*` paths; do not use a catch-all API proxy,
expose the editor/API through the portal hostname, or place n8n API credentials
or webhook secrets in browser code.

For each portal proxy route, remove any incoming `X-Portal-Route` value and set
a fixed proxy-owned marker. Remove `Authorization` from the portal request
before proxying; the browser must not send backend credentials. Remove
caller-supplied `X-Portal-Route` on the n8n editor hostname before proxying as
well, so direct webhook requests cannot forge the portal route. The marker
distinguishes the configured Caddy route; it is not an operator identity or a
secret. Keep the n8n port loopback-only and have each portal workflow require
the marker before processing a request.

Keep reads on GET and mutations on POST. For every mutation, require the exact
portal `Origin`, `application/json`, and a custom request header; reject absent
or foreign origins, form-encoded writes, and other methods. Do not enable CORS
for portal routes. These checks protect the write endpoints from cross-site
requests; workflows must also validate portal-route provenance, allowed transitions,
edition and candidate identity, draft revision, and submitted values. Preserve
Gate 1 selection and Gate 2 final approval before publication.

Before activating the auxiliary hostname, validate the Compose and Caddy
configuration through the normal service entrypoint when it loads DNS
credentials from a file. Running `caddy validate` directly without that
entrypoint can report a missing token even when the service has it. Keep the
validation container isolated from external traffic until the candidate
configuration passes, then test from an allowed tailnet client. Verify the portal loads,
only its explicit API routes reach their matching workflows, rejected requests
cannot change state, and direct webhook calls through the editor hostname fail
even when the caller supplies the marker. Check the certificate,
Tailscale-only listener, tailnet ACL, and absence of public or unintended LAN
access. Save the previous Caddyfile and Compose files on the encrypted mount for
rollback. If a change fails, restore those files and reload or recreate only
Caddy; preserve n8n and its data. Remove a newly created DNS record only when
explicitly authorized, and never overwrite or remove a pre-existing record.

## Private test inbox for workflow email

For email workflow testing, use a dedicated SMTP capture service such as
[Mailpit](https://mailpit.axllent.org/docs/install/docker/) in the n8n Compose
project. Keep it separate from an account service's inbox so test drafts cannot
mix with verification or recovery mail. Capture mail only; leave SMTP relay and
forwarding unset. This gives workflows an end-to-end SMTP target without sending
to external recipients.

Put Mailpit's database in a persistent volume under the encrypted Docker data
root. Set `MP_DATABASE` to the mounted database path and bound message-size and
retention limits. Publish only the web UI to the VM's loopback address; do not
publish SMTP port 1025. n8n reaches SMTP by the Compose service name on the
internal project network. Create an n8n SMTP credential for the Compose hostname and port
1025 with SSL/TLS and STARTTLS disabled and no username or password; reference
its credential ID in the email workflow, not connection settings embedded in
workflow exports. Add a `/readyz` health check and bounded container logs.
When the UI has no separate login, set `MP_ALLOWED_HOSTS` to its intended
hostname and keep the service reachable only through the tailnet-bound HTTPS
proxy. Do not enable Mailpit's internal HTTP request option for email preview
checks.

Check the proposed hostname for A, AAAA, and CNAME conflicts before creating
a DNS-only A record to the VM's Tailscale address. Bind the Caddy site to that
address and use the existing DNS-01 secret; proxy to the loopback UI port.
Validate Compose and the Caddy candidate through the secret-loading entrypoint
before cutover. Preserve rollback copies on the encrypted mount, then recreate
only the new service and Caddy. Avoid restarting n8n and PostgreSQL for an inbox
addition.

Verify a trusted certificate, UI response without Basic Auth, and a captured
message sent from the n8n Compose network to a reserved test address. Confirm
that SMTP has no published host port, the UI has no LAN or public listener, the
Mailpit database is on the encrypted mount, and the existing n8n stack remains
healthy. Test the Host allowlist against an unlisted hostname. Record the actual
hostname, image version, storage volume, rollback paths, and check results in
the ignored local inventory and service handoff.

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

Enable n8n's SSRF protection when workflow nodes can make requests to
user-controlled destinations:

```text
N8N_SSRF_PROTECTION_ENABLED=true
```

If an active workflow must call the internal helper, allow only its exact
operator-controlled Compose hostname with `N8N_SSRF_ALLOWED_HOSTNAMES`. Avoid
allowing an entire private IP range. n8n checks hostname allowlists before its
blocked IP ranges, so an allowed hostname bypasses those IP blocks. Keep the
exception only while a verified workflow needs it; remove it after all callers
have migrated and keep SSRF protection enabled. Before retiring the helper,
verify that no active workflow still references it, remove the exact hostname
exception and helper service/network in the same planned Compose change, and
use the service checkpoint/restart and health checks. Retain the rollback
configuration until n8n is healthy and the removed helper is absent. See n8n's
[SSRF protection guide](https://docs.n8n.io/deploy/host-n8n/configure-n8n/security/enable-ssrf-protection/)
and [environment variable reference](https://docs.n8n.io/deploy/host-n8n/configure-n8n/basic-configuration/use-environment-variables/ssrf-protection/).

## Encryption pattern

Use the [shared LUKS procedure](../../RUNBOOK.md#6-configure-optional-guest-luks-encryption).
Include the n8n home directory, PostgreSQL state, n8n encryption key, and
integration credentials in the encrypted application state.

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

An n8n MCP API key is tied to the user that created it. Store it in the scoped
agent-managed collection and configure the private `/mcp-server/http` endpoint
with the [shared Vaultwarden HTTP-header helper procedure](../../RUNBOOK.md#http-credentials-and-scoped-caches).
That procedure owns protected references, CLI sync, fast/cached helpers,
rotation, and secret-safe verification. Keep write-capable tools behind the
client's approval prompt. Verify authentication and discovery of at least one
workflow deliberately exposed through MCP.

### Codex discovery timing and recovery

Follow the [shared MCP discovery and runtime-restart procedure](../../RUNBOOK.md#12-configure-optional-mcp-discovery-for-agent-clients).
Use a finite 45-second n8n startup timeout. After the required runtime restart
and a new task, verify that native n8n tools and the intended workflow catalog
are available and write-capable tools still require approval.

## Update considerations

Use the [shared guarded updater](../../RUNBOOK.md#8-configure-automatic-application-updates).
Pull n8n and its external task runner together so they remain compatible; keep
PostgreSQL on its selected major. After an update, verify login, saved workflows,
runner health, and a small test workflow. Preserve the matching n8n encryption
key through any database recovery or migration.

## Acceptance checks

Complete the [shared checks](../../RUNBOOK.md#10-validate-the-deployment), then verify:

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
