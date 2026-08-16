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
    Services: `init-nologin`, `init-handbrake` (oneshots),
    `svc-handbrake-watch`, `svc-handbrake-ready` (longruns).
  - `rootfs/usr/local/bin/` — `handbrake-theme.sh`, `handbrake-gpu.sh`,
    `handbrake-watch.sh`, `print-banner.sh`.
  - `rootfs/defaults/` — `autostart` (openbox session, POSIX sh only) and
    `startwm.sh`.
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
- **GPU support lives in `handbrake-gpu.sh` only.** It resolves `GPU_VENDOR` into
  the extra `HandBrakeCLI` arguments written to `/run/handbrake/gpu-args`. v1
  ships none. Never guess an encoder identifier — read it from
  `/usr/local/share/handbrake-cli-help.txt`.
- `rootfs/**` and every `*.sh` MUST stay **LF** (see `.gitattributes`); CRLF
  breaks the shebang scripts inside the image.
- **German** chat/vault, **English** repo. No AI attribution in commits or code.
  No real user data / IPs.
