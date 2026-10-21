# Vaultwarden deployment guide

Follow the [shared operating standards](../standards.md) and
[Vaultwarden reference procedure](../../RUNBOOK.md#11-vaultwarden-reference-pattern).
This guide identifies the password manager's component choices and extra
acceptance checks. The runbook owns registration, scoped account provisioning,
CLI retrieval, key enrollment, and credential-cache procedures.

## Decisions and consequences

Use a dedicated VM because Vaultwarden is a dependency for other service
recovery paths. Its lifecycle must remain independent of those applications.
Select the shared guest-LUKS data pattern, with Vaultwarden's own unlock key and
recovery material outside the vault so it can start before serving credentials.

Run Mailpit in the Compose project as a private SMTP capture service. Captured
verification and recovery messages stay inside that service; its UI needs
separate authentication. Close anonymous registration after verifying the
owner, while leaving invitations available for controlled onboarding.

## Profile characteristics

- Vaultwarden and Mailpit run in one Compose project.
- Mailpit SMTP has no published host port; its optional UI follows the private
  proxy pattern and has its own authentication.
- Persist Vaultwarden data, Mailpit data, Compose configuration, and secrets on
  the selected encrypted application filesystem.

## Hostnames and SMTP verification

Follow the [Mailpit and SMTP setup](../../RUNBOOK.md#11-vaultwarden-reference-pattern)
for auxiliary hostname naming, UI Basic Auth, and SMTP authentication settings.
A captured message alone does not verify Vaultwarden's mail path: complete a real
verification-email acceptance flow through the private site.

## Registration lifecycle

Use the [canonical registration procedure](../../RUNBOOK.md#registration-lifecycle)
for owner creation, closed signups, invitations, and running-policy checks.
It also owns environment/Admin UI precedence and invitation failure recovery.

## Agent-scoped access

Follow [agent account and CLI setup](../../RUNBOOK.md#agent-scoped-organization-accounts)
before making Vaultwarden a credential provider. Use
[service credential retrieval](../../RUNBOOK.md#retrieve-a-service-credential)
for consumer credentials and the
[LUKS helper procedure](../../RUNBOOK.md#vaultwarden-backed-luks-unlock) for
service unlock keys. Record actual item references and scope-test results only
in the ignored inventory and handoff.

## Future scoped local credential cache

The [shared HTTP-header and scoped-cache procedure](../../RUNBOOK.md#http-credentials-and-scoped-caches)
owns the optional cache design, trust scopes, rotation, and failure behavior.
Keep a general credential API outside the baseline design. An optional cache
must not make Vaultwarden or agent-runtime startup depend on the locked vault.

## Locked boot and recovery

Use the [shared locked-boot and unlock procedure](../../RUNBOOK.md#6-configure-optional-guest-luks-encryption).
Vaultwarden's key cannot be available only inside Vaultwarden. Verify the
independent bootstrap path before other services depend on the vault. For key
replacement, use the [shared LUKS key rotation procedure](../../RUNBOOK.md#rotate-an-existing-luks-unlock-key)
so every authorized host and header backup is updated before the old slot is
retired.

## Updates and backups

Follow the [shared update](../../RUNBOOK.md#8-configure-automatic-application-updates)
and [recovery procedures](../../RUNBOOK.md#13-handoff-and-lifecycle). A same-disk
rollback snapshot and an off-host recovery copy have different failure coverage;
record the profile's selected policy privately.

## Owner and credential handoff

Complete the [shared checks](../../RUNBOOK.md#10-validate-the-deployment), then verify:

- Owner login and a real verification-email acceptance succeed.
- New public registration is rejected while the owner can still log in and
  controlled invitations work.
- Mailpit SMTP remains internal; its UI requires its dedicated authentication.
- The agent account can access only its intended collection and cannot manage
  collections or read operator personal-vault items.
- Vaultwarden can recover using its external unlock material before a dependent
  service retrieves a key from it.
