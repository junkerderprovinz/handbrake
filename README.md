<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/junkerderprovinz/handbrake/main/.github/assets/handbrake-banner-dark.png">
    <img src="https://raw.githubusercontent.com/junkerderprovinz/handbrake/main/.github/assets/handbrake-banner.png" alt="HandBrake for Unraid" width="100%">
  </picture>
</p>

<p align="center">
  <a href="https://github.com/junkerderprovinz/handbrake/actions/workflows/build.yml"><img src="https://img.shields.io/github/actions/workflow/status/junkerderprovinz/handbrake/build.yml?branch=main&label=Build&style=for-the-badge&logo=githubactions&logoColor=white" alt="Build" height="36"></a>&nbsp;
  <a href="https://github.com/junkerderprovinz/handbrake/actions/workflows/lint.yml"><img src="https://img.shields.io/github/actions/workflow/status/junkerderprovinz/handbrake/lint.yml?branch=main&label=Lint&style=for-the-badge&logo=githubactions&logoColor=white" alt="Lint" height="36"></a>&nbsp;
  <a href="https://hub.docker.com/r/junkerderprovinz/handbrake"><img src="https://img.shields.io/docker/pulls/junkerderprovinz/handbrake?style=for-the-badge&logo=docker&logoColor=white&label=Pulls&color=1d99f3" alt="Docker Pulls" height="36"></a>&nbsp;
  <a href="https://hub.docker.com/r/junkerderprovinz/handbrake"><img src="https://img.shields.io/docker/image-size/junkerderprovinz/handbrake/latest?style=for-the-badge&logo=docker&logoColor=white&label=Size&color=1d99f3" alt="Image Size" height="36"></a>&nbsp;
  <a href="https://github.com/junkerderprovinz/handbrake/pkgs/container/handbrake"><img src="https://img.shields.io/badge/Arch-amd64%20%7C%20arm64-success?style=for-the-badge&logo=linux&logoColor=white" alt="Arch" height="36"></a>&nbsp;
  <a href="https://github.com/selkies-project/selkies"><img src="https://img.shields.io/badge/Web-Selkies-3daee9?style=for-the-badge&logo=googlechrome&logoColor=white" alt="Selkies" height="36"></a>&nbsp;
  <a href="https://unraid.net"><img src="https://img.shields.io/badge/Unraid-Template-f15a2c?style=for-the-badge&logo=unraid&logoColor=white" alt="Unraid" height="36"></a>&nbsp;
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-AGPL--3.0-blue?style=for-the-badge&logo=gnu&logoColor=white" alt="License: AGPL-3.0" height="36"></a>
</p>

<br>

<p align="center">
A modern, plug-and-play Docker image for <b>HandBrake</b> on Unraid. The full
transcoder GUI in your browser via Selkies, <b>dark by default</b> using
HandBrake's own native GTK dark mode, plus a <b>watch-folder converter</b> that
transcodes anything you drop into <code>/watch</code> without opening the UI at
all. Everything is configurable from the Unraid template, no SSH or config-file
editing required.
</p>

<br>

<p align="center">A solo, free-time project. Bugs and ideas via <a href="https://github.com/junkerderprovinz/handbrake/issues">GitHub issues</a>; if it's useful to you, a coffee is always welcome.</p>

<p align="center">
  <a href="https://buymeacoffee.com/junkerderprovinz">
    <img src=".github/assets/button-buy-me-a-coffee.svg" alt="Buy me a coffee" width="220">
  </a>
</p>

<br>

## Table of Contents

