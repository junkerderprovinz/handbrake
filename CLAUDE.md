# CLAUDE.md — HandBrake for Unraid (Selkies)

Guide for working in this repo. Owner: `junkerderprovinz`. Public repo.

## What this is

An **own-image container** repo: HandBrake (the GTK4 video transcoder) packaged
on top of `ghcr.io/linuxserver/baseimage-selkies`, streamed to the browser via
Selkies, dark by default, with an automated watch-folder conversion daemon.
There is **no Go, no Node app, no Python service** — the deliverable is the
Docker image. `.github/assets/gen-banner.mjs` is a one-off asset generator, not
part of the runtime.

## Layout

- `Dockerfile` — the whole build. Single stage on the Selkies base: apt-installs
  `handbrake` (`/usr/bin/ghb`, GTK4) and `handbrake-cli` (`/usr/bin/HandBrakeCLI`)
  from Ubuntu universe, asserts both binaries exist, and records
  `/usr/local/share/handbrake-{version,cli-help,preset-list}.txt` into the image.
- `rootfs/` — everything shipped into the image (LF-only, see `.gitattributes`):
  - `rootfs/etc/s6-overlay/s6-rc.d/` — s6-overlay v3 init. **No `/etc/cont-init.d`
    is used**: the Selkies base rewrites `/config` and restores openbox's
    `rc.xml` in `init-selkies-config`, which runs *after* the legacy cont-init
    stage, so anything written there can be silently undone.
    Services: `init-nologin`, `init-handbrake`, `init-handbrake-web`,
    `init-handbrake-web-post` (oneshots), `svc-handbrake-watch`,
    `svc-handbrake-ready` (longruns).
  - `rootfs/usr/local/bin/` — `handbrake-theme.sh`, `handbrake-gpu.sh`,
    `handbrake-watch.sh`, `handbrake-web.sh`, `handbrake-terminal.sh`,
    `handbrake-notify.sh`, `print-banner.sh`.
  - `rootfs/defaults/` — `autostart` (openbox session, POSIX sh only),
    `startwm.sh`, and `hooks/*.example` (the conversion-hook templates copied to
    `/config/hooks` on every start).
- `.github/workflows/` — `build.yml`, `lint.yml`, `release.yml`,
  `registry-cleanup.yml`.
- `.github/release-notes/<tag>.md` — per-release notes consumed by `release.yml`.
- `.github/assets/` — banner/icon sources and the generator.
- `docs/handbrake-capabilities.md` — the recorded encoder/preset/toolkit
  capabilities of the current build. Regenerate it after every version bump.

The Unraid Community Applications **template XML lives in the central
`unraid-apps` feed repo, not here.**

## Build / test / lint

`just --list` shows the wrapped flows. The underlying commands:

```sh
docker build -t handbrake:dev .
docker run -d --name hb -p 3000:3000 -p 3001:3001 handbrake:dev
hadolint Dockerfile --ignore DL3008 --ignore DL3009
find rootfs -type f \( -name '*.sh' -o -name 'run' -o -name 'autostart' \) -print0 \
  | xargs -0 shellcheck -S warning -x -e SC1091
gitleaks dir . --redact --no-banner
```

`just check` runs the whole lint chain. There is no unit-test suite; correctness
is proven by lint plus the boot smoke gate.

## CI gates

- **lint.yml** — hadolint, shellcheck, xmllint, and a CR-character guard on
  `rootfs/`, the banner and the workflows.
- **build.yml** — one NATIVE build job per arch (amd64 on `ubuntu-latest`,
  arm64 on `ubuntu-24.04-arm`). Each job runs the **smoke gate**: WebUI answers,
  `GTK_THEME` equals `Adwaita:dark`, the `ghb` process starts and keeps the same
  PID for 20s, the watch daemon runs, the READY banner printed, and a generated
  test clip dropped into `/watch` really is transcoded into `/output` with no
  `.partial` left behind. Then a non-blocking Trivy scan, push by digest, and a
  `merge` job that assembles the multi-arch manifest for GHCR and the Docker Hub
  mirror.
- Runs on push to `main`, on `v*.*.*` tags, weekly (Sunday 04:00 UTC) and on
  dispatch.

## Release (NEVER tag without explicit approval)

1. Write `.github/release-notes/vX.Y.Z.md` (3-digit SemVer, emoji categories,
   only non-empty categories, no version heading inside the body).
2. Commit and push; wait for **Lint** and **Build & Push** to go green.
3. `git tag vX.Y.Z && git push origin vX.Y.Z`. The tag build publishes
   `:X.Y.Z / :X.Y / :X / :latest`; `release.yml` creates the GitHub release from
   the notes file. Release **title = the version only** (`vX.Y.Z`).
4. Keep the `unraid-apps` template entry in sync if anything user-facing changed.

The image stamps its build SHA/date to `/etc/handbrake-build`.

## Conventions / gotchas

- **Dark mode is `GTK_THEME=Adwaita:dark`, and that is load-bearing.** HandBrake
  1.11's GUI is GTK4 *without* libadwaita and calls
  `color_scheme_set_async(APP_PREFERS_LIGHT)` at startup, which resets
  `gtk-application-prefer-dark-theme` whenever no desktop portal answers — and
  there is no portal in this container. GTK4 reads `$GTK_THEME` before it looks
  at that setting, so the env var is the only deterministic mechanism. Side
  effect to keep documented: HandBrake's own in-app theme toggle has no visible
  effect; `HANDBRAKE_THEME` is the single source of truth.
