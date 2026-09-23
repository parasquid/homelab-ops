# Proxmox service deployment runbook

This runbook describes the default path for deploying one private service in a
dedicated Proxmox VM. The service profile is authoritative for sizing and
exceptions. Values from the local `.env` supply site-specific configuration.
The matching page under `docs/services/` records why the service uses its
particular shape and the consequences and gotchas that future operators need.

## 1. Establish the desired state

Create a local service profile from `SERVICE-PROFILE.example.yaml`. Resolve
these decisions before provisioning:

- Service name, purpose, image, and release channel.
- CPU, memory, root disk, application-data requirements, and hardware access.
- Persistent application state, database state, and backup requirements.
- Tailscale-only, LAN, or explicitly public exposure.
- Required ports, discovery protocols, webhooks, and reverse-proxy behavior.
- Stable, rolling, or preview application updates.

Do not infer public exposure from the application category. Private access is
the default.

## 2. Preflight the Proxmox node

Connect to the Proxmox node using the administrator defined in `.env`. Inspect:

```bash
pveversion
free -h
pvesm status
qm list
pvesh get /cluster/nextid
cat /etc/network/interfaces
```

Confirm that the selected storage supports VM images and has enough headroom.
Check the candidate VM ID, hostname, MAC address allocation, DNS record, and any
host mount before changing state. Existing resources win; choose a new value or
ask for direction rather than overwriting them.

For media or file services, separate the small operating-system disk from large
or independently managed application data when doing so improves backup,
expansion, or recovery.

## 3. Prepare and verify the operating-system image

Use an official Debian generic cloud image. Download the image and checksum
manifest from the same official release location and verify the image before
importing it. Record the source URL, release, filename, checksum algorithm, and
verification result in the deployment record.

Never proceed with a missing or failed checksum.

## 4. Create the VM

Create a QEMU/KVM VM using the profile values. The baseline includes:

- VirtIO networking on the configured bridge.
- VirtIO SCSI storage with discard enabled where supported.
- DHCP unless the site profile requires a reserved or static address.
- VM autostart.
- QEMU Guest Agent enabled in Proxmox and installed in the VM.
- A cloud-init drive.

Cloud-init creates the administrator from `VM_ADMIN_USER`, locks its password,
adds it to the sudo group, and grants passwordless sudo:

```yaml
users:
  - name: ${VM_ADMIN_USER}
    groups: [sudo]
    shell: /bin/bash
    lock_passwd: true
    sudo: "ALL=(ALL:ALL) NOPASSWD: ALL"
```

Provide an approved SSH public key for the VM administrator. Do not put a
private key or reusable Tailscale credential in committed cloud-init data.

Boot the VM and wait for cloud-init and the guest agent to finish before
installing the application. Expand the root filesystem to the provisioned disk
size and verify time synchronization and timezone.

## 5. Configure VM access

Install Tailscale from its official repository and enroll the VM. Keep Tailscale
SSH disabled; use Tailscale as the private network path to the VM's OpenSSH
server. Interactive enrollment is acceptable; surface the authorization URL to
the operator. An automated authentication key must be supplied through a
protected local mechanism and must not appear in output.

Before changing SSH access on an existing VM, verify that OpenSSH is running,
the intended administrator's approved public key is in `authorized_keys`, and
the OpenSSH host key is known through a trusted path such as the guest agent.
Disable Tailscale SSH on the VM with `tailscale set --ssh=false`, then verify a
key-only OpenSSH login through its tailnet hostname. Refresh the client's
`known_hosts` entry only after matching the observed host key to the trusted
key. If disabling Tailscale SSH from a Tailscale SSH session, its CLI may require
`--accept-risk=lose-ssh` and will disconnect that session.

Verify login as `VM_ADMIN_USER` and verify passwordless sudo. Direct root login
inside the VM is a recovery path rather than the standard administration path.
The Proxmox node continues to use its own administrator from `.env`.

## 6. Configure optional guest LUKS encryption

Use `guest-luks-data` when the service profile must protect application state
from someone obtaining a copy of its VM disks. This protects data at rest; it
does not protect an unlocked running VM from the Proxmox administrator or a
compromised hypervisor.

The version 1 pattern uses two virtual disks:

