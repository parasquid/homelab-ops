# Persistent Firefox browser workspaces

Use a dedicated VM for interactive browser work so browser state, downloads, and
updates do not change an automation service. For one attended Firefox session,
the LinuxServer Firefox image provides Firefox in a browser-accessible KasmVNC
desktop. Kasm Workspaces is an optional choice when its multi-user workspace
management, session sharing, or Developer API is required.

## Single-user Firefox workspace

Pin a supported LinuxServer Firefox version and its verified image digest. Do
not deploy a moving `latest` tag in production. Check the selected
architecture and image metadata against LinuxServer's published image before
updating.

The web desktop is served on container port 3000 over HTTP. The image also has
a separate HTTPS port 3001. Publish only port 3000 on VM loopback, and keep
3001 unpublished. Put the VM behind a tailnet-only HTTPS proxy after the VM has
joined the intended tailnet. The proxy must bind to the VM's tailnet address;
do not create a public DNS record, forward a router port, or expose the GUI
directly to the LAN.

Enable the image's Basic Auth with a dedicated username and a strong password
provided through a protected file using LinuxServer's `FILE__` environment
support. Keep the file on the encrypted data filesystem with owner-only
permissions. Do not store the password in Compose, container labels, shell
arguments, repository files, or logs. Basic Auth is an application gate; keep
the network path private as well.

A minimal Compose shape is:

```yaml
services:
  firefox-attended:
    image: lscr.io/linuxserver/firefox:<version>@sha256:<verified-digest>
    environment:
      PUID: "1000"
      PGID: "1000"
      TZ: Etc/UTC
      CUSTOM_USER: attended
      FILE__PASSWORD: /run/secrets/firefox_password
    volumes:
      - <encrypted-data-path>/firefox/attended/config:/config
      - <encrypted-data-path>/secrets/firefox_password:/run/secrets/firefox_password:ro
    ports:
      - "127.0.0.1:3000:3000"
    shm_size: 1gb
    restart: unless-stopped
```

Replace each angle-bracket value before use. Store the Compose file and
password file on the encrypted filesystem. Set the host owner of the `/config`
directory to the configured PUID/PGID. Keep the container's `/config` bind
mounted there so replacing the container does not replace the browser profile.
The profile contains cookies, local storage, saved credentials, history,
downloads, and possibly other private browser data.

Keep one private profile path per attended user. Never mount an attended
profile into n8n or a screenshot container. If more than one attended user is
needed, give each user a separate container, credential, and `/config` path.

## Profile and session behavior

Firefox profile files on the persistent `/config` mount survive container
replacement. This includes cookies and local storage after Firefox has flushed
them to disk. Do not treat container persistence as a guarantee that every
website will preserve a live login: sites can expire sessions or require a new
sign-in.

Set Firefox's `browser.startup.page` preference to `3` in the persistent
profile so a normal browser start restores the previous session's tabs. Set
`browser.sessionstore.resume_from_crash` to `true` so Firefox can offer
recovery after an unexpected close. Keep the profile on `/config`, and verify
that the chosen image reads these preferences. A restored tab reloads its URL;
the page may request a fresh login or confirmation.

Stopping the browser or VM ends running processes, JavaScript state, and
unsaved form contents. A browser restart can restore saved tab URLs from the
profile when session restore is configured. A paused browser process keeps its
open tabs only while the container and VM remain running. Test and document
these behaviors for the selected Firefox image. Do not claim tab recovery
across a VM reboot until it has been tested.

## Separate screenshot identities

Keep future screenshot work separate from the attended account and profile:

| Purpose | Profile policy | Access |
| --- | --- | --- |
| Attended browsing | Persistent profile, private to its human user | Private browser UI |
| Authenticated automation screenshots | Optional separate persistent profile | Dedicated automation account and credential |
| Public one-shot screenshot jobs | Ephemeral profile or context | No saved sign-in |

Create a separate Firefox container and `/config` path for authenticated
automation. Use an ephemeral context for public pages that do not need saved
sign-in. Never give screenshot automation access to the attended user's cookies
or profile directory.

The LinuxServer Firefox container provides a browser UI; it does not provide
Kasm Workspaces' Developer API for creating sessions and retrieving their
screenshots. Keep future n8n capture integration on a separate authenticated
route, such as a reviewed capture extension or an isolated automation browser.
Do not issue an API credential or connect n8n until the target workflow,
account isolation, and request path are ready. Keep human browser credentials
out of n8n.

## Firefox capture add-on

Build and review the extension in its owning application repository first.
Firefox release builds require Mozilla signing. After review, distribute a
Mozilla-signed unlisted XPI from the local browser VM instead of publishing a
public AMO listing or installing an unsigned permanent add-on.

