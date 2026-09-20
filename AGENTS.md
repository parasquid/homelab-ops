# Agent operating rules

These instructions apply to every task performed from this repository.

## Access model

- Treat the Proxmox node and its VMs as different systems.
- Connect to the Proxmox node using `PROXMOX_ADMIN_USER` from `.env`.
- Connect to VMs using `VM_ADMIN_USER` from `.env`. The VM administrator has
  passwordless sudo.
- Use the QEMU Guest Agent for Proxmox-side provisioning, status, and recovery.
  It is not an SSH authentication mechanism.
- Version 1 supports VMs only. Do not silently substitute an LXC container.

## Before changing anything

- Read `RUNBOOK.md`, the selected service profile, and the relevant example.
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

## Deployment defaults

- Download operating-system images from official sources and verify their
  published checksum before importing them.
- Enable VM autostart and the QEMU Guest Agent.
- Create `VM_ADMIN_USER` with a locked password and passwordless sudo through
  cloud-init. Authenticate with Tailscale SSH or an approved SSH key.
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

## Safe execution

- Make operations resumable and safe to rerun after interruption.
- Do not overwrite an unrelated DNS record or an existing VM.
- Do not delete a VM, disk, volume, backup, DNS record, or application data
  without explicit authorization and an exact target check.
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
- The configured update policy and the outcome of an update-path test.
- Backup status, including an explicit statement when backups are deferred.
- A sanitized deployment record containing versions, paths, tests, exceptions,
  maintenance commands, and recovery instructions.
