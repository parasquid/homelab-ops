# Shared operating standards

Use these requirements for managed private services and their operating tools.
The [runbook](../RUNBOOK.md) owns implementation procedures; service and topic
guides add application-specific choices and checks. Select supported exceptions
explicitly in the local profile. Public sites need their own authorized exposure
design; their routing does not change private-service defaults.

The VM, application-storage, and private-ingress requirements apply to service
VMs. Workstation tools and public publishing inherit the relevant credential,
tooling, cutover, and verification rules; they retain their documented host and
exposure designs.

## Documentation ownership

| Document | Owns |
| --- | --- |
| This page | Shared requirements and canonical procedure links. |
| [RUNBOOK.md](../RUNBOOK.md) | Provisioning, access, encryption, credentials, HTTPS, updates, and acceptance procedures. |
| [Service guides](services/README.md) and topic guides | Application behavior, integrations, exceptions, and additional checks; link shared procedures instead of copying them. |
| Local profile | Selected resources, release line, exposure, encryption, and recovery choices. |
| Ignored inventory and handoff | Live identifiers, versions, decisions, audit findings, results, maintenance commands, recovery references, and pending work. |
| [AGENTS.md](../AGENTS.md) | Agent execution constraints and the requirement to follow these standards. |

Tracked files teach another operator how to build and verify a similar system.
Keep deployment history and current-state claims private even after removing
identifiers. Neither documentation layer is a secret store. Run the publication
check and separately review tracked prose before publishing.

## VM identity and access

Use dedicated full VMs, official checksum-verified Debian images, cloud-init,
autostart, and a working QEMU Guest Agent. Inspect capacity and conflicts before
selecting resources; preserve existing services. Treat Proxmox and its guests
as separate systems with their own approved administrators.

Install the requesting workstation's approved public key for the guest
administrator. Use cloud-init for new guests and the authenticated Proxmox
management route with the guest agent for existing-key recovery. The Proxmox
API or node CLI can carry those calls. Preserve existing keys; never transfer
a workstation private key. The guest agent is not SSH authentication.

Use key-only OpenSSH to the verified tailnet IP or hostname, with strict
host-key checks, a locked administrator password, and passwordless sudo.
Tailscale supplies the VPN; disable Tailscale SSH in the guest unless explicitly
selected. Verify login and sudo after provisioning or recovery.

