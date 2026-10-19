# Agent operating rules

These instructions apply to every task performed from this repository.

## Public reference and private inventory

Tracked files are instructions for another operator to build and verify a
similar setup: reusable procedures, reference designs, and templates. They are
not a record of this site's deployment. Explain choices as instructions or
conditions, with their reasons, consequences, and acceptance checks. Reserved
example values, placeholders, and generic service names are allowed when they
are clearly presented as examples.

Do not put live deployment state, operator decisions, audit findings, incident
chronology, change history, observed versions, test outcomes, or pending work
in tracked files, even after removing identifiers. Do not describe a tracked
service note as a sanitized export or a diary of an existing deployment. A
statement such as "the server currently runs" belongs in ignored local records;
write a reusable instruction such as "configure the server to run" in the
public reference only when that instruction is useful to a new operator. A
lesson from a real incident may become a generic failure mode and recovery
procedure after all site provenance and current-state claims are removed.

Tracked files must not contain site-specific domains, addresses, usernames,
hostnames, VM IDs, credentials, tokens, key material, or transient health
output. Keep facts about what this site actually has, did, passed, failed,
deferred, or chose in `inventory.local.yaml`, `AGENTS.local.md`, and ignored
per-service handoffs. A public design can state a default or optional choice;
the local profile and handoff record which choice was made here.

Before any task, read this file and `docs/standards.md`. Then read
`AGENTS.local.md` and `inventory.local.yaml` when those ignored files are present.
Read `RUNBOOK.md`, the selected service profile, and the matching page under `docs/services/`
before infrastructure work. The local files hold deployment-specific facts and
operator handoff; do not copy their live values into tracked files.

Keep the two layers consistent: infrastructure work is incomplete until the
deployment-specific changes update `inventory.local.yaml` and the ignored
handoff. Reusable procedure or pattern changes update the tracked runbook,
templates, and relevant service note. Access, encryption, backup, update, and
credential-provider changes update both layers. Before final reporting,
validate the relevant Markdown, YAML, and shell files and run the publication
safety check. Review every tracked-document diff for deployment-state prose as
well as identifiers: the automated check cannot detect a sanitized diary. If
a sentence reports what happened on this site, move it to an ignored local
record or omit it. Update suitable `updated_at` or `last_verified_at` fields
only in local records; do not store transient health output or secrets in
either documentation layer.

## Access model

- Treat the Proxmox node and its VMs as different systems.
- Connect to the Proxmox node using `PROXMOX_ADMIN_USER` from `.env`.
- Connect to VMs using `VM_ADMIN_USER` from `.env`. The VM administrator has
  passwordless sudo.
- Use the QEMU Guest Agent for Proxmox-side provisioning, status, and recovery.
  It is not an SSH authentication mechanism.
- When a managed VM rejects its administrator's approved SSH key, check the
  authenticated Proxmox management route and use the runbook's guest-agent key
  recovery procedure when the requested work already authorizes that key and
  account. A failed guest SSH login does not prove that Proxmox recovery is
  unavailable. Preserve existing authorized keys and verify strict SSH login
  afterward.
- Version 1 supports VMs only. Do not silently substitute an LXC container.

## SSH execution environment

- For operator-requested SSH access to remote systems, use the session's
  permitted outside-sandbox execution route first. This repository is used to
  access other systems; a sandbox-only SSH failure is not evidence that the
  remote host is inaccessible.
- If OpenSSH reports bad ownership or permissions on a system SSH configuration
  file inside the sandbox, do not change that file. Retry the already-authorized
  SSH operation outside the sandbox when the current session provides and
  permits that route.
- If outside-sandbox execution is unavailable or disallowed, inspect
  `AGENTS.local.md` and the target's ignored handoff for an approved route
  before considering a direct connection with SSH configuration disabled.
- Use a direct `ssh -F /dev/null` fallback only when the target is reachable
  without the system configuration and its host key is already verified. Keep
  strict host-key checking and batch mode enabled, and supply any approved
  identity or connection options that were configured for the target. Never
  accept an unverified host key or weaken host-key checking.

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

Follow the canonical [shared operating standards](docs/standards.md) and the
selected service profile. The [runbook](RUNBOOK.md) owns implementation and
recovery procedures; service guides own application-specific requirements.
Update the canonical source when a shared rule changes instead of maintaining
parallel defaults here or in a service guide. Record actual choices and any
authorized deviations only in ignored local records.

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
- An ignored local deployment record containing versions, paths, tests, exceptions,
  maintenance commands, and recovery instructions.
