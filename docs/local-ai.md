# Workstation-hosted local AI

This guide describes a reusable local-inference setup for an atomic desktop.
It uses a rootless Podman Quadlet to run Ollama while leaving the host image
managed by the workstation's OS project. It is a reference procedure, not a
record of any workstation's current state.

## Choose the host path and model service

Read the current [Bluefin AI guide](https://docs.projectbluefin.io/ai/) and
[image catalog](https://docs.projectbluefin.io/sv/images/) before changing an
atomic host. Bluefin documents its supported model tools and GPU path there;
do not add a separate driver or toolkit by habit. Use the OS project's
supported desktop driver/image path, and preserve a known-good deployment
before changing the booted image.

Choose Ollama when its model store, API, or client compatibility is required.
Bluefin also documents `llmman` and Docker Model Runner; compare those choices
before creating a second model service. Keep a single intended service bound to
port `11434`, and check for an existing Ollama process before starting this
one. A native service and a container must not race over the same port or model
directory.

This pattern is for a workstation where the NVIDIA GPU handles inference and
an integrated GPU drives the desktop. On a single-GPU system, omit the desktop
routing checks. Use a model that fits the available VRAM when full GPU
offload is desired; smaller VRAM budgets may require a smaller model or partial
CPU offload.

## Verify desktop and compute routing

Before starting a model, identify the GPU drivers and connected display
connectors. On a hybrid system, confirm the integrated GPU owns connected
outputs and is the desktop's default renderer:

```sh
lspci -nnk | rg -i 'vga|3d controller|kernel driver in use'
switcherooctl list

for status in /sys/class/drm/card[0-9]*-*/status; do
  [ -r "$status" ] || continue
  [ "$(cat "$status")" = connected ] || continue
  connector=${status%/status}
  card=${connector##*/}
  card=${card%%-*}
  printf '%s vendor=' "$connector"
  cat "/sys/class/drm/$card/device/vendor"
done

nvidia-smi --query-gpu=name,display_active --format=csv
```

Run `glxinfo -B` inside the actual logged-in desktop session when available;
check its OpenGL renderer rather than inferring the renderer from PCI device
order. A greeter check is useful before login, but verify again in the user
session. Do not launch the desktop with NVIDIA PRIME offload variables when the
integrated GPU is intended to render it.

NVIDIA CDI may inject `/dev/dri` nodes for the requested GPU as well as CUDA
devices. Their presence inside a container does not mean that GPU owns a
connected monitor. Check host connector ownership and the desktop renderer.
Keep X11 and Wayland sockets out of the model container; Ollama needs the
compute device, not access to the desktop session.

## Confirm rootless Podman and NVIDIA CDI

Use the OS project's supported NVIDIA path, then check the host before
creating the Quadlet:

```sh
podman info --format 'rootless={{.Host.Security.Rootless}}'
nvidia-smi
nvidia-ctk cdi list
```

Require rootless Podman, a working host driver, and a CDI entry for the
intended GPU. Select its CDI name from the live listing; do not assume index
`0` is the desired GPU when multiple devices are present. NVIDIA's toolkit
can generate and refresh CDI specifications; follow the platform's supported
refresh path after driver changes. Avoid enabling the legacy NVIDIA OCI hook
at the same time as native CDI injection.

## Define the Ollama Quadlet

Copy the [Ollama Quadlet example](../examples/ollama.container.example) to
`~/.config/containers/systemd/ollama.container` for the user who will run the
service. Replace the CDI index with the intended entry from
`nvidia-ctk cdi list`. Keep model data in a persistent user-owned directory.
Before reusing an existing Ollama directory, stop only the intended old
service and verify the path so the container does not create a second large
model store or overwrite unrelated data.

The example sets `SecurityLabelDisable=true`, which turns off SELinux label
separation for this container. NVIDIA's CDI example uses the same setting for
Podman. Keep the container dedicated, restrict its mounts, and bind the
unauthenticated Ollama API to loopback. If local policy does not allow disabling
label separation, use a narrowly scoped supported SELinux policy and verify
device access instead of weakening SELinux globally.

The persistent volume preserves downloaded models across container recreation.
`Pull=missing` uses the local image when it exists; it does not automatically
track later changes to the `latest` tag. Pin a release or digest when
repeatability matters.

## Start and verify the service

Use the [runbook's workstation Quadlet procedure](../RUNBOOK.md#workstation-local-rootless-quadlets)
for startup, user-manager persistence, updates, and removal.

Verify the API is responding and the listener is loopback-only:

```sh
curl -fsS http://127.0.0.1:11434/api/version
ss -lnt '( sport = :11434 )'
podman exec ollama ollama list
```

Run a short prompt with a model sized for the selected GPU, then inspect
`podman exec ollama ollama ps`, `nvidia-smi`, and the service journal. Confirm
Ollama reports GPU processing and that its runner appears as an NVIDIA compute
process. `ollama ps` can report mixed CPU/GPU processing when the model or
context does not fit fully in VRAM. A successful HTTP response alone does not
prove GPU acceleration.

For a hybrid desktop, repeat `switcherooctl list`, the connected-connector
check, and the renderer check in the logged-in user session. Confirm connected
outputs still belong to the integrated GPU and normal desktop rendering still
uses it.

## Tailnet access for a remote client

When a service such as n8n on another tailnet node must call Ollama, use the
[runbook's Tailscale Serve
procedure](../RUNBOOK.md#tailnet-access-to-a-workstation-api).
Keep Ollama bound to `127.0.0.1:11434`; Serve can publish the same port on the
Tailscale interface:

```sh
sudo tailscale serve --bg --http=11434 http://127.0.0.1:11434
sudo tailscale serve status
sudo tailscale funnel status
ss -lnt '( sport = :11434 )'
```

From the client node, replace this reserved example name with the workstation's
MagicDNS name and verify the API:

```sh
WORKSTATION_MAGICDNS=ollama-host.tailnet.example
curl -fsS "http://$WORKSTATION_MAGICDNS:11434/api/version"
```

The Ollama API has no authentication, so access follows the tailnet's ACL
policy. Tailscale encrypts traffic between tailnet nodes. Use this HTTP route
for server-to-server consumers; Tailscale notes that HTTP web services can
face DNS-rebinding risks when browsers visit untrusted sites. Tailscale HTTPS
certificates publish machine names in public Certificate Transparency logs,
so account for that disclosure before enabling HTTPS.

Remove only this Serve route with `sudo tailscale serve --bg --http=11434 off`.

## Maintenance and recovery

Use the [runbook's workstation Quadlet procedure](../RUNBOOK.md#workstation-local-rootless-quadlets)
for service lifecycle and image updates. For GPU failures, check
`nvidia-ctk cdi list`, the platform's driver/toolkit refresh status, the Ollama
service journal, `ollama ps`, and `nvidia-smi`. Do not hand-edit generated CDI
files. After changes, recheck the API, listener binding, GPU allocation, and
desktop renderer.

Decide whether the model directory needs backup. Models can often be
downloaded again, but custom files and the time/network cost of reacquiring
large models may make a local backup useful. Record the selected backup or
deferral in the ignored local inventory and handoff.

## References

- [Bluefin AI and Machine Learning](https://docs.projectbluefin.io/ai/)
- [Bluefin images](https://docs.projectbluefin.io/sv/images/)
- [Ollama Quadlet example](../examples/ollama.container.example)
- [Ollama container deployment](https://docs.ollama.com/docker)
- [NVIDIA Container Toolkit CDI support](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/cdi-support.html)
- [Podman Quadlet systemd units](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [Podman Quadlet container options](https://docs.podman.io/en/latest/markdown/podman-container.unit.5.html)
- [Tailscale Serve CLI](https://tailscale.com/docs/reference/tailscale-cli/serve)
- [Tailscale HTTPS certificate visibility](https://tailscale.com/docs/how-to/set-up-https-certificates)