Procedures: [VM creation](../RUNBOOK.md#4-create-the-vm),
[VM access](../RUNBOOK.md#5-configure-vm-access), and
[approved-key recovery](../RUNBOOK.md#recover-a-vms-approved-openssh-key-through-proxmox).

## Storage and encryption

Use sparse virtual disks and ext4 by default, regardless of the host pool.
Monitor actual pool allocation, filesystem space, and inodes. Separate the
replaceable OS disk from persistent application state; size for generated data
and growth as well as original content.

Select encryption explicitly. For `guest-luks-data`, the OS boots Debian and
Tailscale while a separate LUKS data disk holds configuration, secrets, database
and media data, Docker state, and containerd's persistent root. Docker's
`data-root` alone does not move containerd. Require the data mount before its
consumers and update jobs can start. Leave no application secrets or Docker and
containerd persistent metadata on the OS disk.

Keep automation keys off the guest, with an independent recovery passphrase and
off-VM header copy. Refresh the header copy after keyslot changes. A reboot is
deliberately locked until remote unlock mounts the disk and starts services;
verify both states. This protects a copied data disk, not an unlocked guest
from its hypervisor administrator.

Procedure: [guest LUKS](../RUNBOOK.md#6-configure-optional-guest-luks-encryption).

## Vaultwarden and Bitwarden CLI

After bootstrap, Vaultwarden is the primary agent-managed credential store.
Give each agent host its own organization User scoped to the intended collection.
Use the Bitwarden password-manager CLI (`bw`) against the verified private vault
URL, with protected bootstrap credentials outside the repository. Verify account
and collection scope before use; pin the exact item, expected identity, format,
and intended destination. Keep decrypted values and CLI sessions in memory.

```text
external Vaultwarden unlock key -> Vaultwarden
protected CLI bootstrap -> scoped agent account -> exact vault item
  service LUKS key -> standard input -> remote cryptsetup
  Cloudflare DNS token -> protected encrypted file -> Caddy DNS validation
```

Store unique service automation keys as base64 with the expected decoded size;
test retrieval against the intended LUKS header before relying on it. Keep
Vaultwarden's own unlock key available outside Vaultwarden. Preserve independent
recovery and bootstrap copies until a tested replacement and explicit removal
authorization. External files remain a supported bootstrap or selected recovery
provider.

Never print secrets or sessions, put them in arguments/history, or expose a
general credential API. Local provider configuration contains references, not
raw tokens or LUKS bytes. Protect secret files with mode `0600` and their
directories with `0700` where practical.

Procedures: [agent account and CLI setup](../RUNBOOK.md#agent-scoped-organization-accounts),
[credential retrieval](../RUNBOOK.md#retrieve-a-service-credential), and
[Vaultwarden LUKS helper](../RUNBOOK.md#vaultwarden-backed-luks-unlock).

## Private DNS and HTTPS

Use DNS-only Cloudflare records pointing to the VM's Tailscale address. Bind the
application to loopback and Caddy HTTPS to the tailnet address. Keep databases
and internal brokers on Compose-only networks. Public ingress, proxying, Funnel,
and router forwarding require an explicit profile. DNS-only is not access
control: check tailnet policy, firewalls, and actual listeners.

Retrieve the intended zone-scoped Cloudflare token from its exact vault item.
Check credential authorization and destination before transfer. Install over a
host-key-verified connection in an owner-only file on mounted encrypted storage;
give Caddy file-backed access and load it at process startup. Keep the token out
of the Caddyfile and Docker environment metadata. Validate through the same
secret-loading entrypoint used by the service.

Use DNS validation without public challenge ports. Verify certificate chain,
hostname, expiry, and renewal. Keep the admin API private and disable unnecessary
HTTP redirects and HTTP/3 listeners according to the profile.

Procedure: [private DNS and HTTPS](../RUNBOOK.md#9-configure-private-dns-and-https).

## Containers, maintenance, and cutovers

Use supported images, persistent volumes, meaningful health checks, bounded logs,
and restart policies. Keep coupled components compatible and databases within a
selected major. Standardize configuration under `/opt/<service>` and consistently
use the physical Compose directory when it is a symlink.

Track the selected stable application line with guarded automatic updates at the
configured local maintenance time; preview is an explicit choice. Require mounts,
prevent overlap, bound logs, check health, and retain previous images until
acceptance. Enable OS security updates and plan compatibility-changing migrations.
A previous image does not reverse database or application-state migrations.

Select backup and recovery behavior in the profile, including an intentional
deferral. Before a cutover, validate the candidate, preserve configured recovery
state, and recheck the exact target for concurrent changes. Verify the deployed
result. Inspect actual state after ambiguous or interrupted operations before
retrying; preserve unrelated resources.

Procedures: [container layout](../RUNBOOK.md#7-install-docker-and-lay-out-the-application),
[updates](../RUNBOOK.md#8-configure-automatic-application-updates), and
[handoff](../RUNBOOK.md#13-handoff-and-lifecycle).

## Shared tools and acceptance

Reuse established shared runtimes, package pins, and lockfiles. Isolate caller
state and obtain operator approval before upgrading a runtime shared with other
callers. For substantial build, test, or browser output, verify disk-backed
storage, set `TMPDIR`, `TMP`, and `TEMP`, and direct tool caches/output there;
keep generated state ignored.
The [workspace browser guide](workspace-browser.md) owns Playwright registration
and browser-store details.

Choose the smallest check that answers the unresolved question and reuse passing
evidence while its inputs remain valid. Verify actual authentication, network
exposure, persistence, reboot/unlock behavior, and updates; an HTTP health response
or enabled unit alone is insufficient. Service checks extend the
[shared acceptance procedure](../RUNBOOK.md#10-validate-the-deployment).
Validate relevant Markdown, YAML, and shell files, run
`./scripts/check-publication.sh`, and review tracked diffs for private identifiers
and deployment-state prose. Record outcomes only in ignored local records.