```text
OS disk          Replaceable Debian installation and Tailscale bootstrap
LUKS data disk   Docker state, Compose configuration, secrets, and service data
```

The OS disk remains bootable so the VM can join Tailscale for remote unlock.
This means its Tailscale node state and SSH host keys are not protected by the
data disk. Revoke the Tailscale device immediately if an OS image is suspected
to have been copied.

Keep the per-service automation key outside the repository and outside the VM.
The local `.env` contains only `LUKS_KEY_DIRECTORY`. Generate a unique,
high-entropy key file for each service, protect it with mode `0600`, and keep a
separate recovery copy.

Before formatting, resolve the added disk through a stable `/dev/disk/by-id`
path and verify its serial, capacity, VM attachment, and lack of existing
signatures. Never rely on a transient name such as `/dev/sdb` without those
checks.

Pass the key through standard input for both format and unlock operations. A
remote unlock follows this pattern:

```bash
ssh "${VM_ADMIN_USER}@${VM_HOST}" \
  'sudo cryptsetup open /dev/disk/by-id/<verified-disk> service-data --key-file=-' \
  < "${LUKS_KEY_FILE}"
```

Create a filesystem and mount the mapper at the profile's mount point. Place
Docker's data root, `/opt/<service>`, application secrets, and all persistent
bind mounts on this filesystem. Configure Docker, Caddy, and the application so
they cannot start before the encrypted filesystem is mounted. Caddy's API token
belongs in a protected environment file on the encrypted disk, while the
Caddyfile itself contains only an environment reference.

Add a separate human recovery passphrase in another LUKS keyslot and store it
in a password manager. Create a LUKS header backup after configuring the
keyslots, store it outside the VM and its Proxmox storage, and protect it as
sensitive recovery material. Refresh the header backup whenever keyslots
change.

With remote-script unlock, unattended application recovery after a VM reboot is
deliberately disabled. The VM and Tailscale start, but Docker, Caddy, and the
application remain stopped until the data disk is unlocked, mounted, and the
services are started. Test both the locked and unlocked boot states.

## 7. Install Docker and lay out the application

Install Docker Engine and the Compose plugin from Docker's official repository.
Create `/opt/<service>` and give the VM administrator appropriate ownership.

The Compose deployment should:

- Use an upstream-supported release channel.
- Bind a private web application to `127.0.0.1:<port>`.
- Leave databases, queues, and brokers accessible only on Compose networks.
- Persist every stateful path in a named volume or documented bind mount.
- Add meaningful health checks.
- Use `restart: unless-stopped` or a documented alternative.
- Bound `json-file` logs, for example with `max-size` and `max-file`.
- Keep version-coupled images on the same channel or exact version.
- Pin a database to its selected major version and plan major upgrades manually.

Store application and database secrets in a protected environment file outside
Git. Generate independent, random values for application encryption keys and
database credentials.

Any database initialization scripts mounted into an official container image
must be readable and executable by the container's initialization process. Use
mode `0755` for shell entrypoint scripts unless the image documents another
requirement. A script that the host administrator can read may still fail
inside the container because the entrypoint runs under a different UID. Check
the database's first-start logs and verify that the expected application role
and database exist before starting the application. If initialization fails,
only recreate the database volume after proving that it contains no data that
must be retained.

Start the stack, wait for health checks, and test its loopback endpoint before
adding DNS or Caddy.

## 8. Configure automatic application updates

The default policy tracks the application's stable release channel and updates
daily at 03:00 local time. A preview channel must be named explicitly in the
service profile.

The updater should run from the application directory and perform the equivalent
of:

```bash
docker compose pull
docker compose up -d --remove-orphans
```

Wrap this in a non-overlapping cron job or systemd timer. Retain bounded logs,
first verify that any encrypted data mount is present, wait for the defined
health check, and report failures. Do not prune the previous images until the
new deployment is healthy. When a deployment has no backup, record that risk
explicitly before enabling automatic updates.

If the application directory is a symlink into the encrypted mount, run the
updater from its resolved physical directory or pass an explicit Compose
project directory. Compose resolves relative secret files, project names, and
named volumes from that directory; invoking it through the symlink can create
a parallel project with empty volumes or fail to find the secret file.

