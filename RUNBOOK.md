# Proxmox service deployment runbook

Follow the [shared operating standards](docs/standards.md) for requirements and
defaults. This runbook owns implementation procedures; service guides link here
and add application-specific choices rather than copying these steps.

This runbook describes the default path for deploying one private service in a
dedicated Proxmox VM. The service profile is authoritative for sizing and
exceptions. Values from the local `.env` supply site-specific configuration.
The matching page under `docs/services/` teaches the reference design choices,
their consequences, and failure modes that another operator can avoid. Record
the choices and results for this site only in ignored local files.

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

Provision every new VM disk as sparse by default, including OS and data disks.
Use a thick allocation only when the service profile explicitly selects it and
records why. On Proxmox, local-lvm is thin by design; configure ZFS-backed
storage for sparse volumes where the storage supports that option. Verify the
storage configuration and per-volume reservation before import or creation.
Track logical provisioned capacity separately from actual allocated bytes and
monitor pool free space, health, and metadata so sparse growth does not exhaust
the backing pool. This is a default for new disks; do not move, recreate, or
convert existing VM disks as part of applying it.

Use ext4 inside the guest as the default filesystem for every new VM disk,
regardless of whether its backing storage is ZFS or thin LVM. A service profile
may name another guest filesystem when the application requires it. For an
encrypted data disk, create ext4 on the unlocked LUKS mapper; do not create a
guest ZFS pool by default. Preserve the selected guest filesystem choice in the
service profile and verify it from inside the VM.

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
- Sparse virtual allocation for every new disk unless its service profile
  explicitly selects thick allocation.
- ext4 as the default guest filesystem for new OS and data disks. For a LUKS
  data disk, put ext4 on the unlocked mapper. The host storage backend does not
  determine the guest filesystem.
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
server. For routine administration, connect from the workstation directly to
the guest's verified Tailscale IP or hostname as `VM_ADMIN_USER`. Connect to the
Proxmox node separately as `PROXMOX_ADMIN_USER` only for Proxmox management or
guest-agent recovery. Interactive enrollment is acceptable; surface the
authorization URL to the operator. An automated authentication key must be
supplied through a protected local mechanism and must not appear in output.

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

### OpenSSH fallback for a restricted execution environment

If a sandboxed SSH client fails before connecting because a system SSH
configuration file appears to have unsafe ownership or permissions, do not
change that system file. For a read-only check, use an explicitly permitted
outside-sandbox route when the active session provides one. If that route is
unavailable, report the check as blocked rather than weakening SSH checks.

When a verified jump VM is the approved path to the Proxmox LAN address, use an
OpenSSH `ProxyCommand` with the normal VM administrator and Proxmox administrator
identities. Replace every bracketed value with the values from the local
inventory; they are placeholders here:

```bash
ssh \
  -o BatchMode=yes \
  -o StrictHostKeyChecking=yes \
  -o HostKeyAlgorithms=ssh-ed25519 \
  -o 'ProxyCommand=ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o HostKeyAlgorithms=ssh-ed25519 <vm-admin>@<jump-vm> -W %h:%p' \
  <proxmox-admin>@<proxmox-lan-address> '<read-only-command>'
```

Verify both host keys through a trusted path before using the route, and record
the final-hop fingerprint in the ignored inventory. Keep strict host-key
checking enabled for both SSH connections. This route provides network access;
it does not change the authorization or safety requirements for the remote
command. The jump VM opens an ordinary OpenSSH TCP-forwarding channel with
`-W`; the final hop targets the Proxmox LAN address on port 22 and reaches its
ordinary OpenSSH daemon. This may bypass a site-specific Tailscale SSH approval
gate, but does not bypass OpenSSH host-key verification. Do not use
`StrictHostKeyChecking=no`, accept an unverified key, or alter system SSH
configuration ownership to work around the sandbox error.

For a VM reachable only from the Proxmox node, chain another OpenSSH TCP
forward from Proxmox to that VM's private SSH address. Verify and pin each
intermediate and final host key independently, and keep strict host-key
checking enabled on every connection.

### Recover a VM's approved OpenSSH key through Proxmox

