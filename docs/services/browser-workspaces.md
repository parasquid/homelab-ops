# Persistent browser workspaces

Use a dedicated Kasm Workspaces VM when people need an always-available Firefox
workspace and automation may later need isolated browser screenshots. Keep the
attended Firefox, any authenticated screenshot browser, and public one-shot
screenshot jobs in separate Kasm users or workspaces with distinct profile
storage.

## Decisions and consequences

- Use a dedicated VM so browser containers, downloaded files, browser state,
  and updates do not change an existing automation service. A modest VM usually
  supports one interactive browser session at a time; size CPU and memory from
  the selected Kasm workspace's resource limits and expected concurrency.
- Use a supported stable Kasm release and the vendor's documented installation
  path. Verify the downloaded installer against the matching publisher-provided
  checksum file, and compare with the release documentation when it publishes a
  digest. Stop if trusted publisher sources disagree; do not select whichever
  digest happens to match the download.
- Put Kasm configuration, container state, browser profiles, and any service
  credentials on a separate guest LUKS data disk. Keep the OS bootable while
  locked, but leave Docker, Kasm, and the reverse proxy stopped until an
  operator unlocks and mounts the data disk. A stolen, powered-off disk then
  needs the unlock material, while a compromised running VM remains within the
  VM's trust boundary.
- Use a tailnet-only HTTPS reverse proxy. The DNS record should be DNS-only and
  resolve to the VM's tailnet address. Bind the proxy only to that address and
  keep the Kasm backend reachable only from the local VM. Do not enable public
  ingress, a tunnel, or an additional remote-desktop listener unless a separate
  design explicitly requires it.
- Treat a persistent browser profile like an application credential store.
  Cookies, local storage, saved passwords, visited sites, and downloads may be
  present. Limit who can access the Kasm account and encrypted disk, and never
  mount an attended user's profile into an automation workspace.

## Profile and session choices

Kasm publishes the Firefox workspace image; select a tag compatible with the
installed Kasm release (for example, `kasmweb/firefox:1.19.0` with Kasm 1.19.0).
Kasm persistent profiles mount a user's browser home directory into the
workspace container.
Use a unique profile path for each Kasm user and workspace combination so
unrelated accounts cannot read or overwrite one another. Keep the profile
mount enabled for attended Firefox work that needs durable sign-ins. A Firefox
add-on installed in that profile can be retained with the rest of the profile,
but compatibility and operation still depend on the add-on and its
permissions; test the required add-on inside the selected Kasm image. Disable
the profile mount only for deliberately ephemeral jobs. A profile preserves
browser files such as cookies and local storage; it does not preserve a live
browser process, JavaScript heap, open form state, or unsaved page state after
the container is destroyed.

Configure the browser to restore its previous tabs on startup. After a
workspace is stopped or deleted, a new workspace can then recover saved
cookies, local storage, and restorable tab URLs from its mounted profile. A
restart still reloads pages and may require a site sign-in or confirmation.
Document the results for the selected browser image rather than promising that
every site's live session will survive.

Pausing a running Kasm session retains its processes and open tabs while the
VM remains powered on and the session remains allocated. Stopping or expiring
the session ends those processes. Rebooting the VM also ends every live
session; only profile files and browser startup settings remain for a later
workspace. Use Kasm's authenticated session-sharing feature only for a
trusted, intended audience. A session share grants access to the active
browser contents, so stop sharing when the attended task is complete.

Keep at least these identities separate:

| Workspace | Profile policy | Intended use |
| --- | --- | --- |
| Attended Firefox | Persistent, private to its human user | Interactive browsing, sign-ins, and approved Firefox add-ons |
| Authenticated screenshot browser | Optional separate persistent profile, private to an automation user | Sites that require a dedicated automation sign-in |
| Public one-shot screenshot | Ephemeral context by default | Pages that need no saved sign-in |

The screenshot workspace must never mount the attended profile. If a workflow
later needs an authenticated screenshot, give it a separately owned Kasm user
and profile and approve the credential path independently.

### Firefox capture add-ons

Firefox has a built-in full-page screenshot tool, and Kasm supports Firefox
managed policies through a workspace file mapping or a custom image. For a
purpose-built capture add-on, build and review the extension in its owning
application repository first. Firefox release builds require Mozilla signing;
after owner review, distribute a Mozilla-signed unlisted XPI from the local
workspace rather than publishing it as a public AMO listing or installing an
unsigned permanent add-on.