Operating-system security updates are independent of container updates. Enable
the distribution's unattended security updates; handle distribution releases
and database-major upgrades manually.

## 9. Configure private DNS and HTTPS

Create a DNS-only Cloudflare `A` record for the service hostname pointing to the
VM's Tailscale IPv4 address. Check for an existing record first. Do not overwrite
or repurpose an unrelated hostname.

Install Caddy with the Cloudflare DNS provider. Store its zone-scoped API token
in a root-readable environment file and reference it from the Caddy service.
Never place the token directly in the Caddyfile.

The private-site pattern is:

```caddyfile
{
	auto_https disable_redirects
	email {$CADDY_ACME_EMAIL}
	acme_ca {$CADDY_ACME_CA}
}

{$SERVICE_DOMAIN} {
	bind {$TAILSCALE_IPV4}
	tls {
		dns cloudflare {env.CLOUDFLARE_API_TOKEN}
	}
	reverse_proxy 127.0.0.1:{$APPLICATION_PORT}
}
```

Validate the Caddy configuration before reloading it. Confirm that Caddy listens
on the Tailscale address only, that port 80 is not opened by an automatic redirect,
and that the certificate validates from a tailnet-connected device.

Configure the application with its external HTTPS URL and trusted-proxy setting
when required. Do not assume every application interprets forwarded headers the
same way; verify against its current upstream documentation.

## 10. Validate the deployment

Run and record these acceptance checks:

1. VM resources, disk size, network, autostart, and guest-agent status match the
   profile.
2. Tailscale is healthy and `VM_ADMIN_USER` can log in and use sudo.
3. Containers are running and all defined health checks pass.
4. Persistent data exists in the documented locations.
5. The hostname resolves to the intended Tailscale address.
6. HTTPS returns the expected application response with a valid certificate.
7. Application and database ports are not reachable through unintended LAN or
   public addresses.
8. Listener inspection matches the exposure profile.
9. A controlled VM reboot restores Tailscale, Docker, Caddy, and the application.
10. The automatic update path runs without exposing secrets and leaves the
    application healthy.
11. Backup status and restore instructions are documented, including when
    backup work is deliberately deferred.

For `guest-luks-data`, replace check 9 with the expected encrypted sequence:
Tailscale recovers while the application remains stopped, remote unlock mounts
the data disk, and Docker, Caddy, and the application then return healthy.

## 11. Vaultwarden reference pattern

Vaultwarden follows the private VM pattern with one additional internal service:

- Run Vaultwarden and Mailpit in Docker Compose on the encrypted data mount.
  Use the hostname convention `<component>.<service>.<base-domain>`: the
  Vaultwarden site is `vaultwarden.example.invalid` and the auxiliary Mailpit
  UI is `mail.vaultwarden.example.invalid`. Mailpit captures Vaultwarden's
  SMTP during bootstrap and routine testing.
- The Mailpit web UI is protected by Caddy basic auth. Its SMTP listener is a
  Compose-internal service with no SMTP authentication. Vaultwarden must omit
  its SMTP username and password rather than reuse the Mailpit UI credential;
  a mismatch can produce `No compatible authentication mechanism was found`.
  The SMTP listener stays on the Compose network and is never published.
- Keep the application and Mailpit off LAN and public interfaces. Caddy binds
  to the VM's Tailscale address. Cloudflare records for the application and
  auxiliary UI are DNS-only and resolve to that Tailscale address;
  Cloudflare proxying, Funnel, router forwarding, and public ingress remain
  disabled.
- Put Docker state, Compose files, Vaultwarden data, Mailpit data, and
  protected environment files on the guest LUKS data disk. The OS disk holds
  only the bootstrap needed to bring up Debian and Tailscale.
- Treat boot as locked by default. Debian and Tailscale start, while Docker,
  Caddy, Vaultwarden, and Mailpit wait for the encrypted mount. Use the local
  unlock helper to pass the external automation key over standard input, open
  the mapper, mount the filesystem, and start the stack. Verify the locked and
  unlocked states after changes.
- Run the application update job daily at 03:00 local time. It must verify the
  encrypted mount, pull the selected channel, wait for health checks, retain
  the previous image until the new stack is healthy, and report failures.