When a managed VM rejects public-key authentication, check the authenticated
Proxmox management route independently. The QEMU Guest Agent can inspect and
repair the VM administrator's authorized key without an SSH login to the VM.
Use this route when the requested operation already authorizes that exact
administrator and public key.

Run Proxmox CLI commands such as `qm` on the authenticated Proxmox node, not on
the workstation. In `qm guest exec <VMID> -- <command> <args>`, the command and
arguments after `--` run inside the VM. When a guest command needs protected
stdin, enable `--pass-stdin 1` and forward that input to the remote `qm`
process; pass the guest command separately as arguments rather than using the
same input stream for a script.

1. Bind the Proxmox node, VM ID, guest hostname, administrator and approved
   workstation key to the local inventory. Confirm that the matching private
   identity is available on the requesting workstation. Keep excluded or retired
   identities excluded.
2. Authenticate to Proxmox as `PROXMOX_ADMIN_USER` through a trusted management
   route. Check the VM configuration and guest-agent identity before sending a
   guest command. If Tailscale SSH requires an interactive check, surface its
   authentication URL and wait for the check before continuing dependent work.
3. Through the guest agent, inspect `VM_ADMIN_USER`'s account, home directory,
   actual authorized-key path, file ownership and permissions. Retrieve the
   guest's OpenSSH host-key fingerprint through this trusted route and match it
   to the pinned identity. If the approved key is already present, diagnose its
   options, effective SSH policy and file permissions before making a change.
4. Add only the approved public key if absent. Preserve existing key lines,
   comments and options, use a controlled atomic update of the regular file,
   and set administrator ownership with directory mode `0700` and file mode
   `0600`. Detect duplicate keys by key type and blob rather than comment text.
   Pass input through standard input where supported; never transfer a private
   key or log key bytes.
   Retain a protected preimage before replacing the key file, and refuse the
   write if its contents or metadata have changed since inspection. Persist
   the operation identity before dispatch. If the result is lost or invalid,
   inspect that operation and the actual file before considering a retry.
5. From the requesting workstation, verify a key-only login using the intended
   identity, batch mode and strict host-key checking. Confirm guest hostname,
   administrator identity and passwordless sudo. Reinspect the authorized-key
   file to prove that the approved key occurs once and existing entries remain
   equal. An unchanged rerun must make no key-file mutation.
6. Record exact target, account, key fingerprint, recovery route and verified
   outcome in the ignored inventory and service handoff. Keep live identifiers,
   key material and incident history out of the tracked procedure.

