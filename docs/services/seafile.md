# Seafile deployment guide

Follow the [shared operating standards](../standards.md) and
[deployment runbook](../../RUNBOOK.md) for a new private Seafile VM or a planned
migration. This guide adds Seafile-specific storage, component, and recovery
requirements. Record deployment facts only in the ignored local records.

## Design choices

- Use a dedicated VM so large file storage and indexing have a separate
  resource and failure boundary.
- Keep the service private behind Caddy on the VM's Tailscale address. Use a
  DNS-only Cloudflare record, DNS certificate validation, and no public ingress.
- Follow the current Seafile Community Edition Docker Compose guide and use its
  supported component set. Pin the database to a selected major version and
  keep version-coupled components on a compatible release channel.
- For a new VM, keep the replaceable OS disk separate from an additional
  encrypted data disk. Size the data disk for library growth, version history,
  and any enabled search index.

## Network and service layout

Use `/opt/seafile` for the Compose project and operator-managed configuration.
Use `/srv/seafile-data` as the mount point for persistent Seafile state. When
the profile selects guest LUKS encryption, place the Compose project, Docker
and containerd state, protected environment file, and persistent data on the
unlocked encrypted filesystem. Use a mount or bind mount so `/opt/seafile`
resides on that filesystem.

Point the upstream Compose volume settings at directories under
`/srv/seafile-data`, for example separate locations for Seafile data, the SQL
database, and an optional search index. Keep databases and internal components
on Compose-only networks. Bind any private application port to loopback and
route HTTPS through the host's private Caddy instance. If the selected upstream
stack includes its own reverse proxy, follow Seafile's instructions for using
another proxy and avoid exposing both proxy layers.

Store credentials in a protected environment file outside Git. Keep the
application's persistent state out of the OS filesystem so a growing library
does not fill the replaceable system disk.

For an encrypted profile, follow the [shared LUKS procedure](../../RUNBOOK.md#6-configure-optional-guest-luks-encryption)
and [Vaultwarden key-provider procedure](../../RUNBOOK.md#vaultwarden-backed-luks-unlock).
These own enrollment, off-VM recovery material, memory safeguards, remote unlock,
and locked-boot acceptance; do not maintain a separate Seafile key workflow.

## Capacity and storage growth

Monitor free blocks and inodes on both the OS filesystem and the Seafile data
filesystem. Check the large directories under `/srv/seafile-data` with `du` and
compare them with `df`; do not infer free space from the VM's virtual disk size
alone. Seafile stores library content in its repository data, while the SQL
database stores metadata, so inspect both layers when diagnosing growth.

Deleted files and libraries may continue to occupy repository storage because
Seafile retains history and a system trash, and unused blocks are collected
separately. Review retention and system-trash policy before running cleanup.
Start with Seafile's garbage-collection dry run. Confirm the edition and
version-specific operating requirements before running a destructive
collection. Never delete repository objects or database files directly as a
space-recovery shortcut. See the upstream [Seafile garbage-collection
guide](https://manual.seafile.com/latest/administration/seafile_gc/).

For capacity expansion, follow [guest storage growth](../../RUNBOOK.md#grow-existing-guest-storage).
Verify the final Seafile data filesystem and database write path before resuming
normal application work.

## Updates and recovery

Use the [shared guarded updater](../../RUNBOOK.md#8-configure-automatic-application-updates).
Track Seafile's stable release channel and use the official upgrade procedure
for version transitions. Do not let routine image updates skip a required
major-version migration. Keep the database on its selected major version,
retain the previous application image until health checks pass, and verify the
login page, uploads, downloads, database health, and persistence after an
update.

If the database or application stops writing when storage is exhausted, restore
filesystem headroom before retrying writes. Then verify the database and
application health and check repository integrity using the procedure for the
selected Seafile version. Avoid deleting data while the cause is still unclear.

## Acceptance checks

Complete the [shared checks](../../RUNBOOK.md#10-validate-the-deployment), then verify:

- HTTPS works from an authorized tailnet client, and the application is not
  reachable through public ingress.
- Caddy binds to the Tailscale address; application ports, databases, and
  internal components have no unintended LAN or public listener.
- The Seafile data filesystem is mounted before Docker and the application
  start when encryption is enabled.
- Compose configuration, protected secrets, Docker state, database state, and
  Seafile repository data persist on their intended filesystems.
- The selected Seafile and database versions start cleanly, and the web UI,
  upload, download, and search functions enabled by the profile work.
- A controlled container recreation preserves libraries and settings, and the
  configured update path passes its health checks.

## Upstream references

- [Seafile Community Edition with Docker](https://manual.seafile.com/14.0/setup/setup_ce_by_docker/)
- [Use another reverse proxy](https://manual.seafile.com/latest/setup/use_other_reverse_proxy/)
- [Docker upgrade procedure](https://manual.seafile.com/latest/upgrade/upgrade_docker/)
- [Seafile garbage collection](https://manual.seafile.com/latest/administration/seafile_gc/)
- [Seafile FSCK](https://manual.seafile.com/14.0/administration/seafile_fsck/)