- Same-disk encrypted rollback snapshots are useful for a bad update but are
  not disaster recovery. Record their retention and the absence of an
  external backup until a separate off-host backup has been tested.

### Registration lifecycle

Use this one-time bootstrap sequence with the protected environment as the
authoritative source. It follows the upstream [`SIGNUPS_*` and
`INVITATIONS_ALLOWED` settings](https://github.com/dani-garcia/vaultwarden/blob/main/.env.template):

1. Set `SIGNUPS_ALLOWED=true`, `SIGNUPS_VERIFY=true`, and an empty
   `SIGNUPS_DOMAINS_WHITELIST=`. Keep `INVITATIONS_ALLOWED=true`.
2. Recreate only Vaultwarden to apply the environment. Create the first owner
   through the private URL, accept the real verification email, and confirm
   the existing owner can log in. Raw Mailpit capture alone is insufficient.
3. Set `SIGNUPS_ALLOWED=false` while keeping `SIGNUPS_VERIFY=true` and the
   whitelist empty. Recreate only Vaultwarden again.
4. Confirm the running configuration flag is false, a new registration is
   rejected by the backend, and the existing owner can still log in. The
   registration form may remain visible even when the backend blocks it.

For routine onboarding, prefer invitations with `INVITATIONS_ALLOWED=true`:
invited users remain possible while general signups are closed. A temporary
reopening is exactly `true -> recreate -> onboard -> false -> recreate`.
A nonempty `SIGNUPS_DOMAINS_WHITELIST` overrides `SIGNUPS_ALLOWED=false` for
matching domains. Values saved by the Admin UI in `data/config.json` can also
override environment values; keep the protected environment authoritative
unless deliberately changing that source. The upstream implementation is in
[`src/config.rs`](https://github.com/dani-garcia/vaultwarden/blob/main/src/config.rs).

If an organization invitation targets a nonexistent new account while
`INVITATIONS_ALLOWED=false`, Vaultwarden can return the exact error `User does
not exist`. Diagnose this from the running container configuration, not only
from the source environment file. Keep `SIGNUPS_ALLOWED=false`, set
`INVITATIONS_ALLOWED=true`, recreate only Vaultwarden, verify the running
policy is `false:true` and the container is healthy, then retry the owner
invitation. The normal organization flow needs no Admin UI invite and no
direct database write.

### Agent-scoped organization accounts

Give each agent host its own Vaultwarden account so one host can be revoked
without rotating every agent credential. Invite the account as an organization
User, leave organization-wide access disabled, and assign only the
agent-managed collection. In the collection access dialog, enable `Edit items`
and leave `Hide passwords` and `Manage` disabled. This gives the agent
read/write access with visible passwords while preventing collection
management. Do not grant Owner, Admin, or personal-vault access.

Create the agent account through Vaultwarden's invitation link using a
supported web client. A protected bootstrap file outside the repository may
hold the account email and master password while the client establishes the
account's encryption keys. Never log the invitation URL or place the master
password in a command argument. Keep this bootstrap material until another
tested unlock and recovery mechanism exists.

The invitation has two distinct operator steps. The invited account first
finishes signup and accepts the invitation. The organization owner must then
confirm the accepted member and verify its collection assignment. Before that
confirmation, a successful CLI login can still show zero organizations and
zero collections; this is expected and is not evidence of a bad password.

After owner confirmation, configure the Bitwarden CLI with the private
Vaultwarden URL, log in using a protected password file or API-key flow, unlock
without placing the master password on the command line, and sync. Verify that
the account sees exactly the intended organization and collection, can create
and read a disposable test item there, cannot manage the collection, and
cannot see operator personal-vault items. Remove the test item after the check.
Store infrastructure secrets only after this scope test passes. Existing LUKS
keys and bootstrap credentials remain in their protected external locations
until the operator explicitly approves their removal.

For an eligible service data disk, store the automation key as a login-item
password in the agent-managed collection. Binary key files must be encoded,
for example with base64, and the item must record the encoding and expected
decoded byte length. The unlock helper must select one exact item from one
exact collection, decode it only in memory, and pass the bytes to `cryptsetup`
over standard input. It must never write the retrieved key to disk or include
it in a command argument. Before relying on the item, compare a retrieval with
the source key in memory and run `cryptsetup open --test-passphrase` against
the intended LUKS header. Keep the protected local key until the operator
explicitly approves its removal after a real locked-boot recovery test.

Use the tracked `scripts/unlock-from-vaultwarden.sh` implementation with a
local copy of `unlock-from-vaultwarden.conf.example`. Keep that populated file
ignored and mode `0600`. The script sources it as trusted Bash, so only the
operator may own or modify it. Put deployment identifiers, item references,
the credential-file path, and the optional remote post-unlock command in that
file. Keep the master password, vault session, API tokens, and LUKS bytes out
of it. Test the configured path with:

```bash
./scripts/unlock-from-vaultwarden.sh \
  --config private/example-service-vaultwarden-unlock.conf \
  --test
```

For an HTTP client that supports a dynamic header command, store its bearer
token as the password of one exact login item in the agent-managed collection.
Use `scripts/vaultwarden-http-headers.sh` with an ignored mode-`0600` copy of
`vaultwarden-http-headers.conf.example`. The client configuration contains the
private endpoint and helper command, while the helper unlocks the scoped CLI
account, retrieves the exact item, and emits the required header JSON at
connection time. That JSON contains the live token: pipe it directly to the
client or a structural validator and never print or log it. Prefer a token tied
to the least-privileged application user that can do the required work, and
configure the client to prompt for write-capable tools.

For Codex connections using the Vaultwarden CLI, the HTTP header helper
must finish within Codex's 10-second limit. The optional
`scripts/vaultwarden-http-headers-fast.sh` uses exact collection and item
IDs from a protected configuration based on
`vaultwarden-http-headers-fast.conf.example`. It validates the server,
account, item name, and collection membership. It reads the local encrypted
CLI vault without a per-call sync; bootstrap or sync that vault before
first use and after token rotation. The config must contain both the exact
collection name for the syncing helper and the exact collection and item IDs
for the fast helper. Do not put the token in the config.

When repeated MCP connection startup latency matters, an optional
owner-only user service can retain only the scoped header in memory and
serve it over a mode-`0600` Unix socket. Use
`scripts/vaultwarden-http-header-cache.py` with a protected helper config
and `scripts/vaultwarden-http-headers-cached.py` as the client command.
The cache refreshes through the syncing Vaultwarden helper and never
opens a TCP listener or writes the token to disk. The client falls back
to the fast direct helper after three unsuccessful local cache reads.
Each read is limited to 100 ms, with 50 ms and 100 ms between retries;
the bounded retry window leaves time for Codex’s 10-second helper limit.
Do not make Codex remote-control startup depend on the cache: an encrypted
Vaultwarden VM may remain locked after reboot.

For additional agent credentials, a scoped local cache is a future pattern,
not a deployed general Vaultwarden API. Reuse the cache implementation only
with a protected allowlist that maps service aliases to exact collection and
item IDs, expected item names, response formats, and intended destinations.
Validate the Vaultwarden server, agent account, item identity, and collection
membership on every refresh. Reject arbitrary item IDs, searches, and CLI
commands from clients. Keep only the selected values in process memory; never
write decrypted values or session keys to disk, arguments, or logs.

Serve each trust scope through its own owner-only Unix socket in a mode-`0700`
directory, with a mode-`0600` socket and peer-UID checks. A UID check cannot
distinguish processes running as the same user, so use separate OS users or
service instances when clients need different credential access. Do not open
a TCP listener or expose the unrestricted Bitwarden CLI `serve` API. Refresh
in the background, invalidate values on rotation or failed identity checks,
and keep startup and fallback bounded so a locked vault cannot stall the
agent runtime. Document the exact allowlist, refresh and rotation procedure,
failure behavior, and test results in the private inventory and handoff
before enabling any additional credential.

Do not make Vaultwarden dependent on a key held only inside itself. Its own
automation key, recovery passphrase, and header backup require an external
bootstrap and recovery location even when a convenience copy exists in the
vault. Keep human recovery material and agent automation material separate.

Owner creation and the signup policy are an operator handoff after the stack is
reachable over private HTTPS. The agent may verify the setup path and Mailpit
capture, but must not invent owner credentials or silently choose an account
policy. During bootstrap, protected local files are the credential source. Once
the owner completes setup, Vaultwarden is the primary agent-managed credential
store. Its authoritative LUKS recovery material must remain outside Vaultwarden
because it is required before Vaultwarden is available. A local-file bootstrap
is the supported path; a gopass adapter is an optional future integration and
is not implemented. A raw Mailpit capture alone does not exercise Vaultwarden's
SMTP configuration; perform a real Vaultwarden verification-email acceptance
test after owner setup and record its result in the private handoff.

## 12. Configure optional MCP discovery for agent clients

An MCP server that obtains an authorization header through a dynamic helper can
be healthy while its client still reports the server or its tools as missing.
Codex gives each optional MCP server a default 1000 ms discovery grace period;
the helper may need longer than that even when authenticated `initialize` and
`tools/list` requests succeed.

Set the global grace period to zero at the root of the Codex TOML file, before
the first table. Zero means that Codex waits up to each server's own bounded
startup timeout; it does not make startup unbounded:

```toml
mcp_optional_startup_grace_ms = 0

[mcp_servers.<service>]
startup_timeout_sec = 45
```

Use the service profile's finite timeout (n8n uses 45 seconds), preserve a
separate tool-call timeout, and keep write-capable tools behind an explicit
client approval prompt. Do not put the global setting inside an MCP table or
duplicate it under a server. Keep the global configuration mode `0600` and
never paste a helper's bearer-header JSON into a command, log, ticket, or
tracked file.

The running remote-control process reads this setting only at startup. Apply it
at a safe checkpoint with the actual user-runtime restart, for example:

```bash
systemctl --user restart codex-remote-control.service
```

This restart disconnects the active remote-control task. Checkpoint first, then
wait for the service to return and reconnect with a new task. Verify that the
native n8n tools are present before continuing; editing the file or reloading a
unit is not sufficient if the existing process remains alive.

For a safe smoke test, let the configured MCP client invoke the dynamic header
helper and issue `initialize`, the initialized notification, and then
`tools/list`. Reuse the returned session identifier when the server supplies
one; otherwise follow the server's stateless HTTP behavior. Pipe helper output
directly to that client or to a structural validator that prints only pass/fail.
Record only request status and the presence of a tool catalog; never print the
helper JSON, `Authorization` header, session value, or raw JSON-RPC response.
Confirm that write-capable tools still require approval.

Troubleshoot in this order:

1. If the server is absent but direct authentication works, confirm one
   root-level zero setting, its position before all tables, mode `0600`, and an
   actual runtime restart followed by a new task.
2. If `initialize` fails, check the protected helper configuration, its owner
   and mode, and the scoped credential item without displaying helper output.
3. If discovery or calls time out, inspect helper/network latency and adjust
   only the finite per-server timeout approved by the service profile.

To roll back, remove the root-level line (restoring the 1000 ms default) or
restore the previously approved root value, then restart the runtime and
reconnect with a new task. Leave the per-server timeout and write approval
policy explicit.

## 13. Handoff and lifecycle

Produce a sanitized deployment record containing:

- Purpose, profile, VM resource allocation, and storage layout.
- Operating-system, application, database, helper, Caddy, Docker, and Tailscale
  versions or release channels.
- Configuration and persistent-data paths without secret values.
- DNS, exposure mode, listeners, and access method.
- Update schedule, backup status, health endpoint, and test results.
- Encryption method, unlock procedure, key reference, recovery-key status, and
  header-backup location without including any key material.
- Routine start, stop, logs, update, reboot, and recovery commands.
- All deviations from this runbook and all deferred work.

Update the matching tracked service note whenever a deployment establishes a
reusable decision, consequence, failure mode, or acceptance check. Keep exact
deployment facts in the ignored inventory and handoff so the public note does
not become an infrastructure map.

Before an application update, create the configured backup or snapshot when the
profile enables one. If backups are deferred, let the configured update policy
proceed and record that there is no backup or database rollback point. Retaining
the previous container image does not reverse a database migration. After a
successful update, repeat health, exposure, and persistence checks. When
retiring a service, identify its VM, disks, DNS, certificates, backups, and
external integrations, then obtain explicit authorization before deleting any
of them.