This recovery adds an administrator's approved public key; it does not require
changing SSH daemon policy, enabling root or Tailscale SSH in the guest,
restarting services, rebooting the VM, or changing network exposure.

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
Use Vaultwarden as the primary provider after bootstrap, following the
[credential setup and retrieval procedure](#agent-scoped-organization-accounts).
An external-file provider remains supported for bootstrap or a selected recovery
path: protect the operator-host file with mode `0600` and put only
`LUKS_KEY_DIRECTORY` in `.env`. The
[Vaultwarden unlock procedure](#vaultwarden-backed-luks-unlock) owns key encoding,
item selection, and validation. Supply either provider's key over standard input;
never put decoded bytes in `.env`, arguments, logs, the guest, or the repository.

Keep an independent human recovery passphrase outside Vaultwarden, protected
and available before Vaultwarden can be reached. Do not rely on Vaultwarden to
unlock its own encrypted storage or as the only credential path to a system
that must be available before Vaultwarden.

Before formatting, resolve the added disk through a stable `/dev/disk/by-id`
path and verify its serial, capacity, VM attachment, and lack of existing
signatures. Never rely on a transient name such as `/dev/sdb` without those
checks.

Install the distribution's `cryptsetup` package from its signed official
repository before formatting, and verify that the guest command is available.
Do not start formatting when the utility is missing. After an interrupted SSH
operation, reconnect and inspect the disk identity and LUKS header before
retrying: a lost SSH session can hide the guest command's actual error.

Format the LUKS mapper as ext4 unless the service profile explicitly selects a
different guest filesystem. Use ext4 lazy initialization and do not run a
whole-disk zeroing, random-fill, or discard pass when sparse virtual allocation
is intended. Check the backing pool's actual allocated bytes after formatting
and filesystem creation; do not infer allocation from the virtual disk's
logical size. For example:

```bash
sudo mkfs.ext4 \
  -E nodiscard,lazy_itable_init=1,lazy_journal_init=1 \
  /dev/mapper/service-data
```

`nodiscard` prevents the formatter from discarding the virtual device. Lazy
inode-table and journal initialization reduce format-time writes; the kernel
completes the deferred work after the first mount, so allow that initialization
to finish before treating format-time performance as steady-state. Ext4
metadata and its deferred initialization still allocate backing blocks as they
are written. Record the host pool's actual allocated bytes before and after
each disk-writing stage, then again after lazy initialization settles; sparse
allocation does not imply zero metadata allocation.

Pass the key through standard input for both format and unlock operations. A
remote unlock follows this pattern:

```bash
ssh "${VM_ADMIN_USER}@${VM_HOST}" \
  'sudo cryptsetup open /dev/disk/by-id/<verified-disk> service-data --key-file=-' \
  < "${LUKS_KEY_FILE}"
```

Create the profile's guest filesystem (ext4 by default) and mount the mapper at
the profile's mount point. Place Docker's data root, containerd's persistent
root, `/opt/<service>`, application secrets, and all persistent bind mounts on
this filesystem. Configure Docker, containerd, Caddy, and the application so
they cannot start before the encrypted filesystem is mounted. Place Caddy's
protected token file on this filesystem and use the runtime file-loading
pattern in [private DNS and HTTPS](#9-configure-private-dns-and-https).

Keep automation and human recovery credentials in separate keyslots. Use the
[existing-volume enrollment procedure](#add-an-automation-key-to-an-existing-luks-volume)
to add a missing credential and verify both paths before accepting the deployment.

With remote-script unlock, unattended application recovery after a VM reboot is
deliberately disabled. The VM and Tailscale start, but Docker, Caddy, and the
application remain stopped until the data disk is unlocked, mounted, and the
services are started. Test both the locked and unlocked boot states.

### Add an automation key to an existing LUKS volume

An existing encrypted volume can gain an independent automation credential
without formatting or re-encrypting its data. Preserve its working recovery
passphrase and existing keyslots. Slot numbers are deployment choices; record
the actual assignments locally instead of assuming fixed numbers.

1. Bind the exact VM, stable device identifier, LUKS UUID, and current keyslots.
   Verify an existing unlock credential against that header before changing it.
   Administrative SSH or guest-agent access alone does not satisfy this
   procedure's credential prerequisite. If a legacy passphrase-only volume is
   already unlocked but its passphrase cannot be supplied through a protected
   input path, use the restricted alternate procedure below. Keep independent
   recovery available.
2. Save a protected header copy outside the VM and its Proxmox storage before
   enrollment. Check available guest memory and run only one key derivation at
   a time; Argon2 can consume enough memory to disrupt running applications.
3. Generate a unique service automation key, for example 64 random bytes.
   Store it base64-encoded in the exact scoped Vaultwarden item with its expected
   decoded length. Follow [credential retrieval](#retrieve-a-service-credential)
   and verify the stored value by an in-memory readback. Never reuse another
   service's key.
4. Add the decoded key to an unused slot with `cryptsetup luksAddKey`, authorized
   by the verified existing credential or, only under the conditions below, the
   active volume key from an already-open legacy volume. Supply both secrets
   through protected input streams or in-memory file descriptors, without
   writing them to the guest or placing their values in arguments. Preserve
   existing slots; use the installed version's
   [key-enrollment options](https://manpages.debian.org/trixie/cryptsetup-bin/cryptsetup-luksAddKey.8.en.html)
   to select the intended new slot explicitly. After an interruption, inspect
   the header and test the stored candidate before retrying enrollment; preserve
   the existing vault key and resolve whether its slot was already added.
5. Retrieve the automation key from its vault item and test that specific slot
   with `cryptsetup open --test-passphrase`. Test the retained recovery credential
   separately, refresh the off-VM header copy, and verify application health.
   Record slot IDs, provider references, header location, and checks privately.

#### Alternate enrollment for an already-open, legacy passphrase-only volume

Use this exception only when the exact LUKS volume is already open, its
device-mapper mapping is active, and the legacy passphrase cannot be supplied
through a protected input path. A privileged operator can ask `dmsetup` for the
active mapping's volume key and stream its decoded bytes directly to
`cryptsetup luksAddKey`. This authorizes adding a keyslot without changing or
removing the passphrase slot. It does not enable remote unlock before the root
filesystem is opened at boot. The example below applies only when the active
mapping exposes the raw volume key as hexadecimal. If the mapping instead shows
a kernel-keyring reference, use `--volume-key-keyring` only when the installed
cryptsetup documentation confirms that key type is readable by userspace.
LUKS2 commonly keeps the key in a kernel `logon` keyring and displays a
reference instead; that reference is not the key and must not be decoded or
treated as a key file. A `logon` payload is intentionally unreadable to
userspace, so stop and use the retained passphrase or another supported
credential in that case. See the installed version's
[key-enrollment options](https://manpages.debian.org/trixie/cryptsetup-bin/cryptsetup-luksAddKey.8.en.html).

1. Verify the device, LUKS UUID, active mapping, root/mount ancestry, and slot
   list independently. Confirm the retained passphrase is known to work, using
   a protected test when available or a recent successful boot unlock when the
   passphrase cannot be supplied remotely. Do not proceed if the mapping is
   closed, the passphrase slot is uncertain, or the target identity is
   ambiguous.
2. Capture and verify a protected off-VM header copy before the change. Prepare
   the unique automation key in the approved secret store and a protected
   input source. Check that the source contains exactly the expected number of
   bytes; `--new-keyfile-size` is a maximum, not an exact-length check.
3. Check that the installed `cryptsetup` supports `--volume-key-file`, determine
   the active volume key's exact size in bits, and inspect the mapper's table
   format. Continue only if its key field is raw hexadecimal; the example parser
   deliberately rejects kernel-keyring references and all other formats. The
   volume key must flow directly from
   `dmsetup table --showkeys` through a strict parser to an anonymous file
   descriptor; never display it, capture it in shell variables, log it, or
   save it to a file. In this legacy layout, retain slot 0 for the existing
   console passphrase and use slot 1 for automation only after confirming slot
   1 is empty. If the slots differ or slot 1 is occupied, stop and review the
   layout. The following is a guest-side script: `dmsetup` and `cryptsetup`
   must run as root inside the already-unlocked VM, not on the workstation or
   Proxmox node. Invoke it through the approved Proxmox guest-agent route using
   `qm guest exec <VMID> --pass-stdin 1 -- /bin/bash -c <guest-script>`; when
   tunneled over SSH, redirect the protected automation-key file to the SSH
   command's standard input. Pass the guest script as a command argument with
   safe quoting; standard input is reserved for the key bytes.

   Example guest-side command shape (replace placeholders only with
   independently verified, non-secret values):

   ```bash
   set -euo pipefail
   VOLUME_KEY_BITS=$(dmsetup table --showkeys "$VERIFIED_MAPPER" |
     python3 -c '
   import sys
   lines = sys.stdin.read().splitlines()
   if len(lines) != 1:
       raise SystemExit(1)
   fields = lines[0].split()
   if len(fields) < 5 or fields[2] != "crypt":
       raise SystemExit(1)
   key = fields[4]
   if not key or len(key) % 2 or any(c not in "0123456789abcdefABCDEF" for c in key):
       raise SystemExit(1)
   print(len(key) * 4)')
   exec 3< <(
     dmsetup table --showkeys "$VERIFIED_MAPPER" |
       python3 -c '
   import sys
   lines = sys.stdin.read().splitlines()
   if len(lines) != 1:
       raise SystemExit(1)
   fields = lines[0].split()
   if len(fields) < 5 or fields[2] != "crypt":
       raise SystemExit(1)
   key = fields[4]
   if not key or len(key) % 2 or any(c not in "0123456789abcdefABCDEF" for c in key):
       raise SystemExit(1)
   sys.stdout.buffer.write(bytes.fromhex(key))'
   )
   cryptsetup luksAddKey --batch-mode \
     --volume-key-file=/proc/self/fd/3 --key-size="$VOLUME_KEY_BITS" \
     --new-keyfile=- --new-keyfile-size="$AUTOMATION_KEY_BYTES" \
     --new-key-slot=1 "$VERIFIED_DEVICE"
   ```

   Keep shell tracing disabled. The remote-execution channel supplies the
   automation key on standard input, while the volume key remains on the
   inherited anonymous descriptor. Do not reuse a failed command's status as
   proof of whether a slot changed; inspect the LUKS metadata before any retry.
4. Verify that the legacy passphrase slot remains present and test the new key
   against its exact slot. Refresh the protected off-VM header copy and verify
   the volume and dependent services. Record this method as an exception in the
   ignored local handoff; keep deployment-specific findings out of public docs.

### Rotate an existing LUKS unlock key

Use this procedure when replacing an automation or recovery key while keeping
the existing encrypted data. Rotation must update every authorized key copy and
remove the old key from both the live header and operational header backups.

1. Identify the exact VM, stable disk identifier, LUKS UUID, mapper, active
   slots, key providers, and every host that can unlock the volume. Test the
   current key against its intended slot and test an independent recovery key
   against its own slot. Do not begin if either required credential is
   unverified or the slot map is ambiguous.
2. Save a protected header backup outside the VM and Proxmox storage. Record
   that this pre-change header preserves the old keyslot state: the removed key
   may still unlock data with this backup. Keep the backup protected during the
   change, and plan to retire it after the final header has been refreshed and
   verified.
3. Generate a new unique key on an encrypted, access-controlled host. Store it
   in a mode-`0600` file under a mode-`0700` directory, and provision it to each
   authorized unlock host through a protected channel. Do not put key bytes in
   command arguments, shell history, logs, guest files, or the repository.
4. Add the new key to an explicitly selected unused slot, authorizing the
   change with the verified old key. Pass key material through standard input
   or inherited file descriptors. Check guest memory and serialize memory-hard
   key derivation so concurrent Argon2 operations do not exhaust the VM.
5. Test the new key against its exact slot, then test the independent recovery
   key against its exact slot. Verify each authorized host has the intended new
   key copy, and verify the service-specific unlock path and application health
   while the old slot remains available.
6. With explicit removal authorization, preflight the exact UUID, slot map,
   old slot, new slot, and recovery slot immediately before removing only the
   old slot. Authenticate removal with the new key. Re-read the header and
   retest the new and recovery credentials after removal.
7. Create a fresh protected header backup from the post-removal header and
   replace the operational copies on every recovery host. Verify the backup
   identifies the same LUKS volume and active slot set. Retire the pre-change
   backup from operational storage; if it must be retained for a defined
   rollback period, treat the old key as still usable until that copy is
   destroyed under the storage's deletion policy.
8. Run the unlock helper and service health check again. Record the new slot
   mapping, external key references, header backup locations, and test results
   in ignored local inventory and handoff files only.

A keyslot provides another way to unlock the same volume; it does not provide
a pre-boot network path. If the OS root is encrypted, normal SSH, Tailscale, and
the guest agent become available only after root unlock. Establish a separate
pre-boot recovery route or migrate to the bootable-OS/separate-data-disk design
before relying on remote unlock. Verify a real locked boot only after the
recovery route is ready. Never remove an old key or recovery copy without
explicit authorization.

### Grow existing guest storage

Before expanding a VM disk, confirm the exact attachment and storage-pool
headroom. Grow each guest layer in order and verify it before proceeding:
partition, active LUKS mapping, any LVM physical volume and logical volume, then
the filesystem. If ext4 is directly on the mapper, grow that filesystem without
inventing an LVM layer. Use the authorized key over standard input for encrypted
operations; do not format an existing disk as an expansion step.

Check `lsblk`, `cryptsetup status`, `pvs`, `lvs`, `findmnt`, and `df` as applicable.
A larger virtual disk alone does not expand its guest filesystem. Verify the
application's final mount and write path before declaring capacity available.

## 7. Install Docker and lay out the application

Install Docker Engine and the Compose plugin from Docker's official repository.
Create `/opt/<service>` and give the VM administrator appropriate ownership.
For encrypted profiles, configure Docker's data root and containerd's persistent
root on the mounted encrypted filesystem before starting either service.

With Docker's containerd image store, Docker's `data-root` does not move image
contents or container snapshots: containerd uses its own persistent `root`,
which defaults to `/var/lib/containerd`. Configure that root separately in
`/etc/containerd/config.toml` and verify both effective storage paths with
mount checks. Monitor free blocks and inodes on both filesystems; extracted
image layers can consume many inodes as well as disk space. See the
[Docker data-directory guide](https://docs.docker.com/engine/daemon/#daemon-data-directory)
and [containerd configuration reference](https://containerd.io/docs/main/man/containerd-config.toml.5/).
For an existing installation, plan a stopped-service migration and preserve
its old store and configuration until health and persistence checks pass.
Never remove raw snapshot directories as a capacity fix.

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

### Relocate an existing containerd store

Treat relocation as stopped-service maintenance. Bind the exact VM, source,
encrypted destination, mapper, configuration and available blocks/inodes before
copying. Hold the deployment updater's actual lock and the package manager's
locks throughout the operation so another job cannot replace the inspected
binaries or recreate containers during maintenance.
Record service and container restart policies, socket activation and the
original configuration so temporary changes can be restored exactly.

Stop application containers gracefully before Docker and containerd. Docker's
live-restore setting can leave them running after the daemon stops. Prevent
socket activation and automatic restarts, and verify that no shim, mounted
snapshot or process can still write the source. After stopping Docker, use
service and kernel state for these checks; Docker inspection would require
restarting the daemon. Retain a complete keyed
application-row baseline at the stopped-application checkpoint; counts alone
cannot establish that persistent state survives the move.

Copy the complete store without pruning snapshots. Preserve numeric ownership,
modes, times, hard links, symlinks, special files, ACLs and xattrs. Verify every
entry and regular-file content with a bounded-memory, disk-backed manifest;
fail on traversal or attribute errors. Compare sparse-file contents separately
from physical allocation layouts, which may legitimately differ. Flush the
copy before recording verification complete. Keep the original store intact.

Change only the intended persistent root and enforce an encrypted-mount guard
that rejects an absent or wrong filesystem. Bind its filesystem UUID as well
as the mapper and mount path. Validate with the installed
containerd parser and systemd verifier. Start the database separately and
compare the saved row map before starting application writers. Check the
actual active layer paths and mount options, rather than the configured root
alone: the retained source can conceal stale absolute snapshot paths. Verify
task-runner registration for this application restart using the installed
broker contract; a running launcher or an unrelated health endpoint does not
prove registration. Keep log bodies and runner identifiers out of receipts.

Remove the exact inactive original only with explicit authorization and after
copy equality, encrypted-root use, persistence and health checks pass. Verify
recovered blocks/inodes and restore the recorded restart and maintenance
policies. Once the new store receives writes, the original is stale; rollback
requires a stopped, verified reverse migration rather than selecting the old
path. Preserve durable operation stages so an interrupted change can be
resolved before any retry.

## 8. Configure automatic application updates

The default policy tracks the application's stable release channel and updates
daily at 03:00 local time. A preview channel must be named explicitly in the
service profile.

Select the automatically maintained services in the profile. Pull and recreate
that explicit service set, including version-coupled companions, while keeping
database, extension, and other compatibility-changing maintenance separate.
Preserve the Compose project, persistent mounts, and volume identities; do not
remove unrelated services as part of an update.

Wrap the updater in a non-overlapping cron job or systemd timer. Before pulling
or changing containers, verify the expected filesystem UUID and encrypted-mount
identity for application configuration, persistent data, Docker, and containerd.
Fail closed when a required mount is absent or wrong. Retain bounded logs on
success and failure, wait for every selected service's defined health check,
compare the running images with the pulled images, and check the application's
reported version. Make failures observable through the scheduler's failed state
or the profile's selected reporting path. Do not prune previous images until
acceptance or automatically downgrade after a failure: an older image cannot
reverse a state migration. When a deployment has no backup, record that risk
explicitly before enabling automatic updates.

If the application directory is a symlink into the encrypted mount, run the
updater from its resolved physical directory or pass an explicit Compose
project directory. Compose resolves relative secret files, project names, and
named volumes from that directory; invoking it through the symlink can create
a parallel project with empty volumes or fail to find the secret file.

Test the actual scheduled entrypoint manually before enabling the schedule.
Verify that an absent or mismatched mount blocks mutation and a held lock
prevents overlap. An update test may correctly be a no-op when the selected
images are already current; still verify the running image and health checks.
Route manual maintenance through the same guard and lock.

Operating-system security updates are independent of container updates. Enable
the distribution's unattended security updates; handle distribution releases
and database-major upgrades manually.

## 9. Configure private DNS and HTTPS

Create a DNS-only Cloudflare `A` record for the service hostname pointing to the
VM's Tailscale IPv4 address. Check for an existing record first. Do not overwrite
or repurpose an unrelated hostname.

For another private web UI on the same VM, use an auxiliary hostname in the
`<component>.<service>.<base-domain>` form, such as
`pages.<service>.<base-domain>`. Check for conflicting A, AAAA, and CNAME
records, then create a separate DNS-only A record to the same Tailscale IPv4
address and add a matching Caddy site block. Use the Tailscale ACL to restrict
HTTPS to the intended operators; a DNS-only record does not provide access
control. Prefer Caddy's static file server over a new application process when
the UI can be built as static assets. Give each application its own path prefix
on a shared page hostname; leave the host root available for a generic index
or additional services.

Install Caddy with the Cloudflare DNS provider. Store its zone-scoped API token
in a root-readable mode-0600 secret file on the encrypted data mount. For a
Compose deployment, grant it to Caddy through a file-backed service secret and
load it into the Caddy process at runtime; do not place the token in the
Compose environment, Docker metadata, logs, or Caddyfile. The Caddyfile should
contain only an environment reference.

For the token provider, follow
[service credential retrieval](#retrieve-a-service-credential) with the exact
Vaultwarden item authorized for the intended zone. The Caddy Cloudflare module
documents a single token with `Zone.Zone:Read` and `Zone.DNS:Edit` restricted to
the managed zones; verify its
[current requirements](https://github.com/caddy-dns/cloudflare#configuration)
when provisioning. Stream the selected token field through the verified
connection into the protected destination file without logging it. A protected
external source may supply bootstrap or recovery when selected in the profile.

Before copying a Cloudflare API token to a managed VM, check the private
inventory and agent handoff for the exact token source, intended service,
destination host and path, and any standing operator authorization. Confirm
that the destination data volume is mounted and encrypted, that the target is
restricted to the service owner with mode 0600, and that the token will be used
only for the approved Cloudflare API or DNS-01 operation. Transfer over a
host-key-verified encrypted connection; verify file equality and permissions
without displaying token bytes. Stop if the purpose, destination, encryption,
or file protection cannot be verified. Ask for specific approval only when no
standing authorization covers the verified operation. Keep site-specific
authorization terms in the ignored local instructions, not this public reference.

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
on the Tailscale address only, that port 80 is not opened by an automatic
redirect, and that the certificate validates from a tailnet-connected device.
If Caddy is containerized and the application listens on the VM's loopback
interface, use host networking (or an equally narrow, verified path) so the
proxy can reach that loopback listener. Keep the application bound to loopback;
do not widen its bind address to make a bridge network work. Disable or bind
Caddy's admin API to loopback. If HTTP/3 is not needed, configure the HTTPS
server for HTTP/1.1 and HTTP/2 only so it does not open UDP 443. Inspect TCP and
UDP listeners after startup and confirm that only the intended Tailscale
address has the HTTPS listener.

Configure the application with its external HTTPS URL and trusted-proxy setting
when required. Do not assume every application interprets forwarded headers the
same way; verify against its current upstream documentation.

## 10. Validate the deployment

Run and record these acceptance checks:

1. VM resources, disk size, network, autostart, and guest-agent status match the
   profile.
2. Tailscale is healthy and `VM_ADMIN_USER` can log in and use sudo.
3. Containers are running and all defined health checks pass. After an
   installer finishes, inspect the actual container list and listening sockets;
   do not infer container state from an inactive unit or an installer
   `--no-start` option. If an unexpected service or listener appears, stop the
   scoped application through its documented service path and confirm the
   containers and sockets are gone. Preserve volumes while investigating.
4. Persistent data exists in the documented locations.
5. The hostname resolves to the intended Tailscale address.
6. HTTPS returns the expected application response with a valid certificate.
   For authenticated applications, also complete a real login through the
   private endpoint; an HTTP health response alone does not verify the auth
   path. Do not create public DNS or widen ingress before login succeeds.
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

### Retrieve a service credential

Use the [Bitwarden password-manager CLI](https://bitwarden.com/help/cli/) with
the verified self-hosted Vaultwarden URL and the scoped agent account established
above. Keep the bootstrap credential outside the repository; use a protected
file or password environment mechanism instead of a password argument. Capture
the unlock result in memory without printing it, and keep the session out of
command arguments and logs.

1. Read the protected provider configuration: server, account, collection, exact
   item reference, expected item name, field, encoding, and intended destination.
   Reuse an applicable standing credential-use grant; confirm the service and
   destination before transmitting any value.
2. Check CLI server and account identity, unlock without exposing the session,
   and sync before selecting the item. Use an owner-only CLI state directory;
   isolate temporary state on disk-backed storage when the normal cache is
   unavailable. Do not change an unrelated caller's server or account state.
3. Fetch and parse the exact item in memory. Verify its identity and collection
   membership, then select only the intended field and validate its expected
   format. Fail on ambiguity, mismatched scope, or an unexpected destination.
4. Send the value directly to its consumer: standard input for a LUKS operation,
   or a protected file on the verified encrypted destination for a Caddy DNS
   token. Follow [private DNS and HTTPS](#9-configure-private-dns-and-https) for
   token transfer, permissions, and secret loading. Never print the response or
   put decrypted values in container metadata, history, or temporary files.
5. Release the helper's session and in-memory values when finished, preserving
   unrelated callers. Verify the consumer result and record only references,
   permissions, identity checks, and outcomes in the ignored handoff.

The local header cache described below is an optional, explicitly scoped
optimization; it is not a general credential-retrieval service.

### Vaultwarden-backed LUKS unlock

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

### HTTP credentials and scoped caches

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

Set the background refresh interval explicitly; the reference header cache uses
15 minutes. After a token rotation, sync the CLI vault, restart the cache service,
and reconnect its client so it cannot continue using an old in-memory header.
Verify the new credential without printing the header.

For additional agent credentials, keep a general Vaultwarden API outside the
baseline design. Extend a scoped local cache only with a protected allowlist
that maps service aliases to exact collection and
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
is the supported path. Treat a gopass adapter as a separate extension outside
this reference design. A raw Mailpit capture alone does not exercise
Vaultwarden's SMTP configuration; perform a real verification-email acceptance
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

Produce an ignored local deployment record containing:

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

For a workstation expected to host unattended remote execution, follow the
[remote host availability procedure](docs/remote-host-availability.md). Record
the effective idle policy, live inhibitor, boot enablement, reboot verification,
and recovery path in the ignored local handoff.

Update the matching tracked service note only when work reveals a reusable
procedure, design tradeoff, generic failure mode, or acceptance check. Write
it as guidance for a new operator. Put the originating deployment's status,
history, and exact identifiers only in the ignored inventory and handoff.

Before an application update, create the configured backup or snapshot when the
profile enables one. If backups are deferred, let the configured update policy
proceed and record that there is no backup or database rollback point. Retaining
the previous container image does not reverse a database migration. After a
successful update, repeat health, exposure, and persistence checks. When
retiring a service, identify its VM, disks, DNS, certificates, backups, and
external integrations, then obtain explicit authorization before deleting any
of them.