1. [Overview](#1-overview)
2. [Screenshots](#2-screenshots)
3. [Quick Start](#3-quick-start)
4. [Volumes and Ports](#4-volumes-and-ports)
5. [Configuration](#5-configuration)
6. [Automated Watch-Folder Conversion](#6-automated-watch-folder-conversion)
7. [Dark Mode](#7-dark-mode)
8. [Hardware Encoding](#8-hardware-encoding)
9. [Migrating from jlesage/handbrake](#9-migrating-from-jlesagehandbrake)
10. [Building Locally](#10-building-locally)
11. [Troubleshooting](#11-troubleshooting)
12. [License](#12-license)
13. [Support this project](#13-support-this-project)

<br>

## 1. Overview

This image packages [HandBrake](https://handbrake.fr) — the open-source video
transcoder — into a self-contained Docker container that runs in any modern web
browser. It is built on
[`linuxserver/baseimage-selkies`](https://github.com/linuxserver/docker-baseimage-selkies),
so it inherits LSIO's actively maintained Selkies desktop-streaming stack (a
hybrid VNC/H.264 pipeline) and weekly security updates, while everything
HandBrake-specific is layered on top here.

What you get beyond bare HandBrake:

- **Selkies instead of noVNC** — a hybrid VNC/H.264 pipeline for a smooth web
  desktop, real bidirectional browser clipboard, native file upload and
  download, high-DPI ready
- **Dark by default** — HandBrake's own native GTK dark mode, not a repaint;
  switch to light with one variable
- **Watch-folder automation** — drop a file into `/watch`, get a transcode in
  `/output`, no GUI interaction
- **Atomic output** — conversions are written to a hidden `.partial` file and
  renamed on success, so a media scanner never indexes a half-written video
- **Multi-arch** — amd64 and arm64, both gated by a CI smoke test that really
  transcodes a clip before anything is published

| | **This image** | jlesage/handbrake |
|---|:---:|:---:|
| Web stack | **Selkies (WebRTC/H.264)** | noVNC |
| Base | Ubuntu (glibc) | Alpine (musl) |
| NVIDIA NVENC encoding | ✅ | ❌ ([open since 2019](https://github.com/jlesage/docker-handbrake/issues/49)) |
| Dark mode default | ✅ | opt-in via `DARK_MODE=1` |
| Watch-folder conversion | ✅ | ✅ |
| Browser clipboard | ✅ | ⚠️ |
| File upload via WebUI | ✅ | ❌ |
| Multi-arch | ✅ amd64 + arm64 | ✅ |
| Direct VNC client | ❌ (Selkies only, by design) | ✅ |

<br>

## 2. Screenshots

<p align="center">
  <img src=".github/assets/screenshots/handbrake-1.png" alt="HandBrake running in the browser in dark mode" width="100%">
</p>

<br>

## 3. Quick Start

Unraid: install from Community Applications and adjust the paths in the
template. Everything else has a working default.

Plain Docker:

```sh
docker run -d \
  --name=handbrake \
  -p 3000:3000 \
  -p 3001:3001 \
  -e PUID=99 \
  -e PGID=100 \
  -e TZ=Europe/Vienna \
  -v /mnt/user/appdata/handbrake:/config \
  -v /mnt/user/media:/storage:ro \
  -v /mnt/user/media/watch:/watch \
  -v /mnt/user/media/converted:/output \
  --restart unless-stopped \
  ghcr.io/junkerderprovinz/handbrake:latest
```

Then open `https://<host>:3001/`. Wait for `HANDBRAKE IS READY` in the container
log on the very first start.

<br>

## 4. Volumes and Ports

| Container path | Mode | Purpose |
|---|---|---|
| `/config` | rw | HandBrake presets, queue, logs and container state |
| `/storage` | ro | Media you want to browse from inside the GUI |
| `/watch` | rw | Watch folder — anything dropped here is converted automatically |
| `/watch2` … `/watch5` | rw | Additional watch folders (optional) |
| `/output` | rw | Where converted files are written |

| Port | Purpose |
|---|---|
| `3000` | WebUI over HTTP |
| `3001` | WebUI over HTTPS (self-signed by default) |

<br>

## 5. Configuration

| Variable | Default | Description |
|---|---|---|
| `PUID` / `PGID` | `911` | User and group the container runs as (Unraid: `99` / `100`) |
| `UMASK` | `022` | File-mode mask for everything the container creates |
| `TZ` | `Etc/UTC` | Container timezone |
| `LANG` | `en_US.UTF-8` | Locale, also drives HandBrake's UI language |
| `HANDBRAKE_THEME` | `dark` | `dark` or `light` — see [Dark Mode](#7-dark-mode) |
| `APP_NICENESS` | `0` | `nice` level (0-19) for the GUI and every transcode |
| `KEYBOARD_LAYOUT` | `us` | X keyboard layout loaded at session start |
| `GPU_VENDOR` | `none` | `none`, `nvidia`, `intel` or `amd` — see [Hardware Encoding](#8-hardware-encoding) |
| `CUSTOM_USER` / `PASSWORD` | empty | Set both to require a login on the WebUI; empty means no login |
| `CUSTOM_PORT` / `CUSTOM_HTTPS_PORT` | `3000` / `3001` | Internal WebUI ports |

<br>

## 6. Automated Watch-Folder Conversion

Every file dropped into `/watch` (and `/watch2`…`/watch5` when mounted) is
transcoded with the configured preset and written to `/output`. The variable
names match `jlesage/handbrake` so existing template values keep working.

| Variable | Default | Description |
|---|---|---|
| `AUTOMATED_CONVERSION` | `1` | Set to `0` to disable the daemon entirely |
| `AUTOMATED_CONVERSION_PRESET` | `General/Very Fast 1080p30` | HandBrake preset, `category/name` |
| `AUTOMATED_CONVERSION_FORMAT` | `mp4` | Output container: `mp4`, `mkv` or `webm` |
| `AUTOMATED_CONVERSION_KEEP_SOURCE` | `1` | `0` deletes the source after a successful conversion |
| `AUTOMATED_CONVERSION_VIDEO_FILE_EXTENSIONS` | (built-in list) | Space-separated extensions to pick up |
| `AUTOMATED_CONVERSION_WATCH_DIR` | `AUTO` | `AUTO` scans `/watch`…`/watchN`; any other value is used as the single watch folder |
| `AUTOMATED_CONVERSION_MAX_WATCH_FOLDERS` | `5` | How many `/watchN` folders `AUTO` looks for |
| `AUTOMATED_CONVERSION_OUTPUT_DIR` | `/output` | Destination folder |
| `AUTOMATED_CONVERSION_OUTPUT_SUBDIR` | empty | A fixed subfolder, or `SAME_AS_SRC` to mirror the source tree |
| `AUTOMATED_CONVERSION_OVERWRITE_OUTPUT` | `0` | `1` overwrites an existing output file |
| `AUTOMATED_CONVERSION_SOURCE_STABLE_TIME` | `5` | Seconds a file must stop changing before it is picked up |
| `AUTOMATED_CONVERSION_CHECK_INTERVAL` | `5` | Seconds between watch-folder scans |
| `AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS` | empty | Extra `HandBrakeCLI` arguments appended to every job |

How it behaves:

- A file is only converted once it has been **stable** for
  `AUTOMATED_CONVERSION_SOURCE_STABLE_TIME` seconds, so a file still being
  copied in is never touched.
- Output is written as `.<name>.<ext>.partial` and renamed only after
  `HandBrakeCLI` succeeds.
- Processed sources are remembered in
  `/config/handbrake/watch-state/done.list` by path, size and mtime — an
  unchanged source is never converted twice, an edited or re-copied one is.
- A failed job is recorded in `failed.list` and is not retried until the source
  changes. The full `HandBrakeCLI` output for every job is in
  `/config/handbrake-watch.log`.

<br>

## 7. Dark Mode

`HANDBRAKE_THEME=dark` (the default) applies HandBrake's own native GTK dark
mode — the stock Adwaita dark theme that ships inside GTK 4, exactly what
HandBrake uses on any Linux desktop set to dark. Nothing is repainted or
restyled. `HANDBRAKE_THEME=light` switches to the light variant.

One consequence worth knowing: the container sets `GTK_THEME`, which GTK reads
before it looks at any in-app preference. HandBrake's own light/dark toggle in
the UI therefore has no visible effect here — `HANDBRAKE_THEME` is the single
source of truth. Change it in the template and restart the container.

<br>

## 8. Hardware Encoding

Set `GPU_VENDOR` and pass the device through; the watch-folder converter then
adds `--encoder <hardware encoder>` to every job. The GUI is unaffected and
keeps its own encoder dropdown. This is the feature the Alpine-based
community image has never been able to ship at all: NVIDIA's userspace
libraries are glibc binaries that musl cannot load, so its NVENC request has
been [open since 2019](https://github.com/jlesage/docker-handbrake/issues/49).
This image is Ubuntu-based, so the standard container runtimes just work.

| `GPU_VENDOR` | What you need on the host | Works out of the box | Verified by the maintainer |
|---|---|---|---|
| `none` (default) | nothing | ✅ software x264/x265 | ✅ |
| `nvidia` | `--runtime=nvidia`, the Nvidia-Driver plugin | ✅ | ✅ real hardware, RTX 4070 Ti SUPER |
| `intel` | `/dev/dri` passthrough, `i915` or `xe` kernel driver | ❌ [known Ubuntu-packaging bug](#intel-quick-sync-qsv) | ✅ real hardware, bug found and fixed (`handbrake:gpu-full`) |
| `amd` | `/dev/dri` passthrough, `amdgpu` kernel driver, a custom image, AMD's AMF runtime | ❌ see below | ❌ no AMD GPU here |

The container never pretends. If the encoder you asked for is not usable it
falls back to software and writes the reason into the container log, plus a
full report to `/config/handbrake-gpu.log`.

### NVIDIA NVENC

`GPU_VENDOR=nvidia` encodes every watch-folder job on an NVIDIA GPU using
HandBrake's NVENC encoder instead of the CPU.

**Status:** developer-verified on real hardware (NVIDIA GeForce RTX 4070 Ti
SUPER, Unraid).

#### What the host needs

| Requirement | Value |
|---|---|
| Unraid plugin | **Nvidia-Driver** (ich777), from Community Applications |
| Extra Parameters | `--runtime=nvidia` |
| `NVIDIA_VISIBLE_DEVICES` | a GPU UUID from `nvidia-smi -L` on the host, or `all` |
| `NVIDIA_DRIVER_CAPABILITIES` | `compute,video,utility` (or `all`) |
| `GPU_VENDOR` | `nvidia` |

`NVIDIA_DRIVER_CAPABILITIES` matters more than it looks: with the variable unset
the NVIDIA runtime defaults to `utility,compute`, which does **not** include
`video` — and `video` is the capability that injects `libnvidia-encode.so.1`,
the library NVENC actually calls.

Plain Docker:

```sh
docker run -d \
  --name=handbrake \
  --runtime=nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,video,utility \
  -e GPU_VENDOR=nvidia \
  -p 3000:3000 -p 3001:3001 \
  -e PUID=99 -e PGID=100 -e TZ=Europe/Vienna \
  -v /mnt/user/appdata/handbrake:/config \
  -v /mnt/user/media/watch:/watch \
  -v /mnt/user/media/converted:/output \
  --restart unless-stopped \
  ghcr.io/junkerderprovinz/handbrake:latest
```

#### What it changes

- **Watch-folder jobs only.** `GPU_VENDOR` adds `--encoder nvenc_h264` to every
  automated conversion. In the GUI you pick the encoder yourself — the NVENC
  entries appear in HandBrake's own encoder list as soon as the GPU is passed in.
- **H.264 by default, on purpose.** The default preset is an x264 preset, so
  `nvenc_h264` keeps the delivered codec identical and only swaps the encoder.
  For HEVC, set
  `AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS=--encoder nvenc_h265` — custom args
  are appended last, so they win.
- **A HandBrake hardware preset is left alone.** If
  `AUTOMATED_CONVERSION_PRESET` already names an NVENC preset, the container does
  not override its encoder.
- **Speed presets.** NVENC does not understand x264 speed names such as
  `veryfast`; HandBrake substitutes its own default. To control the tradeoff
  yourself, add `--encoder-preset <name>` to the custom args — the valid names
  are listed by
  `docker exec handbrake HandBrakeCLI --encoder-preset-list nvenc_h264`.
- **Hardware decoding (NVDEC) stays off.** HandBrake disables hardware decoding
  as soon as any filter runs, and every stock preset crops or scales, so it would
  buy nothing by default. Force it with
  `AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS=--enable-hw-decoding nvdec` if your
  preset has no filters.

The measured details for this build, including the NVENC encoders it offers on
a working GPU and the hardware evidence behind the "developer-verified" claim,
are in [`docs/hardware-encoding-nvidia.md`](docs/hardware-encoding-nvidia.md).

### Intel Quick Sync (QSV)

Requirements on the host:

- The iGPU or Arc card passed into the container. Unraid: add `--device=/dev/dri`
  to *Extra Parameters*. Plain Docker: `--device /dev/dri`.
- The **open-source** `i915` (or `xe`) kernel driver, which every current Linux
  kernel ships. No proprietary driver, no vendor container toolkit, nothing to
  install on the host.

```sh
docker run -d \
  --name=handbrake \
  --device /dev/dri \
  -e GPU_VENDOR=intel \
  ... \
  ghcr.io/junkerderprovinz/handbrake:latest
```

On the next start the log says which encoder was chosen:

```
[handbrake-gpu] Intel QSV enabled: --encoder qsv_h264 (render node /dev/dri/renderD128)
```

**Important: the default image's QSV detection is correct, but the encode
itself currently fails.** This was measured on real Intel hardware (Intel UHD
770), not assumed: every conversion with the stock, apt-installed
`HandBrakeCLI` fails at the muxing step with "Application provided invalid,
non monotonically increasing dts to muxer". This is a confirmed bug in
Ubuntu's specific packaged build of HandBrake, independently reproduced by
another user on the identical environment
([HandBrake/HandBrake#7962](https://github.com/HandBrake/HandBrake/issues/7962)),
not a bug in this container or in HandBrake itself.

**The fix ships as an optional variant image.** Build `handbrake:gpu-full`
(`Dockerfile.gpu`, `just build-gpu-full`, 30-60 minutes on 8 cores, amd64
only, not published) — it rebuilds `HandBrakeCLI` from source with
`--enable-qsv`, which fixes the bug completely. Verified end to end: a 180 s
1080p30 clip encodes in 12 s with `qsv_h264` on this hardware (27 s in
software on the same CPU), with no mux errors, and the output decodes
cleanly. Full measured evidence is in
[`docs/hardware-encoding-intel.md`](docs/hardware-encoding-intel.md).

```sh
docker build -f Dockerfile.gpu -t handbrake:gpu-full .
docker run -d \
  --name=handbrake \
  --device /dev/dri \
  -e GPU_VENDOR=intel \
  ... \
  handbrake:gpu-full
```

Notes worth knowing:

- The chosen encoder is `qsv_h264`, so the output codec matches what the default
  preset produces and stays as compatible as before. For HEVC, set
  `AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS=--encoder qsv_h265`; custom
  arguments are appended after the automatic ones and always win.
- Hardware *decoding* is not enabled automatically. Add
  `--enable-hw-decoding qsv` to `AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS` if
  you want it.
- Quality is preset-driven and the RF scale is not identical between x264 and
  QSV, so expect a different file size at the same nominal quality.
- Quick Sync is x86-64 only. On arm64 the variable is accepted and ignored, with
  a log line saying so.
- Which encoders your specific GPU generation actually supports (H.264/H.265
  are broadly supported; AV1 needs a newer generation) is logged by HandBrake
  itself at the start of every job — see
  [`docs/hardware-encoding-intel.md`](docs/hardware-encoding-intel.md) section 2.

### AMD VCE

**Honest summary: the stock image cannot do AMD hardware encoding, and this is
not something we can fix from inside the container.** Setting `GPU_VENDOR=amd`
is still worth doing, because it prints the exact reason and keeps converting in
software:

```
[handbrake-gpu] WARNING: GPU_VENDOR=amd and /dev/dri/renderD128 exists, but HandBrakeCLI offers neither vce_h264 nor vaapi_h264 here.
```

Why:

- HandBrake's AMD path on Linux is **VCE through AMD's AMF framework**. Ubuntu
  does not build HandBrake with `--enable-vce`, and upstream enables it by
  default only for Windows builds, so the packaged `HandBrakeCLI` contains no
  AMD encoder at all.
- Even a rebuilt binary needs AMD's proprietary AMF runtime
  (`libamfrt64.so.1`, from the `amf-amdgpu-pro` package on `repo.radeon.com`).
  That library is not redistributable here, and AMD no longer ships AMF as part
  of the Linux driver stack. The last release covers **RDNA1 and RDNA2 only**
  (RX 5000 and RX 6000 series).
- HandBrake 1.11 has no VA-API fallback for AMD. VA-API encoders exist in
  upstream's development branch, so this is expected to change; when a base
  image update brings them, this container picks them up automatically, because
  it asks HandBrake which encoders exist instead of hardcoding names.

If you have an RX 5000/6000 series card and want to try anyway:

1. Install `amf-amdgpu-pro` on the host per AMD's instructions, and find the
   library: `dpkg -L amf-amdgpu-pro | grep amfrt`.
2. Build the variant image (amd64 only, expect 30 to 60 minutes; also fixes
   Intel QSV, see above):
   ```sh
   docker build -f Dockerfile.gpu -t handbrake:gpu-full .
   ```
3. Run it with the runtime mounted in and the device passed through:
   ```sh
   docker run -d \
     --name=handbrake \
     --device /dev/dri \
     -v /opt/amdgpu-pro/lib/x86_64-linux-gnu/libamfrt64.so.1:/usr/lib/x86_64-linux-gnu/libamfrt64.so.1:ro \
     -e GPU_VENDOR=amd \
     ... \
     handbrake:gpu-full
   ```
4. Check the log for `AMD hardware encoding enabled: --encoder vce_h264`. If it
   is not there, `/config/handbrake-gpu.log` says which piece is missing.

One more caveat, because it has caught people out: on cards newer than RDNA2 the
AMF runtime can report encoder capabilities and still encode on the CPU. If the
transcode runs at software speed, that is what is happening; there is no fix
available today other than waiting for HandBrake's VA-API encoders.

**AMD VCE is unverified.** There is no AMD GPU here to test the actual encode
on — see the Community Verification section below.

### What the container tells you

Every non-`none` `GPU_VENDOR` writes `/config/handbrake-gpu.log` on each start:
the render nodes and their permissions, the groups the container user is in, the
kernel driver behind each node, the encoders HandBrake really offers on your
machine, and `vainfo` / `vpl-inspect` output.

```sh
docker exec handbrake cat /config/handbrake-gpu.log
```

That file is the first thing to read when hardware encoding does not engage, and
the one thing to attach to a report.

The container never guesses an encoder name: at start-up it asks the bundled
`HandBrakeCLI` which encoders it can actually use on your GPU and picks from
that list, so a driver or GPU that cannot do the requested vendor is detected
instead of assumed.

```sh
docker logs handbrake 2>&1 | grep '\[handbrake-gpu\]'
docker exec handbrake cat /run/handbrake/gpu-args    # empty means software encoding
```

### Help us verify this (please)

**AMD VCE in this image is implemented against AMD's and HandBrake's own
documentation. It has not been verified on real hardware by the maintainer,
because there is no AMD GPU here to test on.** NVIDIA and Intel both have a
card behind them now — see the table above. Every part that could be tested
without AMD hardware has been: the runtime libraries are asserted in CI, the
encoder selection logic is exercised in CI on GPU-less runners, and the
fallback path is checked on both architectures.

What is missing is somebody with actual AMD hardware saying whether a file
comes out the other end faster — and, since Intel Quick Sync varies a lot by
GPU generation, a confirmation on hardware other than a Gen12/Xe iGPU
(older Gen9-11, or a discrete Arc card) is useful too.

If you have an AMD Radeon, or Intel hardware other than a Gen12+ iGPU:

1. Set `GPU_VENDOR=amd` (or `intel` with `handbrake:gpu-full`) and pass
   `--device /dev/dri`.
2. Convert one file.
3. Open a report with the hardware report form:
   [**Report your GPU result**](https://github.com/junkerderprovinz/handbrake/issues/new?template=hardware-report.yml)

Attach `/config/handbrake-gpu.log` and say whether it worked. A report that says
"it does not work" is just as useful as one that says it does, and the log file
usually contains the reason.

<br>

## 9. Migrating from jlesage/handbrake

- Ports change: `5800`/`5900` become `3000` (HTTP) and `3001` (HTTPS). There is
  no direct VNC port — Selkies is the only access path, by design.
- `USER_ID`/`GROUP_ID` become `PUID`/`PGID` (the LinuxServer convention).
- `DARK_MODE=1` becomes `HANDBRAKE_THEME=dark`, which is already the default.
- All `AUTOMATED_CONVERSION*` variables listed above keep their names and
  defaults, so you can copy those values over unchanged.
- `/config`, `/storage`, `/watch` and `/output` keep their meaning, but the
  `/config` contents are not compatible: start with a fresh appdata folder and
  re-import your custom presets from the GUI.

<br>

## 10. Building Locally

```sh
git clone https://github.com/junkerderprovinz/handbrake.git
cd handbrake
docker build -t handbrake:dev .
docker run -d --name hb -p 3000:3000 -p 3001:3001 handbrake:dev
```

`just check` runs the same lint chain as CI. `just smoke` builds and boots the
image; `just convert-test` drops a generated clip into its watch folder.

<br>

## 11. Troubleshooting

**The WebUI is black on the first start.** The desktop is up before HandBrake
has drawn its window. Wait for `HANDBRAKE IS READY` in `docker logs handbrake`.

**Nothing in `/watch` gets converted.** Check `docker logs handbrake` for
`[handbrake-watch]` lines. The most common cause is a watch or output folder the
container user cannot write — the init log says so explicitly:
`WARNING: watch folder /watch is NOT writable by the container user`. Fix the
share owner on the host (`chown nobody:users /mnt/user/<share>`).

**A conversion failed.** The full `HandBrakeCLI` output is in
`/config/handbrake-watch.log`. The source is recorded in
`/config/handbrake/watch-state/failed.list` and is not retried until the file
changes; delete the line to retry it.

**The UI is light although `HANDBRAKE_THEME=dark`.** Confirm the variable
reached the process:

```sh
docker exec handbrake sh -c 'cat /proc/$(pgrep -x ghb)/environ | tr "\0" "\n" | grep GTK_THEME'
```
It must print `GTK_THEME=Adwaita:dark`.

**`GPU_VENDOR=nvidia` but the log says "no /dev/nvidia* device node".** The
container was not started through the NVIDIA runtime. Add `--runtime=nvidia` to
Extra Parameters and set `NVIDIA_VISIBLE_DEVICES` to a UUID from `nvidia-smi -L`
(Unraid needs the Nvidia-Driver plugin installed first). Conversions keep running
in software until then.

**The log says `libnvidia-encode.so.1` is missing.** The GPU is passed in but the
driver capabilities are too narrow. Set
`NVIDIA_DRIVER_CAPABILITIES=compute,video,utility`; the default of the NVIDIA
runtime leaves `video` out, and `video` is what injects the encoder library.

**The log says HandBrakeCLI "offers none of" the NVENC encoders.** The GPU and
the driver library are both there, but HandBrake itself will not use NVENC on
this machine. HandBrake only lists a hardware encoder it can currently use, so
the usual cause is an NVIDIA driver older than HandBrake's minimum — update the
Nvidia-Driver plugin. The log line `Encoders HandBrakeCLI offers here:` shows
exactly what it did find.

**NVENC is on but the files are still slow.** Check which encoder ran:

```sh
grep -i nvenc /mnt/user/appdata/handbrake/handbrake-watch.log | tail -n 5
```

If the job log names a software encoder, your preset is a hardware preset the
container deliberately did not override, or your custom args set `--encoder`
themselves — custom args are applied last and win.

**Which image am I actually running?**

```sh
docker exec handbrake cat /etc/handbrake-build
```

<br>

## 12. License

This wrapper is AGPL-3.0-only (see [`LICENSE`](LICENSE)). HandBrake itself is
GPL-2.0 and its artwork is CC BY-SA 4.0 — every bundled component and its
licence is listed in [`NOTICE`](NOTICE).

<br>

## 13. Support this project

HandBrake for Unraid is a one-person project. I write, test, and support it
myself, in whatever free time is left after work. Found a bug or have an idea?
Please [open a GitHub issue](https://github.com/junkerderprovinz/handbrake/issues)
so it doesn't get lost.

If you'd like to support the time that goes into it, you're welcome to buy me
a coffee. Genuinely appreciated either way.

<p align="center">
  <a href="https://buymeacoffee.com/junkerderprovinz">
    <img src=".github/assets/button-buy-me-a-coffee.svg" alt="Buy me a coffee" width="220">
  </a>
</p>
