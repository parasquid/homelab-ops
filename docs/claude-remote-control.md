# Claude Code Remote Control on immutable Linux

This guide describes a reusable, per-user setup that makes a Linux workstation
a Claude Code Remote Control host: a machine that appears in the Claude app's
host list and accepts new sessions started from the app or the web. It keeps
the service in the user systemd manager and leaves the operating-system image
unchanged. Replace every angle-bracket placeholder with a local value; do not
copy deployment-specific identifiers into tracked documentation.

The official product reference is
[Claude Code Remote Control](https://code.claude.com/docs/en/remote-control).
The command surface changes between releases. Verify the official reference
and the installed CLI help before changing a service, and do not infer that a
host is registered merely because its unit is active.

## Choose the server mode

The CLI offers two different Remote Control entry points:

| Command | What it registers | Use it for |
| --- | --- | --- |
| `claude remote-control` | The machine and working directory, as a host | A host that should appear in the app and accept new sessions |
| `claude --remote-control` | One interactive session | Reaching a single session you started at the terminal |

The two differ by two dashes, but only the `remote-control` subcommand
registers a host. A supervised service that runs the `--remote-control` flag
stays healthy in systemd and keeps one reachable session, yet the machine
never appears in the app's host list. Use the subcommand for an always-on host.

## Architecture

```text
Claude app or web
        |
        v
Anthropic API  <-- outbound HTTPS: host registration and work polling
        ^
        |
claude remote-control (server) --spawns--> session workers in <workspace>
        |
        +-- detached tmux session (attachable status screen)
        +-- user systemd unit (restart and boot)
```

The server makes outbound HTTPS requests only: it registers the host and then
polls for work. It does not need an inbound port, proxy, tunnel, or firewall
opening. Verify that with a listener check after the first start rather than
assuming it.

## Prerequisites and layout

Install the CLI through one owner, either a package manager such as a Homebrew
cask or the official installer, and keep a stable user-facing path such as
`%h/.local/bin/claude`. On an immutable host, do not layer an OS package solely
to obtain the CLI. If the stable path is a symlink into a package-managed
directory, update through that package manager rather than replacing files.

Complete these one-time steps as the service user before creating the unit:

1. Sign in interactively on this host. Each host needs its own sign-in; do not
   copy a credential cache from another machine, because sharing one login
   between machines can invalidate the other machine's session.
2. Run `claude` once in `<workspace>` and accept the workspace trust prompt.
   Without that, `claude remote-control` exits immediately with a
   "Workspace not trusted" error, and the service restarts in a loop.
3. Confirm the command surface without starting a server:

```bash
command -v claude
claude --version
claude remote-control --help
```

Keep the Claude configuration directory (`%h/.claude` by default) local to
each host. The server writes machine-specific runtime state there, such as
bridge pointers and spawned-session directories. If two hosts share that
directory through file sync, each host sees the other's runtime state, and a
migrated copy carries the source host's state with it. Start a migrated host
from a fresh sign-in and do not reuse the source host's runtime registrations.

Write debug logs to host-local disk, for example `%h/.cache/claude-rc-debug`,
with mode `0700` on the directory. Avoid `/tmp` on hosts where it is a RAM-backed
tmpfs, and avoid any synced directory, because the logs contain session
identifiers, paths, and prompts.

## User service

Create `%h/.config/systemd/user/claude-remote-control.service`:

```ini
[Unit]
Description=Claude Code Remote Control
Wants=network-online.target
After=network-online.target

[Service]
Type=forking
ExecStartPre=/usr/bin/test -x %h/.local/bin/claude
ExecStartPre=/usr/bin/test -d %h/<workspace>
ExecStart=/usr/bin/tmux -f /dev/null -L claude-rc new-session -d -s rc -c %h/<workspace> /bin/sh -c 'umask 077; mkdir -p %h/.cache/claude-rc-debug; exec %h/.local/bin/claude remote-control --spawn=same-dir --name <host-label> --debug-file %h/.cache/claude-rc-debug/rc-$$(date +%%Y%%m%%d-%%H%%M%%S).log'
ExecStop=-/usr/bin/tmux -L claude-rc send-keys -t rc C-c
ExecStop=-/bin/sh -c 'for i in $(seq 30); do /usr/bin/tmux -L claude-rc has-session -t rc 2>/dev/null || exit 0; sleep 1; done; /usr/bin/tmux -L claude-rc kill-server'
TimeoutStartSec=60
TimeoutStopSec=60
Restart=always
RestartSec=15

[Install]
WantedBy=default.target
```

Each choice has a reason:

- **Server mode with a name.** `remote-control --name <host-label>` registers
  the host under a label you will recognize in the app. `--spawn=same-dir`
  starts new sessions in `<workspace>`; use `worktree` instead when concurrent
  sessions must not share one working tree.
- **Detached tmux.** The server draws a status screen with its capacity and a
  QR code for the mobile app. Running it in a private tmux server (`-L
  claude-rc`, with `-f /dev/null` so a personal tmux configuration cannot
  change its behavior) lets an operator attach to that screen and lets the
  stop command send the server's own graceful-shutdown key.
- **`Type=forking`.** `tmux new-session -d` returns once the tmux server is
  running. systemd then tracks the tmux server, which exits when the Claude
  process exits, so a dead server ends the unit.
- **`Restart=always` with `RestartSec=15`.** A start can fail within about a
  second during host registration, and repeated attempts after an upgrade can
  fail several times before one holds. `on-failure` is not enough when a
  wrapper can exit cleanly; `always` retries every exit. A deliberate
  `systemctl --user stop` does not trigger a restart.
- **Graceful stop.** `C-c` is the server's own shutdown key. It ends the
  server cleanly and keeps the host registration so a later start can
  reconnect. The second stop command waits up to 30 seconds and then removes
  the tmux server, so a hung process cannot block shutdown.
- **One debug log per start.** A fixed log path is overwritten by the start
  that finally succeeds, which erases the evidence of the failed attempts. A
  timestamped file per start keeps each attempt. In a unit file, `$$` and `%%`
  are systemd escapes for a literal `$` and `%`, and `umask 077` keeps the logs
  owner-only.

If the sessions need a separate credential-provider user service, for example
for MCP clients, declare both `Requires=` and `After=` on that provider and give
the provider a bounded readiness check. `After=` alone orders startup but does
not stop the host when the provider fails; `Requires=` alone does not wait for
it.

Enable linger so the user manager runs at boot without a login, then enable
the unit:

```bash
loginctl enable-linger "$USER"
systemctl --user daemon-reload
systemctl --user enable --now claude-remote-control.service
```

Linger changes the user manager's lifecycle. It does not grant root access and
does not make the service a system unit.

## Verification

Check the unit, its stability, and the registration it produced:

```bash
systemctl --user is-enabled claude-remote-control.service
systemctl --user show claude-remote-control.service \
  -p ActiveState -p Type -p InvocationID -p NRestarts
loginctl show-user "$USER" -p Linger
readlink -f "$(command -v claude)"
latest=$(ls -t "$HOME/.cache/claude-rc-debug"/rc-*.log | head -1)
grep -E 'environments/bridge -> [0-9]+' "$latest"
```

Acceptance requires all of the following:

- The newest debug log contains a `POST /v1/environments/bridge -> 200` line.
  A log that ends right after the `POST /v1/environments/bridge` request line,
  with no response line, records a failed registration attempt.
- The same `InvocationID` is reported for at least 20 seconds. `is-active` alone
  is true for most of each restart window during a restart loop, so it cannot
  tell a held start from a loop.
- `<host-label>` appears in the Claude app's host list, and a session started
  there runs in `<workspace>`.
- `ss -ltnp` shows no listener owned by the Claude process.

To see the status screen without risking a stray keystroke, attach read-only
with `tmux -L claude-rc attach -r -t rc` and detach with the tmux prefix and
`d`. Read only the registration lines from a debug log. Do not copy a whole log
into a ticket or chat; it contains prompts and session identifiers.

## Updates and recovery

A restart ends every live Remote Control session on the host. Update through
the package manager or installer that owns the CLI, and only when the host is
idle:

```bash
systemctl --user stop claude-remote-control.service
# Update through the mechanism that owns this installation.
rm -f "$HOME/.claude/projects/<encoded-workspace>/bridge-pointer.json"
systemctl --user start claude-remote-control.service
claude --version
```

`<encoded-workspace>` is the workspace's absolute path with each `/` replaced
by `-`. The server records its last session in `bridge-pointer.json`. After a
service stop the session is marked inactive, but the next start tries to
re-adopt it. The child then exits with `Epoch mismatch (409,
reason=session_not_active)`, and the server shows Ready with zero usable
capacity. Removing the pointer while the service is stopped makes the next
start create a fresh session.

After the start, wait for the same `InvocationID` to hold for at least 20
seconds, as in the verification above, before treating the update as done.
Keep the previous release available until the new one passes.

An optional daily systemd timer can automate this. Make the update script:

- Check whether the owning package is outdated and exit if it is not.
- Defer when more than one session worker process is running, because each
  live conversation is one worker and the server pre-creates one on start.
- Defer when any session transcript in the workspace's project directory has
  a conversation entry newer than an idle window. Judge by the newest entry's
  timestamp, not the file modification time: the server rewrites its bridge
  pointer on a periodic housekeeping tick, which bumps modification times on
  an idle host.
- Stop the unit, remove the bridge pointer, upgrade, start the unit, then poll
  for a held `InvocationID` within a deadline, and log a warning if none holds.
- Prune debug logs older than a retention period.

If the unit is active but the host is missing from the app, check `ExecStart`
for the `--remote-control` flag before anything else.

## Security boundaries

- Run the service as the intended unprivileged user. Do not add `sudo` or a
  system unit to make Remote Control start at boot.
- Anyone who can use the Claude account that registered the host can start
  sessions on it. Those sessions run as the service user in `<workspace>`
  with the configured permission mode. Choose `--permission-mode` deliberately,
  and do not use a mode that skips permission prompts on a host that holds
  credentials you would not hand to that account.
- Keep credentials, MCP configuration, and tokens out of the unit and its
  command line. The CLI keeps its sign-in in its own credential store.
- Keep the debug log directory owner-only and out of synced folders, Git, and
  support output. Treat the logs as sensitive even when the CLI redacts
  registration secrets in them.
- Linger keeps the user manager available. It is not an authentication method.

## Troubleshooting checklist

| Symptom | Focused checks |
| --- | --- |
| Unit active, host missing from the app | `ExecStart` runs `claude --remote-control` instead of `claude remote-control`. Switch to the subcommand. |
| Start dies within about a second; `NRestarts` climbs | Read the newest debug logs. A log ending at the registration request with an empty `Error:` is a failed registration; `Restart=always` retries it. If no start holds within a few minutes, check sign-in and outbound HTTPS. |
| Exits immediately with "Workspace not trusted" | Run `claude` once in `<workspace>` and accept the trust prompt. |
| Ready, but zero usable capacity after a restart | The child hit `Epoch mismatch (409, reason=session_not_active)`. Stop the unit, remove `bridge-pointer.json`, and start it again. |
| Restart loop after an upgrade | Wait for a held `InvocationID` before judging the upgrade; if none holds within the deadline, compare the new release's help and the official reference. |
| Unit absent after reboot | Check `loginctl show-user "$USER" -p Linger` and the unit's `default.target.wants` link. |
