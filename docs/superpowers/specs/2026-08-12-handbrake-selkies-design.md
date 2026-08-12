# HandBrake (Selkies) — Design Spec

## Overview

A new Unraid container repo, `junkerderprovinz/handbrake`, providing HandBrake's full
GUI and automated video-conversion functionality through a Selkies (WebRTC) web
desktop — matching the architecture already used by `jdownloader`, `krusader`, and
`matrix` — plus GPU-accelerated hardware encoding (NVENC/QSV/VCN) that the existing
community standard, [jlesage/docker-handbrake](https://github.com/jlesage/docker-handbrake),
has never supported.

This is a **port, not an original product**: the app keeps its real name and identity
(HandBrake's own branding, subject to its GPL license), matching the `jdownloader`/
`krusader`/`matrix` pattern rather than the medieval-branded original-tool pattern used
for our own original tools (KnightLoader, BombVault, etc.).

## Why not fork jlesage/docker-handbrake

jlesage's container is Alpine Linux (musl libc) based. The maintainer investigated
NVIDIA GPU encoding support starting in 2019 (see
[issue #49](https://github.com/jlesage/docker-handbrake/issues/49), open since 2019,
53 comments, still unresolved) and concluded NVIDIA's CUDA/NVENC libraries are
distributed as prebuilt glibc binaries that musl cannot dynamically load. This is an
architectural dead end for that image, not a "nobody got around to it" gap.

Our existing Selkies base (used by `jdownloader`/`krusader`) is Ubuntu-based (glibc),
so a fresh build sidesteps this blocker entirely — standard `nvidia-container-toolkit`
+ apt-installed NVIDIA userspace libraries work normally. A literal git fork would drag
the Alpine base (and therefore the exact blocker we're trying to solve) along with it.

jlesage's repo and README remain the **feature and UX reference** throughout this
project — not a git remote.

## Goals

1. Full HandBrake GUI + automated (watch-folder) conversion, in-browser via Selkies,
   matching jlesage's feature set (enumerated below) so it is a drop-in upgrade path
   for anyone currently on `jlesage/handbrake`.
2. GPU-accelerated encoding for all three families HandBrake itself supports on Linux:
   **NVIDIA NVENC**, **Intel QSV**, **AMD VCN** — HandBrakeCLI supports these natively
   on Linux (`nvenc_h264`, `nvenc_h265`, `nvenc_h265_10bit`, `qsv_h264`, `qsv_h265`,
   `vce_h264`, `vce_h265` or equivalent, exact encoder identifiers to be confirmed
   against the HandBrakeCLI version actually bundled — see Task-level verification in
   the implementation plan). This is the concrete gap jlesage's image has left open for
   7 years.
3. Selkies WebUI, dark-by-default via HandBrake's own native GTK dark theme (not a
   Carbon rebuild, see Branding / Theming), CI boot-smoke gate, multi-arch GHCR +
   Docker Hub publish, Unraid CA template — matching `jdownloader`/`krusader`/`matrix`
   conventions exactly (see `Docker Container` and `GitHub` house style guides).

## Non-Goals (v1)

- Optical-drive ripping is included only if/when test hardware is available; the
  plumbing (device passthrough) is straightforward to wire but cannot be verified
  end-to-end without a physical drive. Ship it best-effort, flag as unverified in the
  README until confirmed.
- No VNC-protocol client access (jlesage offers direct VNC as an alternative to its web
  UI). We standardize on Selkies WebRTC only, matching every other container in the
  fleet — this is an intentional architecture choice, not a parity gap, since Selkies
  already supersedes the VNC-vs-web-UI distinction jlesage's image has to make.

## Architecture

- **Base:** LSIO `baseimage-selkies` (the same base as `jdownloader`/`krusader`),
  Ubuntu, glibc. Java is NOT needed here (HandBrake is C/C++ + a GTK GUI on Linux, not
  Swing) — HandBrake ships an official GTK GUI, `ghb`, on Linux, confirmed at
  implementation time against the actual bundled version.
- **App install:** `HandBrakeCLI` + `ghb` (the GTK GUI) from HandBrake's official
  Ubuntu PPA/Flatpak/AppImage — evaluate which packaging HandBrake officially publishes
  for Ubuntu at implementation time (this repo tracks whichever channel gives the
  most current stable release with least patching, mirroring how `jdownloader` pulls
  fresh from `installer.jdownloader.org` at build time rather than vendoring an old
  release).
- **s6-overlay init:** cont-init scripts for: watch-folder automated-conversion daemon
  (a small supervised script polling the watch folder and invoking `HandBrakeCLI`,
  mirroring jlesage's `AUTOMATED_CONVERSION*` env-var surface — see Feature Parity
  below), GPU vendor detection/setup, theme seeding (Carbon dark), ad/dialog-suppression
  equivalents if `ghb` has any (HandBrake is not ad-supported, so this is likely a
  no-op, confirm during implementation).
- **No Java agent needed** — HandBrake's GTK GUI does not use FlatLaf/Swing, so the
  `jdownloader`-style dialog-confirm/theme-defaults-source agent pattern does not
  apply here. Theming goes through GTK's own theme mechanism instead (see Branding /
  Theming below — resolved in favour of HandBrake's own native dark mode, not a
  Carbon rebuild).

## GPU Encoding Support

Three independent code paths, each gated on the relevant device being present and an
explicit `GPU_VENDOR=nvidia|intel|amd|none` environment variable (default `none`,
unprefixed to match jlesage's own environment-variable style since this has no
existing name to preserve compatibility with):

### NVIDIA (NVENC/NVDEC)
- Requires the host's Unraid Nvidia-Driver plugin, `--runtime=nvidia` (or Unraid's
  native "Nvidia GPU" template dropdown), `NVIDIA_VISIBLE_DEVICES`,
  `NVIDIA_DRIVER_CAPABILITIES=all` (or at least `compute,video,utility`).
- **Primary, end-to-end-testable target** — jdp has a 4070 Ti Super in the homelab
  already proven working for GPU passthrough (currently serving Ollama).
- HandBrakeCLI encoders: `nvenc_h264`, `nvenc_h265`, `nvenc_h265_10bit` (confirm exact
  identifiers against the bundled HandBrakeCLI `--help` output at build time).

### Intel (QSV)
- Requires `/dev/dri` passthrough + the `i915` kernel driver on the host (open-source,
  no proprietary driver needed — unlike jlesage's GUI-rendering caveat, QSV encoding
  itself works through VAAPI/media-driver, not the GLX path).
- No local Intel iGPU/Arc hardware to verify end-to-end — ship best-effort against
  HandBrake's own documented QSV requirements, mark as community-verifiable in the
  README until a report confirms it working.

### AMD (VCN)
- Requires `/dev/dri` passthrough + `amdgpu` kernel driver, Mesa/VAAPI userspace.
- Same caveat as Intel: no local AMD GPU to verify against, best-effort + flagged.

### Testing approach
CI boot-smoke gate cannot exercise real hardware encoding (no GPU in the CI runner).
The smoke gate proves the container boots and the GUI/automated-conversion daemon
starts; actual hardware-encode verification happens on jdp's own box for NVIDIA, and
is deferred to community reports for QSV/AMD. This asymmetry should be stated plainly
in the README ("NVENC is developer-verified; QSV/VCN are implemented per HandBrake's
own documentation but not yet hardware-verified by us — reports welcome").

## Feature Parity Checklist (from jlesage's README, environment-variable driven)

Port the full surface, renaming variables to match our house conventions where we
already have an established equivalent (e.g. `JD_LANG`-style naming), keeping
jlesage's names where there's no reason to diverge (reduces migration friction for
anyone moving from `jlesage/handbrake`):

- GUI toggle (n/a, GUI is always on)
- Theme selection (Light/Dark), matching the `jdownloader` `JD_THEME` pattern —
  **Dark is the default** (jdp, 2026-08-12: "ich will auch ein dark mode, soll der
  standard sein"), Light available as an explicit opt-out, same as every other
  container in the fleet
- Watch-folder automated conversion: preset selection, output format, keep-source
  toggle, file-extension filtering, multiple watch folders, hooks (pre/post-conversion
  scripts), staging conversion directory
- Web file manager (allowed/denied paths)
- Web terminal
- Web notifications
- Web audio passthrough
- Host clipboard sync
- Web authentication (username/password, token validity)
- Secure connection (HTTPS/TLS) — likely already the house default via Selkies, confirm
  it satisfies the same guarantees jlesage's `SECURE_CONNECTION` provides
- CJK font installation toggle
- Optical drive access (non-goal caveat above)
- Multiple-container capability (running several instances against different
  watch/output folders) — mostly a "does our volume/env design allow it" check, not
  new code
- `KEEP_APP_RUNNING`, `APP_NICENESS`, standard `USER_ID`/`GROUP_ID`/`UMASK`/`TZ`/`LANG`
  — same as every other container in the fleet already, no new work

## Branding / Theming

- Keep HandBrake's real name, real logo (GPL, no licensing concern — verify HandBrake's
  actual trademark/logo usage policy before embedding the logo asset, same diligence
  applied to every repo's assets).
- **Use HandBrake's own native dark mode, not a Carbon rebuild** (jdp, 2026-08-12: "es
  muss nicht unbedingt unser farbschema im dark mode sein falls handbrake schon einen
  nativen dark mode hat"). Investigated how jlesage's `DARK_MODE=1` actually works: it
  is not HandBrake-specific code, it simply switches the container's system GTK theme
  (`GTK_THEME`/`GTK2_RC_FILES`, implemented in jlesage's shared
  `docker-baseimage-gui`) to a stock dark GTK theme — `ghb`, being a well-behaved GTK
  app, picks that up automatically like any GTK application does. So a genuine,
  already-working dark mode exists with zero HandBrake-specific styling work: ship a
  stock dark GTK theme (e.g. Adwaita-dark, confirm the best available option at
  implementation time) as the default, rather than building a custom Carbon-matched
  GTK theme/CSS. **Dark is still the default** (matching `jdownloader`'s
  `JD_THEME=Dark` default), Light available as an explicit override — only the
  *mechanism* changed (native stock theme instead of a custom Carbon rebuild), not the
  default-dark decision itself. A Carbon-matched GTK theme remains a possible future
  visual-consistency polish, explicitly NOT a v1 requirement.
- README banner follows the established `<picture>` dark/light pair convention.

## CA / Template

- New entry in the `unraid-apps` feed repo, following the existing `jdownloader`/
  `krusader` template pattern (Icon via `generate-assets.yml`, CA template lives in
  the feed, not this repo).
- Template exposes the GPU vendor selection (Nvidia/Intel/AMD/none) as a template
  dropdown, plus the standard Selkies WebUI ports, matching how `jdownloader`'s
  template is structured today.

## Release Plan / Versioning

Standard house SemVer (`vX.Y.Z`), CI boot-smoke gate on both arches before `:latest`,
hand-written release notes with emoji categories, matching every other repo's
convention exactly (see `release-repo` skill).

## Open Questions / Risks (carried into the implementation plan, not blocking this spec)

1. Exact HandBrakeCLI encoder identifiers for QSV/VCN on the specific HandBrakeCLI
   version we bundle — confirm via `HandBrakeCLI --help` during implementation rather
   than assumed here.
2. Which official Linux GUI packaging channel (PPA/Flatpak/AppImage/source build)
   HandBrake currently recommends for Ubuntu — confirm at implementation time, mirror
   the "always pull fresh at build time" pattern `jdownloader` uses rather than
   vendoring a pinned old version, unless HandBrake's own release cadence makes that
   impractical.
3. ~~GTK dark theme mechanism~~ — **resolved**: ship a stock dark GTK theme (native
   mechanism, same one jlesage's base image already uses), not a Carbon rebuild. Only
   remaining implementation detail is which specific stock dark GTK theme package
   looks best (e.g. confirm Adwaita-dark vs. an alternative) — a quick visual check,
   not an open design question anymore.
4. Whether HandBrake's GTK GUI has any first-run dialogs analogous to JDownloader's
   forced installer dialogs (needing a dialog-confirm mechanism) — unknown until a
   fresh install is actually run and observed.