Firefox managed policy uses
`/etc/firefox/policies/policies.json` and the `ExtensionSettings`
policy to force-install an extension by its exact add-on ID. Mount the policy
and signed XPI read-only into the container, or add them to a reviewed custom
image. A local policy can reference a `file:///` XPI path. For LinuxServer
images, a custom initialization script can place the policy and XPI before
Firefox starts. Keep the extension scoped to the attended profile unless a
separate automation profile is explicitly designed to use it. Record the XPI
version and digest privately; verify installation and full-page capture after
each Firefox or extension update.

See LinuxServer's [Firefox image
guide](https://docs.linuxserver.io/images/docker-firefox/),
[container customization guide](https://docs.linuxserver.io/selkies/developer-guide/customization/),
and [environment variables from
files](https://docs.linuxserver.io/images/docker-nginx/). See Mozilla's
[Firefox ExtensionSettings policy
reference](https://mozilla.github.io/policy-templates/#extensionsettings).

## Installation outline

1. Check for a free VM ID, unused hostname and tailnet name, DNS conflicts,
   storage capacity, and host listener conflicts. Keep the browser VM separate
   from n8n.
2. Install an official Debian image after verifying its checksum. Provision
   new virtual disks sparsely unless the service profile explicitly selects
   thick allocation. Use ext4 inside the guest regardless of the host storage
   pool. For encrypted data, create ext4 inside LUKS on the data disk.
3. Follow the general LUKS procedure in `RUNBOOK.md` section 6. Install
   `cryptsetup` from the guest distribution's signed official repository
   before formatting. Check the exact disk serial, size, VM attachment, and
   absence of existing signatures immediately before formatting. Keep the
   automation key, independent recovery passphrase, and LUKS header copy
   outside the VM and repository. Do not zero, random-fill, or discard an
   entire sparse disk.
4. Put the container image, Compose file, Firefox `/config`, and Basic Auth
   secret on the unlocked encrypted filesystem. Start one attended browser
   container and publish only `127.0.0.1:3000:3000`. Before adding any proxy,
   inspect the generated container and host listener configuration. Check
   unauthenticated and authenticated responses separately.
5. After local health and authentication checks pass, join the VM to its
   authorized tailnet with Tailscale SSH disabled if OpenSSH is the intended
   administration route. Configure HTTPS ingress only on the VM's tailnet
   address. Keep the DNS record DNS-only and pointed to the tailnet address.
6. If a later design needs multi-user workspaces, active session sharing, or
   Kasm's Developer API, evaluate Kasm Workspaces separately. Use its matching
   official installer and checksum, pin the web UI to loopback behind the
   tailnet proxy, and use unique persistent profiles per user and workspace.
   A Kasm screenshot API key belongs to a dedicated automation identity and
   must not grant access to the attended user's browser.

## Acceptance checks

- The browser UI returns an authentication challenge without credentials and
  loads only with the intended Basic Auth credential.
- The VM has only a loopback listener for port 3000. Port 3001, Kasm ports,
  and remote-desktop ports are not published. Verify this from both the Compose
  configuration and the VM's listening sockets.
- The tailnet proxy is reachable from an authorized client and unavailable
  from unintended LAN or public interfaces. Do not add DNS or proxy ingress
  before local authentication and app health checks pass.
- On a controlled synthetic origin, write a test cookie and local-storage
  value, replace the browser container while retaining the same `/config`
  mount, and confirm both values remain. Remove the test origin data and
  disposable profile afterward. Do not use the attended profile's sign-in as
  test data.
- Open a controlled tab, close Firefox cleanly, restart it with session restore
  enabled, and confirm the tab URL reopens. Separately verify this after a VM
  reboot before documenting reboot recovery as tested. Unsaved forms and page
  memory do not survive either restart.
- Confirm the screenshot identity cannot read the attended profile. If session
  sharing or a capture extension is enabled, verify its permissions and
  intended audience before using real sites.

## Updates and recovery

Keep the exact image tag and digest, Compose configuration, and recovery steps
in the ignored local handoff. Update by pinning a reviewed image version and
digest, then recreate only the browser service. Check UI authentication,
listener bindings, Firefox version, profile access, and screenshot extension
after an update. Test updates with the encrypted filesystem mounted. Treat the
profile as user data; a container rollback does not roll back cookies or
Firefox state.

If the data disk cannot be unlocked, leave Docker and the browser container
stopped and verify disk identity before retrying. Do not initialize or reformat
a disk that may contain profiles. If the reverse proxy fails, check tailnet
binding, DNS-only resolution, certificate challenge permissions, websocket
proxying, and the local backend listener without widening network exposure.

Kasm Workspaces persistent profiles, sharing, and Developer API are documented
in the [Kasm 1.19 profile
guide](https://docs.kasm.com/docs/how-to/data-storage/persistent-profiles/),
[reverse-proxy guide](https://docs.kasm.com/docs/1.19.0/how-to/networking/reverse-proxy),
and [Developer API reference](https://docs.kasm.com/docs/develop/reference/developer-api).
