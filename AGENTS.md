# Agent operating rules

These instructions apply to every task performed from this repository.

## Public reference and private inventory

Tracked files are reusable procedures, sanitized examples, and templates. They
must not contain site-specific domains, addresses, usernames, hostnames, VM
IDs, credentials, tokens, key material, or transient health output.
Reserved example values, placeholders, and generic service names are allowed
when they are clearly presented as examples.

Before any task, read this file and then read `AGENTS.local.md` and
`inventory.local.yaml` when those ignored files are present. Read `RUNBOOK.md`,
the selected service profile, and the matching page under `docs/services/`
before infrastructure work. The local files hold deployment-specific facts and
operator handoff; do not copy their live values into tracked files.

Keep the two layers consistent: infrastructure work is incomplete until the
deployment-specific changes update `inventory.local.yaml` and the ignored
handoff. Reusable procedure or pattern changes update the tracked runbook,
templates, and relevant service note. Access, encryption, backup, update, and
credential-provider changes update both layers. Before final reporting,
validate the relevant Markdown, YAML, and shell files and run the publication
safety check. Update suitable `updated_at` or `last_verified_at` fields, but
do not store transient health output or secrets in either documentation layer.

## Access model

- Treat the Proxmox node and its VMs as different systems.
- Connect to the Proxmox node using `PROXMOX_ADMIN_USER` from `.env`.
- Connect to VMs using `VM_ADMIN_USER` from `.env`. The VM administrator has
  passwordless sudo.
- Use the QEMU Guest Agent for Proxmox-side provisioning, status, and recovery.
  It is not an SSH authentication mechanism.
- Version 1 supports VMs only. Do not silently substitute an LXC container.

## Before changing anything

- Read `RUNBOOK.md`, the selected service profile, and the relevant service
  note under `docs/services/`.
- Inspect capacity, storage, existing VM IDs, DNS records, and current network
  listeners before choosing values.
- Confirm that the target VM ID, hostname, DNS record, storage volume, and
  configuration directory do not belong to another service.
- Explain any required deviation from the profile before applying it.
- Preserve existing VMs, DNS records, storage, backups, and network policy.

## Secrets and sensitive configuration

- Never print, commit, paste into chat, or include in reports the contents of
  `.env`, environment files, credentials, tokens, passwords, encryption keys,
  certificates, or private keys.
- Never run broad environment dumps such as `env`, `printenv`, raw container
  inspection, or unredacted configuration output on systems containing secrets.
- Do not enable shell tracing with `set -x` in secret-handling code.
- Validate that required variables exist without displaying their values.
- Pass credentials through protected files, standard input, or a dedicated
  secret mechanism. Avoid placing them in command arguments or shell history.
- Protect local secret-bearing files with mode `0600` and their directories
  with mode `0700` where practical.
- Honor any standing credential-use authorization recorded in the ignored
  `AGENTS.local.md` for operator-requested work. Do not ask again solely to
  retrieve or use an authorized agent credential. Check the intended service
  and destination before transmitting it; a standing grant does not authorize
  unrelated destinations or destructive operations.
- Store LUKS automation keys outside the repository. Put only the external key
  directory or key reference in `.env`; do not store a raw LUKS key there.
- Pass LUKS key material through standard input. Never put it in cloud-init,
  the VM filesystem, a command argument, or deployment output.

## Deployment defaults

- Download operating-system images from official sources and verify their
  published checksum before importing them.
- Enable VM autostart and the QEMU Guest Agent.
- Create `VM_ADMIN_USER` with a locked password and passwordless sudo through
  cloud-init. Authenticate to OpenSSH with an approved key over the tailnet;
  leave Tailscale SSH disabled unless the operator explicitly requests it.
- Place application configuration under `/opt/<service>`.
- Bind private application ports to loopback. Keep databases and internal
  brokers on Compose-only networks.
- Use bounded container logs, persistent data volumes, health checks, and a
  restart policy.
- Default to DNS-only Cloudflare records that resolve to a Tailscale address.
- Bind Caddy to the Tailscale address and obtain certificates with DNS
  validation.
- Do not enable Cloudflare proxying, Tailscale Funnel, router forwarding, or
  public ingress unless the service profile explicitly requires it.
- Automatically update application containers from the selected stable channel
  at the configured maintenance time. Preview channels require an explicit
  profile choice. Keep database images within a selected major version.
- When a profile selects guest LUKS encryption, use a separate encrypted data
  disk for application configuration, secrets, Docker state, and persistent
  data. Leave no application secret or Docker metadata on the OS disk.

## Safe execution

- Make operations resumable and safe to rerun after interruption.
- Do not overwrite an unrelated DNS record or an existing VM.
- Do not delete a VM, disk, volume, backup, DNS record, or application data
  without explicit authorization and an exact target check.
- Before formatting a LUKS target, verify its stable device identifier, expected
  size, VM attachment, and absence of existing signatures or data. Treat a
  mismatch as a hard stop.
- Do not automatically prune the previous container image before the updated
  service passes its health checks.
- When interactive Tailscale authorization is required, provide only the
  authorization URL and continue independent work that does not depend on it.

## Definition of done

A deployment is complete only after recording and verifying:

- VM resources, storage, autostart, cloud-init, and guest-agent operation.
- Tailscale connectivity and SSH access as `VM_ADMIN_USER`.
- DNS resolution, certificate validity, application health, and database health.
- Intended listener bindings and absence of unintended LAN or public exposure.
- Persistence and automatic service recovery after a VM reboot.
- For encrypted deployments, the locked-boot state, remote unlock path, service
  start after unlock, recovery keyslot, and off-VM header backup.
- The configured update policy and the outcome of an update-path test.
- Backup status, including an explicit statement when backups are deferred.
- A sanitized deployment record containing versions, paths, tests, exceptions,
  maintenance commands, and recovery instructions.
