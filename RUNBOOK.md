# Proxmox service deployment runbook

This runbook describes the default path for deploying one private service in a
dedicated Proxmox VM. The service profile is authoritative for sizing and
exceptions. Values from the local `.env` supply site-specific configuration.

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
    sudo: ALL=(ALL:ALL) NOPASSWD: ALL
```

Provide an approved SSH public key when regular SSH is needed. Do not put a
private key or reusable Tailscale credential in committed cloud-init data.

Boot the VM and wait for cloud-init and the guest agent to finish before
installing the application. Expand the root filesystem to the provisioned disk
size and verify time synchronization and timezone.

## 5. Configure VM access

Install Tailscale from its official repository, enroll the VM, and enable
Tailscale SSH. Interactive enrollment is acceptable; surface the authorization
URL to the operator. An automated authentication key must be supplied through a
protected local mechanism and must not appear in output.

Verify login as `VM_ADMIN_USER` and verify passwordless sudo. Direct root login
inside the VM is a recovery path rather than the standard administration path.
The Proxmox node continues to use its own administrator from `.env`.

## 6. Install Docker and lay out the application

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

Start the stack, wait for health checks, and test its loopback endpoint before
adding DNS or Caddy.

## 7. Configure automatic application updates

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
wait for the defined health check, and report failures. Do not prune the previous
images until the new deployment is healthy. When a deployment has no backup,
record that risk explicitly before enabling automatic updates.

Operating-system security updates are independent of container updates. Enable
the distribution's unattended security updates; handle distribution releases
and database-major upgrades manually.

## 8. Configure private DNS and HTTPS

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

## 9. Validate the deployment

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

## 10. Handoff and lifecycle

Produce a sanitized deployment record containing:

- Purpose, profile, VM resource allocation, and storage layout.
- Operating-system, application, database, helper, Caddy, Docker, and Tailscale
  versions or release channels.
- Configuration and persistent-data paths without secret values.
- DNS, exposure mode, listeners, and access method.
- Update schedule, backup status, health endpoint, and test results.
- Routine start, stop, logs, update, reboot, and recovery commands.
- All deviations from this runbook and all deferred work.

Before an application update, create the configured backup or snapshot. After a
successful update, repeat health, exposure, and persistence checks. When
retiring a service, identify its VM, disks, DNS, certificates, backups, and
external integrations, then obtain explicit authorization before deleting any
of them.
