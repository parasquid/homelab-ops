# Codex Remote Control on immutable Linux

This guide describes a reusable, per-user setup for the standalone Codex CLI
on an immutable or image-based Linux host. It keeps the service in the user
systemd manager and leaves the operating-system image unchanged. Replace every
angle-bracket placeholder with a local value; do not copy deployment-specific
identifiers into tracked documentation.

The official product references are [Codex remote connections](https://developers.openai.com/codex/remote-connections)
and the [Codex app server](https://developers.openai.com/codex/app-server).
The `remote-control` command is version-sensitive: some standalone releases
label it experimental, and the literal command is not currently described in
the public reference. Verify the local CLI help before changing a service and
prefer behavior confirmed on the installed release. Do not infer that pairing
is active merely because the service is enabled.

## Architecture

```text
remote Codex client
        |
        v
Codex remote-control command -> user app-server daemon
        |                         |
        |                         +-- user control socket and local log
        +-- user systemd unit
```

The unit is a convenience boundary, not a new network proxy. The remote client
path, listener address, and authentication mechanism remain properties of the
installed Codex release and the host network policy. Keep databases, web
proxies, tunnels, and containers out of this setup unless a separate design
explicitly requires them.

## Prerequisites and layout

Install the standalone Codex CLI using the official distribution instructions
and keep its executable in a user-owned writable location such as
`%h/.local/bin`. On an immutable host, do not install an unrelated OS package
solely to obtain the CLI. A stable user-facing path may resolve through a
release-managed directory, for example:

```text
%h/.local/bin/codex -> %h/.codex/packages/standalone/current/bin/codex
```

The app-server state is normally under `%h/.codex`. Protect the state and
control directories with mode `0700`; protect sockets and logs so only the
owning user can access them. Follow the installed release's documented modes
when they differ, and never publish the contents of a log or configuration
file.

Before creating the unit, verify the executable and its command surface without
starting a daemon:

```bash
command -v codex
codex --version
codex remote-control --help
```

If the help does not expose the expected `start` and `stop` operations, stop
and consult the release-specific documentation. A `pair` operation, when
present, creates a short-lived pairing artifact; run it only as an intentional
operator action and record its result outside the repository.

If the installed app-server release requires a remote-control setting, use its
supported configuration path and verify that the setting is the only intended
change. Do not copy a global `config.toml`, MCP endpoint, token, or session
data into the service unit.

## User service

Create `%h/.config/systemd/user/codex-remote-control.service` with a user-owned
editor. This template uses the systemd `%h` specifier so it does not embed a
username or host path:

```ini
[Unit]
Description=Codex Remote Control
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=%h/.local/bin/codex remote-control start
ExecStop=%h/.local/bin/codex remote-control stop
TimeoutStartSec=60
TimeoutStopSec=30
Restart=on-failure
RestartSec=15

[Install]
WantedBy=default.target
```

This `oneshot` unit records whether the start command succeeded. With
`RemainAfterExit=yes`, systemd can report it as active after that command exits;
`Restart=on-failure` does not supervise the separate app-server daemon. Check
that the control socket accepts a connection before treating the daemon as
available. A working local socket still does not prove that a remote client is
paired.

Use an absolute user-owned executable path. Do not rely on a shell, `~`, or a
mutable interactive `PATH` in `ExecStart`. If the release's official installer
uses another path, substitute that path and document the resolver locally.

Enable linger when the service must be managed by the user manager after logout
and across boot, then enable the unit:

```bash
loginctl enable-linger "$USER"
systemctl --user daemon-reload
systemctl --user enable --now codex-remote-control.service
```

`enable-linger` changes the host's user-manager lifecycle. It does not grant
root access and does not make the service a system unit.

## Verification

Check the unit, user manager, executable resolver, and local control state:

```bash
systemctl --user is-enabled codex-remote-control.service
systemctl --user is-active codex-remote-control.service
systemctl --user show codex-remote-control.service \
  -p ActiveState -p Type -p RemainAfterExit -p MainPID -p ExecMainStatus
loginctl show-user "$USER" -p Linger
readlink -f "$(command -v codex)"
test -S "$HOME/.codex/app-server-control/app-server-control.sock"
stat -c '%A %n' "$HOME/.codex/app-server-control" \
  "$HOME/.codex/app-server-control/app-server-control.sock"
python3 - <<'PY'
from pathlib import Path
import socket

path = Path.home() / '.codex/app-server-control/app-server-control.sock'
with socket.socket(socket.AF_UNIX) as connection:
    connection.settimeout(1)
    connection.connect(str(path))
print('Control socket accepts connections')
PY
```

The socket check sends no application data and fails if the daemon is not
accepting local connections. Inspect narrowly scoped user-journal entries only
when needed; redact or avoid any line that could contain a token, pairing code,
prompt, request, or path-derived secret. Do not treat a running unit as proof
that a remote client is paired or that a host-wide firewall permits or denies
a path.
Listener and firewall checks must be performed in the appropriate host
namespace with separate authorization.

## Updates and recovery

Use the standalone installer's supported update path. Before switching a
release, record the current version, keep the previous release available, and
verify that the stable user-facing path resolves to the intended executable.
Then restart and repeat the focused checks:

```bash
systemctl --user stop codex-remote-control.service
# Update through the official standalone release mechanism.
systemctl --user daemon-reload
systemctl --user start codex-remote-control.service
codex --version
systemctl --user show codex-remote-control.service \
  -p ActiveState -p ExecMainStatus
```

If the unit is active but the socket check fails, checkpoint any active task,
then restart the user unit and repeat the socket check. Restarting disconnects
remote-control tasks. If the unit fails, inspect its exit status and a small,
redacted journal slice; do not read or copy logs into a ticket. Confirm the
executable still exists, the user manager is running, and linger remains
enabled. After correcting the unit or release path, use `daemon-reload`,
`reset-failed`, and a controlled
start. Preserve the old release until the new one passes its checks. Do not
delete a socket, lock, package, or log based only on its name; stop the service,
verify the owning user and the absence of a running process, then remove only a
known stale runtime artifact if the release documentation calls for it.

If the host image is updated, treat that as a separate immutable-host change.
Recheck the user CLI resolver, linger, unit enablement, app-server state modes,
and the intended remote connection after the reboot.

## Security boundaries

- Run the service as the intended unprivileged user. Never add `sudo` or a
  privileged system service just to make remote control start at boot.
- Keep the global Codex configuration, app-server settings, control socket,
  pairing artifacts, and logs out of Git and out of support output.
- Do not place access tokens, pairing codes, credentials, or MCP configuration
  in the unit, command arguments, shell history, or tracked files.
- Linger keeps the user manager available; it is not an authentication method.
- Verify listeners and firewall policy separately. SSH, Tailscale, a reverse
  proxy, a tunnel, and public ingress are not implied by this setup.
- The unit retries failed start commands within the timeouts above; it does not
  restart a daemon that dies after a successful start. Investigate repeated
  failures rather than looping through unverified upgrades.

## Troubleshooting checklist

| Symptom | Focused checks |
| --- | --- |
| Unit is not enabled | Confirm the user manager, run `daemon-reload`, then enable the exact unit. |
| Unit starts then exits | Check `Type=oneshot`, `RemainAfterExit=yes`, the executable resolver, and the release's `remote-control` help. |
| Start times out | Confirm network readiness, the user app-server state directory, and a single non-stale control socket. |
| Restart loop | Stop the unit, preserve the old release, inspect a redacted status/journal slice, and fix the release or unit path. |
| Remote client cannot connect | Verify the local daemon and pairing state first; separately verify the documented client path and host network policy. |
| Behavior changed after an update | Compare the installed release help and official references; the experimental command surface may have changed. |