Use the Firefox `ExtensionSettings` policy in
`/etc/firefox/policies/policies.json` to force-install the reviewed extension by
its exact add-on ID. A local policy can reference a `file:///...` XPI path. Map
the policy and XPI into each new Kasm session with File Mapping, or build both
into a custom workspace image when the artifact or policy needs exceed File
Mapping's limits. Keep this capture add-on scoped to the attended Firefox
workspace. For each signed update, record its version and digest privately,
replace the local XPI, update the managed policy if its ID or path changes, and
start a new workspace to verify installation. See Kasm's [Firefox Managed
Policies guide](https://docs.kasm.com/docs/1.18.0/how-to/chrome_managed_policies)
and Mozilla's [Firefox ExtensionSettings policy
reference](https://mozilla.github.io/policy-templates/#extensionsettings) for
the supported configuration.

## Private access and installation outline

1. Select a free VM ID, a unique host and tailnet name, an unused DNS name, and
   storage with enough headroom for Kasm images and browser profile growth.
   Check the host listener, network, and DNS inventory before creating the VM.
2. Install a supported Debian cloud image after checking its digest against the
   official checksum manifest. Keep the OS on its own disk and attach a
   separately identified data disk for LUKS2.
3. Format only after verifying the guest disk's stable serial, expected size,
   VM attachment, and absence of existing signatures. Keep an automation key
   and an independent recovery passphrase/header backup outside the VM and
   repository. Do not store their values in service documentation.
4. Configure the remote unlock path. At boot, start only the OS, Tailscale, and
   administration access. After unlock, mount the encrypted data disk, then
   start Docker, Kasm, and the reverse proxy. Confirm that a locked reboot does
   not start the application stack.
5. Download the selected Kasm release and its matching publisher checksum
   artifact from official sources. Verify the exact archive digest before
   extracting or executing the installer. Follow the release's installation
   guide, including its documented reverse-proxy settings.
6. Configure Caddy with a DNS-01 certificate and the provider's token supplied
   through protected local configuration. Bind Caddy to the tailnet address;
   proxy to the Kasm HTTPS listener on loopback and configure Kasm's upstream
   proxy address as required by the release guide. Do not commit the provider
   token or a live hostname to this repository.
7. Create a Firefox workspace for attended browsing and separate Kasm users
   and workspaces for future screenshot work. Set per-workspace CPU/memory
   limits, persistent profile paths, session timeouts, and sharing permissions
   deliberately. Verify required Firefox add-ons against that image before
   treating them as part of the attended workflow.

## Future n8n screenshot integration

Kasm's Developer API can create a workspace session, report its status, and
return a screenshot. The documented public API routes include
`/api/public/request_kasm`, `/api/public/get_kasm_status`, and
`/api/public/get_kasm_screenshot`; confirm the request shape and permissions
against the installed release's [Developer API documentation](https://docs.kasm.com/docs/develop/reference/developer-api).
The documented minimum API key permissions for creating a session on behalf of
a user are `Users Auth Session` and `User`; assign the key to a dedicated
automation identity and avoid unrelated permissions. Keep API calls on the
private tailnet endpoint. Do not pass session-sharing URLs or human browser
credentials to n8n.

Use ephemeral screenshot sessions for public pages. If authenticated captures
become necessary, assign their own automation Kasm user and optionally enable
that user's separately persistent profile. Store any approved API credential
in the secret store and n8n credential storage, never in workflow JSON, logs,
or this repository. Do not issue or connect an API credential until the
target-site workflow and its account isolation are ready. Test session
creation, status polling, screenshot retrieval, cleanup, profile isolation,
and failure handling before enabling a production workflow.

## Acceptance checks

- The UI is reachable over HTTPS from a tailnet client and is unavailable from
  unintended LAN or public interfaces. Kasm's backend port is not exposed.
- A paused session retains its open tabs and running processes while the VM is
  up. Record what happens at the selected session timeout.
- For durable-profile testing, write a synthetic cookie and local-storage value
  on a controlled test origin, stop and delete the workspace, recreate it with
  the same profile path, and confirm both values are present. Remove test data
  afterward. Never use profile deletion as the persistence test.
- Restart a stopped workspace and confirm the browser restores its configured
  tabs. Reboot the VM and confirm live processes end, the encrypted data disk
  remains locked until remote unlock, and profile data remains available after
  the stack is started again.
- Confirm that the attended and screenshot users cannot read each other's
  profiles. If session sharing is enabled, verify that only authenticated
  intended users can join and that stopping sharing revokes access.
- Verify the reviewed Firefox capture add-on is present under `about:addons`,
  then capture a controlled long page and confirm the result covers the full
  page. Inspect that capture output and extension permissions before using it
  on real attended sites. Repeat after an XPI or Firefox image update.
- Before any n8n integration, exercise the Developer API with a dedicated
  non-production identity and verify that screenshot jobs cannot reach the
  attended profile or UI credentials.

## Updates and recovery

Follow the selected Kasm release's update and rollback instructions. Keep the
installer, version, checksum source, and verified digest in the ignored local
handoff so an operator can reproduce the install. Test updates with the
encrypted data mounted and check both UI login and a disposable browser
workspace before treating an update as healthy. A container-image rollback may
not undo changed application state; treat profiles and Kasm configuration as
user data. Restore them only through the site's approved recovery process.

If the data disk cannot be unlocked, leave Docker, Kasm, and Caddy stopped and
verify the disk identity before retrying. Do not initialize or reformat a disk
that might contain profiles or Kasm state. If the reverse proxy fails, check
tailnet binding, DNS-only resolution, certificate challenge permissions, Kasm
upstream proxy configuration, and the local backend listener without widening
the network exposure.
