# Keep a Linux host awake for remote work

Use this procedure only for a host that is intended to accept remote work while
unattended. A running remote-control service, SSH reachability, or user-manager
linger does not prove that the operating system will stay awake.

## Configure automatic suspend

Disable automatic suspend with the desktop environment's supported power
setting or centrally managed policy. On GNOME, check the AC and battery
inactivity actions:

```bash
gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type
gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type
```

For a host that must remain awake, these should read `nothing`. Keep screen
blanking and locking as separate settings if desired. Recheck the effective
values after importing settings or applying an OS image update.

A user service can hold a sleep inhibitor only if it successfully acquires the
lock in the unattended state. Linger keeps the user manager alive; it does not
prevent suspend or bypass authorization required to acquire an inhibitor. Check
the live inhibitor list instead of relying on a unit's enabled state.

## Hold a persistent system sleep inhibitor

When the host must stay awake without an active desktop session, use a separate
system unit to hold a blocking sleep inhibitor. The unit runs only
`systemd-inhibit` and `sleep` as root; keep Codex, Claude, and other remote
execution processes under their intended unprivileged accounts.

Create `/etc/systemd/system/remote-host-no-sleep.service`:

```ini
[Unit]
Description=Keep host awake for remote work
Documentation=man:systemd-inhibit(1)
Wants=systemd-logind.service
After=systemd-logind.service
StartLimitIntervalSec=10min
StartLimitBurst=3

[Service]
Type=simple
ExecStart=/usr/bin/systemd-inhibit --what=sleep --mode=block \
    --who=remote-workstation --why=remote-work \
    /usr/bin/sleep infinity
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

Use a short, single-token `--who` and `--why` value in the unit so systemd
passes each option as one argument. The start limit makes a persistent
configuration or authorization failure visible instead of producing an
unbounded restart loop.

Validate and enable the unit:

```bash
sudo systemd-analyze verify /etc/systemd/system/remote-host-no-sleep.service
sudo systemctl daemon-reload
sudo systemctl enable --now remote-host-no-sleep.service
```

The `block` inhibitor prevents the requested sleep operation without a time
limit; only privileged callers may override it. It does not prevent shutdown or
reboot. Do not mask `sleep.target` or related targets as a substitute. For a
laptop, separately review lid-close behavior: systemd-logind defaults to
ignoring high-level sleep inhibitors for lid-switch events. Configure that
policy only when a lid exists and the intended closed-lid behavior requires it.
A desktop needs no lid-switch override.

## Verify persistence and recover failures

Confirm both the systemd unit and the live lock:

```bash
sudo systemctl is-enabled remote-host-no-sleep.service
sudo systemctl is-active remote-host-no-sleep.service
sudo systemctl show remote-host-no-sleep.service \
  -p ActiveState -p UnitFileState -p MainPID -p ExecMainStatus -p WantedBy
systemd-inhibit --list --no-pager --what=sleep --mode=block
```

The inhibitor list must show a `sleep` lock in `block` mode held by the system
service. An enabled unit without a live lock is not success. If the service is
inactive or failed, inspect its unit status and narrowly scoped journal, correct
the authorization or command-argument error, then reset and start it:

```bash
sudo systemctl reset-failed remote-host-no-sleep.service
sudo systemctl daemon-reload
sudo systemctl start remote-host-no-sleep.service
```

After a planned reboot, repeat the unit and inhibitor checks and verify the
remote client can reach the host. Schedule that reboot after active work is
checkpointed; `enable` proves boot wiring, not that the host has passed a real
reboot. Record the effective desktop policy, live inhibitor, boot result, and
rollback path in the ignored local handoff.

To restore the prior sleep behavior, disable and remove only this unit, then
reload systemd:

```bash
sudo systemctl disable --now remote-host-no-sleep.service
sudo rm /etc/systemd/system/remote-host-no-sleep.service
sudo systemctl daemon-reload
```

See the official [`systemd-inhibit`](https://www.freedesktop.org/software/systemd/man/latest/systemd-inhibit.html)
and [`logind.conf`](https://www.freedesktop.org/software/systemd/man/latest/logind.conf.html)
manuals for inhibitor and lid-switch behavior.