- **`rootfs/defaults/autostart` is POSIX sh.** openbox runs it with dash and
  ignores the shebang; `[[ ]]` fails silently and skips the block.
- **The watch daemon must stay quiet when idle** so `HANDBRAKE IS READY` remains
  the last block in `docker logs`.
- **`SELKIES_ENABLE_BASIC_AUTH=false`** on purpose: the base enables basic auth
  with well-known default credentials otherwise. No login unless the user sets
  `CUSTOM_USER`/`PASSWORD`; `init-nologin` strips the empty values Unraid sends
  for blank template fields.
- **The `WEB_*` variables are a translation layer, not a feature.** Everything in
  `handbrake-web.sh` maps a jlesage-style name onto something the Selkies base
  already has. Before adding another one, check the base first: clipboard, audio,
  HTTPS, CJK fonts and basic auth are all already provided and deliberately have
  **no** variable here.
- **`handbrake-web.sh` runs in two phases and the ordering is load-bearing.**
  `pre-nginx` must run before the base's `init-nginx`, which bakes
  `$FILE_MANAGER_PATH` into `/etc/nginx/sites-available/default` and deletes the
  whole `files {}` block when `SELKIES_FILE_TRANSFERS` has no `download`.
  `post-config` must run after `init-selkies-config`, which restores
  `/etc/xdg/openbox/rc.xml` from its `.bak` on every start. Collapsing the two
  oneshots into one silently breaks whichever half loses.
- **All of `handbrake-web.sh` logs to stderr.** `resolve_allowed()` returns its
  result on stdout, and a log line mixed into that stream would become a
  published path.
- **nginx workers run as `www-data`, not `abc`.** Anything the file manager must
  serve has to be world-readable. The symlink farm lives on tmpfs at
  `/run/handbrake/webfm` and is chmod 0755 explicitly for that reason.
- **`/config` is refused as a file-manager path** because `/config/ssl/cert.key`
  is the WebUI's TLS private key. Do not "fix" that by relaxing
  `FORBIDDEN_PATHS`.
- **The hook argument order is jlesage's, verbatim.** It is the whole point:
  a hook copied from that image has to keep working. Changing it is a breaking
  change and needs a major bump.
- **Optical-drive support is wired but unverified.** `ATTACHED_DEVICES_PERMS`
  activates the base's own `init-device-perms`; no drive was ever available to
  test a rip. The README says so and must keep saying so until someone confirms
  it. `/dev/sg*` is deliberately not in that list: on a NAS that group owns every
  raw disk.
- **Disk-full during a conversion is verified-safe, not just assumed.**
  Tested against a real, size-limited output filesystem: `HandBrakeCLI`'s own
  muxer detects `ENOSPC` (`av_interleaved_write_frame failed with error 'No
  space left on device'`) and exits non-zero, `hb_run()` propagates that,
  nothing corrupt lands in `/output`, and the source is neither deleted nor
  marked done. jlesage/docker-handbrake has a confirmed bug in the opposite
  direction (a full disk gets marked successful and the source deleted,
  [issue #435](https://github.com/jlesage/docker-handbrake/issues/435)); do
  not weaken the `hb_run() && [ -s ... ] && finalise_output()` chain in the
  main loop without re-running that test.
- **GPU support lives in `handbrake-gpu.sh` only.** It resolves `GPU_VENDOR`
  (`none` | `nvidia` | `intel` | `amd`) into the extra `HandBrakeCLI` arguments
  written to `/run/handbrake/gpu-args`, and writes a diagnostics report to
  `/config/handbrake-gpu.log`. **Its stdout is a command line, not a log** —
  every human-readable line goes to stderr, or the text ends up as a
  `HandBrakeCLI` argument.
- **Never read hardware encoder availability from
  `/usr/local/share/handbrake-cli-help.txt`.** libhb lists a hardware encoder
  only when it is compiled in *and* usable on the machine right now
  (`hb_video_encoder_is_enabled()`), and that dump is recorded during
  `docker build` on a GPU-less machine, so it never contains one. Ask the live
  binary, as `abc`, which is what `hb_load_encoders()` does. Details in
  `docs/handbrake-capabilities.md`.
- **Intel QSV detects correctly but the stock package's encode is broken.**
  Ubuntu compiles `handbrake-cli` with `--enable-qsv` on amd64, but a
  confirmed, independently-reproduced bug in that specific build makes every
  real QSV encode fail at the muxer
  ([HandBrake/HandBrake#7962](https://github.com/HandBrake/HandBrake/issues/7962)).
  `Dockerfile.gpu` (optional, `just build-gpu-full`, not published, not
  CI-gated) rebuilds `HandBrakeCLI` from source with `--enable-qsv
  --enable-vce --enable-nvenc`, which fixes QSV completely and adds AMD VCE
  (Ubuntu never passes `--enable-vce`). Verified end to end on real Intel
  hardware; see `docs/hardware-encoding-intel.md`.
- **NVIDIA NVENC and Intel QSV are verified on real hardware; AMD VCE is
  not.** There is no AMD GPU to test on. Do not add a claim that VCE has been
  verified. CI asserts the runtime libraries and the fallback logic only.
- `rootfs/**` and every `*.sh` MUST stay **LF** (see `.gitattributes`); CRLF
  breaks the shebang scripts inside the image.
- **German** chat/vault, **English** repo. No AI attribution in commits or code.
  No real user data / IPs.
