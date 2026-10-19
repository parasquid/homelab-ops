# Immich deployment guide

Follow the [shared operating standards](../standards.md) and
[deployment runbook](../../RUNBOOK.md). This guide adds Immich-specific sizing,
storage, release, proxy, and acceptance requirements. Select deployment values
in a local profile and record actual state only in the ignored inventory and
handoff.

## Application choices

- Start with 4 vCPU and 8 GiB RAM, then size for concurrent uploads, transcoding,
  and machine learning. Check the selected release's CPU instruction
  requirements before choosing the VM CPU model. See the upstream
  [requirements](https://docs.immich.app/install/requirements/).
- Allow storage for generated thumbnails and transcoded video as well as
  originals, database growth, and container images. Record upload, PostgreSQL,
  model-cache, and optional external-library paths separately.
- Put `DB_DATA_LOCATION` on a guest-local disk, preferably backed by SSD
  storage; do not use an NFS or SMB mount. The database is part of library
  state, not a disposable index.
- Standardize the Compose project as `/opt/immich`. For the shared LUKS pattern,
  it can point into `/srv/immich-data/app`; use its physical directory
  consistently. Require external-library mounts before starting consumers.

## Compose installation

Follow the upstream [Docker Compose installation](https://docs.immich.app/install/docker-compose/).
Obtain `docker-compose.yml` and `example.env` from the same selected release,
and retain source references locally. Populate `UPLOAD_LOCATION`,
`DB_DATA_LOCATION`, timezone, and an independent database password using the
shared secret-handling rules.

Use the release's supported database image and extensions, with PostgreSQL on
its selected major. Use the same `IMMICH_VERSION` selection for the server and
machine-learning images. Preserve upstream health checks and dependencies;
apply the shared restart and bounded-log policy.

Replace the server's published port with:

```yaml
ports:
  - "127.0.0.1:2283:2283"
```

Validate Compose without printing its expanded environment, start the stack,
and verify container health and the loopback endpoint. Complete first-owner
setup through the private access path using operator-supplied credentials, and
test a real login before accepting the deployment.

## Proxy requirements

Apply the [private DNS and HTTPS procedure](../../RUNBOOK.md#9-configure-private-dns-and-https),
including the Vaultwarden-backed DNS credential path. Proxy a dedicated
hostname's root to `127.0.0.1:2283`; Immich does not support a subpath such as
`/immich`. Preserve forwarded headers and WebSockets, allow intended upload
sizes and durations, and route `/.well-known/immich` to Immich. See the upstream
[reverse-proxy requirements](https://docs.immich.app/administration/reverse-proxy/).

## Updates and recovery

Use the [shared guarded updater](../../RUNBOOK.md#8-configure-automatic-application-updates)
within an explicitly selected stable application major. Keep its release
Compose definition and companion images compatible. Review release notes and
required Compose changes before advancing the line; plan application-major,
PostgreSQL-major, and database-extension migrations separately. Check mobile
client compatibility before a server-major upgrade. Follow the upstream
[upgrade procedure](https://docs.immich.app/install/upgrading/).

Set `IMMICH_VERSION` to the selected stable major tag, such as `v3`, for both
server and machine learning. The guarded job should pull and recreate those
two services together using the release's actual service names:

```bash
docker compose pull immich-server immich-machine-learning
docker compose up -d --no-deps immich-server immich-machine-learning
```

Keep their database and cache dependencies running on compatible, explicitly
selected images. Review release notes for required companion-image or Compose
changes before enabling a release line. Verify both running image identities,
their container health, the server version, and database access after the job;
the public ping endpoint alone only proves HTTP liveness.

Immich does not support downgrading. Retained images are therefore not a
migration rollback. Establish an existing instance's exact versions, database
extensions, and persistent mounts before applying a release definition or
moving storage.

When the profile enables backups, include both the database and original assets,
including external libraries. A database dump contains no photos or videos.
Preserve consistency and test an isolated restore using the upstream
[backup and restore procedure](https://docs.immich.app/administration/backup-and-restore/).

## Additional acceptance checks

Complete the [shared acceptance checks](../../RUNBOOK.md#10-validate-the-deployment),
then verify:

- A real web and mobile login, photo and video uploads, thumbnail generation,
  video playback, and an original download work through private HTTPS.
- Proxy upload limits and timeouts accommodate intended files; mobile discovery
  reaches `/.well-known/immich`.
- PostgreSQL uses its supported local filesystem and extensions. Model-cache,
  upload, and external-library paths match the profile and persist through
  container recreation.
- The configured update path leaves server and machine-learning images
  compatible, with application and database health checks passing.
