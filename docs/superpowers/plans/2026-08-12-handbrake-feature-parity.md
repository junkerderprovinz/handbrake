# HandBrake — Feature Parity Implementation Plan (Plan 4 of 4)

> **For agentic workers:** Requires Plan 1 (core port) already implemented and merged. Steps use checkbox (`- [ ]`) syntax for tracking. Execute task-by-task, committing after each passing task.

**Goal:** Close the remaining gap to `jlesage/docker-handbrake` — web file manager, web terminal, desktop notifications, conversion hooks, a configurable staging directory, safe multi-instance operation and optical-drive plumbing — by mapping jlesage's `WEB_*` / `AUTOMATED_CONVERSION_*` surface onto capabilities the LinuxServer Selkies base already ships, and only writing new code where the base genuinely has none.

**Architecture:** A single translation script, `rootfs/usr/local/bin/handbrake-web.sh`, converts the jlesage-style `WEB_*` variables into the base's own knobs (`FILE_MANAGER_PATH`, `SELKIES_FILE_TRANSFERS`, `SELKIES_UPLOAD_DIR`, `DISABLE_TERMINALS`) and is run from two s6 oneshots — one **before** the base's `init-nginx` (which bakes those values into the nginx config) and one **after** `init-selkies-config` (which rewrites `/etc/xdg/openbox/rc.xml` on every start). The watch-folder daemon from Plan 1 gains four hook call sites around its single `hb_run()` invocation, a configurable staging directory replacing `partial_path()`, a cross-container lock directory in the watch folder, and desktop notifications routed into the running Selkies session.

**Tech Stack:** POSIX sh + bash, s6-overlay v3, nginx (`fancyindex`, already in the base), `dunst` + `libnotify` (already in the base), `xterm` (already in the base), Docker ENV, GitHub Actions.

## Global Constraints

- Repo: `d:\nextcloud\it\github\handbrake`, remote `https://github.com/junkerderprovinz/handbrake`, git identity `junkerderprovinz` / `jdp@braethoria.com`.
- **All work in this plan lands on the branch `feat/feature-parity`** (Task 1) and is merged to `main` in Task 15. `main` is the release branch; never commit this plan's intermediate states directly to it. `build.yml` only runs on `main` and on tags, so the branch is verified locally (Task 11) before the merge.
- Versioning: 3-digit SemVer, tags `vX.Y.Z`. Plan 1 shipped `v1.0.0`, Plan 2 `v1.1.0`, Plan 3 `v1.2.0` — this plan is the minor bump **`v1.3.0`** (new features, no breaking change: every new variable has a default that preserves Plan 1 behaviour except where noted in Task 13). Task 15 Step 1 confirms the real latest tag before the notes file is written.
- **Everything inside the repo is English** — code, comments, commit messages, README, release notes, log strings.
- **No AI attribution anywhere.** No `Co-Authored-By`, no "Generated with", no assistant references in commits, code or docs.
- **No em dashes in GitHub issue/PR/forum prose.** Repo files such as the README may use them; issue and forum text may not.
- LF line endings are mandatory for everything under `rootfs/` and every `*.sh` — enforced by `.gitattributes` from Plan 1. The new `rootfs/defaults/hooks/*.example` files are covered by the existing `rootfs/** text eol=lf` rule.
- **Fail loudly on permanent misconfiguration.** A staging directory that cannot be written, an allowed path that would publish the TLS private key, or an nginx fragment the server rejects must produce a loud, actionable log line and a safe fallback — never a silent half-working state.
- **Do not redefine anything Plan 1 owns.** Plan 1's files are extended with the exact edits given here. Plan 2 owns `rootfs/usr/local/bin/handbrake-gpu.sh` and README section 8; this plan touches neither.
- Never `git add -A`. Always stage explicit paths.
- **Never tag or publish a release without explicit approval from jdp.** Merging to `main` and letting `:latest` rebuild is fine; cutting `v1.3.0` is gated (Task 15).

---

## What the Selkies base already provides (established before this plan was written)

Verified against the local clones `d:\nextcloud\it\github\docker-baseimage-selkies` (branch `origin/ubunturesolute`, the tag Plan 1 pins) and `d:\nextcloud\it\github\selkies` (commit `0d134b6e1ffe42a579bc66363b0e7159ab22aacc`, the commit that base builds its web client from). Task 1 re-confirms all of it against the running image before any code is written.

| jlesage feature | Base already provides | What is actually left to do |
|---|---|---|
| `WEB_FILE_MANAGER` | **Partial.** nginx `fancyindex` serves one directory at `/files/` (`root/defaults/default.conf`, `alias REPLACE_DOWNLOADS_PATH/`), path from `FILE_MANAGER_PATH` (default `$HOME/Desktop`). Sidebar upload from `SELKIES_FILE_TRANSFERS` (default `upload,download`) into `SELKIES_UPLOAD_DIR` (default `~/Desktop`, never set by the base). No allow/deny lists. | Point it at the data mounts, wire multi-path via a symlink farm, add deny locations, set `SELKIES_UPLOAD_DIR`. Tasks 2, 4. |
| `WEB_TERMINAL` | **Partial.** `xterm`, `stterm`, `foot` ship in the image and an openbox menu entry exists; `DISABLE_TERMINALS=true` chmods all eleven terminal binaries to `0000` and strips them from `menu.xml`. No standalone browser-page terminal. | Map `WEB_TERMINAL` onto `DISABLE_TERMINALS` and add a keybind, because `ghb` is maximised and the openbox root menu is unreachable. Tasks 2, 3, 4. |
| `WEB_NOTIFICATION` | **No.** `dunst` and `libnotify-bin` are installed but no service starts them; the Selkies web client has no browser Notification API bridge. | Start `dunst` in the session and send notifications from the watch daemon. Tasks 2, 3, 9. |
| `WEB_AUDIO` | **Yes, and on by default.** PulseAudio + `svc-pulseaudio`, `SELKIES_AUDIO_ENABLED=True`. | Nothing. Variable dropped as a non-goal. Task 10 turns the microphone off. |
| `WEB_HOST_CLIPBOARD_SYNC` | **Yes, and on by default.** `SELKIES_CLIPBOARD_ENABLED/_IN_/_OUT_` all default `True`; `xclip`/`xsel`/`wl-clipboard` installed. | Nothing. Verification + README only. Tasks 1, 13. |
| `WEB_AUTHENTICATION` | **Yes.** nginx HTTP basic auth from `CUSTOM_USER`/`PASSWORD`, plus Plan 1's `init-nologin` and `SELKIES_ENABLE_BASIC_AUTH=false`. Established house pattern, identical in `jdownloader` and `krusader`. | Nothing. No parallel jlesage-named variable. Verification + README mapping. Tasks 1, 13. |
| `SECURE_CONNECTION` | **Yes.** Self-signed cert generated into `/config/ssl` on first start, HTTPS on 3001. | Nothing. Already in Plan 1's README. |
| `ENABLE_CJK_FONT` | **Yes, unconditionally.** `fonts-noto-cjk 1:20240730+repack1-1build1` is in the built base image. | Nothing. Variable dropped, always on. Verification + README. Tasks 1, 13. |
| Multiple watch folders | **Already satisfied by Plan 1.** `resolve_watch_dirs()` scans `/watch` plus `/watch2`…`/watchN` under `AUTOMATED_CONVERSION_WATCH_DIR=AUTO`. | Nothing. Verified in Task 1. |
| Optical drive | **Partial.** The LinuxServer base's `init-device-perms` already adds `abc` to the group owning any device listed in `ATTACHED_DEVICES_PERMS` and `chmod g+rw`s it. The base sets no default. | One ENV line. Task 10. Honest verification in Task 11. |

---

## Task Overview

| # | Task | Ships |
|---|---|---|
| 1 | Branch and base-capability verification sweep | branch `feat/feature-parity` (no code) |
| 2 | `handbrake-web.sh` translation layer | `rootfs/usr/local/bin/handbrake-web.sh` |
| 3 | Terminal launcher and notification sender | `handbrake-terminal.sh`, `handbrake-notify.sh` |
| 4 | The two s6 oneshots | `init-handbrake-web/**`, `init-handbrake-web-post/**` |
| 5 | Example hook scripts | `rootfs/defaults/hooks/*.example` |
| 6 | Watch daemon: configuration and helpers | `handbrake-watch.sh` |
| 7 | Watch daemon: startup block | `handbrake-watch.sh` |
| 8 | Watch daemon: conversion loop | `handbrake-watch.sh` |
| 9 | Notifications in the desktop session | `rootfs/defaults/autostart` |
| 10 | Dockerfile: ENV, `/staging`, device perms, `chmod +x` | `Dockerfile` |
| 11 | Local build and full manual verification | (no new files) |
| 12 | CI feature-parity gate | `.github/workflows/build.yml` |
| 13 | README | `README.md` |
| 14 | `CLAUDE.md` and `justfile` | `CLAUDE.md`, `justfile` |
| 15 | Merge, CI, release notes, gated tag | `.github/release-notes/v1.3.0.md` |
| 16 | Follow-ups outside this repo | (no files in this repo) |

---

### Task 1: Branch and base-capability verification sweep

Nothing here is optional. Every later task assumes these facts; if one of them is false the base image changed and the plan must be re-cut rather than pushed through.

**Files:**
- Modify/Create: none. This task creates the working branch and runs read-only checks.

**Interfaces:**
- Consumes: the image built by Plan 1 (`handbrake:dev`, rebuilt here from the current `main`).
- Produces: the branch `feat/feature-parity`, and confirmation of every base capability Tasks 2-10 build on.

- [ ] **Step 1: Sync and branch**

```bash
cd /d/nextcloud/it/github/handbrake
git fetch origin
git checkout main
git pull --rebase origin main
git checkout -b feat/feature-parity
git status --short --branch
```
Expected: `## feat/feature-parity` and a clean tree.

- [ ] **Step 2: Build and boot the current image**

```bash
cd /d/nextcloud/it/github/handbrake
docker build -t handbrake:dev .
docker rm -f hb-base 2>/dev/null || true
docker run -d --name hb-base -p 3000:3000 -p 3001:3001 handbrake:dev
for i in $(seq 1 180); do
  c=$(curl -k -o /dev/null -s -w '%{http_code}' --max-time 5 https://localhost:3001/ || true)
  [ -n "$c" ] && [ "$c" != "000" ] && { echo "WebUI up after ${i}s (HTTP $c)"; break; }
  sleep 1
done
```
Expected: a line like `WebUI up after 20s (HTTP 200)`.

- [ ] **Step 3: File manager — confirm both halves and the default path**

```bash
docker exec hb-base sh -c 'grep -n "location /files" -A 6 /etc/nginx/sites-available/default | head -20'
docker exec hb-base sh -c 'ls -ld /config/Desktop'
curl -k -s -o /dev/null -w 'GET /files/ -> %{http_code}\n' https://localhost:3001/files/
```
Expected: two `location /files {` blocks whose `alias` is `/config/Desktop/`, the directory exists, and `GET /files/ -> 200`. This proves the base serves exactly **one** directory and that redirecting it is the whole job.

- [ ] **Step 4: File manager — confirm there is no allow/deny list to reuse**

```bash
docker exec hb-base sh -c 'grep -rn "ALLOWED_PATHS\|DENIED_PATHS" /etc/s6-overlay /usr/share/selkies 2>/dev/null | head'
```
Expected: **no output.** The base has no allow/deny concept, so Task 2 has to build one.

- [ ] **Step 5: Terminal — confirm the binaries exist and the base's off-switch works**

```bash
docker exec hb-base sh -c 'ls -l /usr/bin/xterm /usr/bin/stterm /usr/bin/foot 2>/dev/null'
docker exec hb-base sh -c 'grep -n "TERMINAL_NAMES=" /etc/s6-overlay/s6-rc.d/init-selkies-config/run'
docker exec hb-base sh -c 'grep -c "handbrake-terminal\|ttyd" /usr/share/selkies/web/index.html || true'
```
Expected: `xterm` is mode `-rwxr-xr-x`, the `TERMINAL_NAMES=(...)` array lists eleven terminals, and the last command prints `0` — there is no web-page terminal in the client, only desktop terminal emulators.

- [ ] **Step 6: Terminal — confirm the GUI really is maximised (so a keybind is required)**

```bash
docker exec hb-base sh -c 'grep -n "maximized" /etc/xdg/openbox/rc.xml'
docker exec hb-base sh -c 'grep -n "</keyboard>" /etc/xdg/openbox/rc.xml'
```
Expected: `<application class="*"><maximized>yes</maximized></application>` is present, and there is exactly one `</keyboard>` line. The first line is why the openbox root menu is unreachable behind `ghb`; the second is the insertion point Task 2 uses (the base injects its own `C-S-d` keybind the same way).

- [ ] **Step 7: Clipboard and audio — confirm both are already on**

```bash
docker exec hb-base sh -c 'which xclip xsel; pgrep -x pulseaudio >/dev/null && echo "pulseaudio running"'
docker exec hb-base sh -c 'cat /run/s6/container_environment/SELKIES_CLIPBOARD_ENABLED 2>/dev/null || echo "(unset -> selkies default True)"'
```
Expected: both clipboard tools resolve, `pulseaudio running`, and the clipboard variable is unset, meaning the upstream default `True` applies. **Nothing to port for either feature.**

- [ ] **Step 8: CJK fonts — confirm they are already installed**

```bash
docker exec hb-base sh -c 'dpkg -l fonts-noto-cjk | tail -1'
docker exec hb-base sh -c 'fc-list :lang=ja | wc -l'
docker exec hb-base sh -c 'fc-list :lang=zh-cn | wc -l'
```
Expected: the package is `ii  fonts-noto-cjk`, and both counts are greater than `0`. **`ENABLE_CJK_FONT` has nothing to switch on.**

- [ ] **Step 9: Authentication — confirm the house pattern already holds**

```bash
curl -k -s -o /dev/null -w 'no creds -> %{http_code}\n' https://localhost:3001/
docker exec hb-base sh -c 'ls -l /etc/nginx/.htpasswd 2>/dev/null || echo "no .htpasswd (correct: no login by default)"'
docker rm -f hb-base >/dev/null
docker run -d --name hb-auth -p 3002:3001 -e CUSTOM_USER=tester -e PASSWORD=secret handbrake:dev >/dev/null
for i in $(seq 1 180); do
  c=$(curl -k -o /dev/null -s -w '%{http_code}' --max-time 5 https://localhost:3002/ || true)
  [ -n "$c" ] && [ "$c" != "000" ] && break
  sleep 1
done
curl -k -s -o /dev/null -w 'auth on, no creds  -> %{http_code}\n' https://localhost:3002/
curl -k -s -o /dev/null -w 'auth on, good creds -> %{http_code}\n' -u tester:secret https://localhost:3002/
docker rm -f hb-auth >/dev/null
```
Expected:
```
no creds -> 200
no .htpasswd (correct: no login by default)
auth on, no creds  -> 401
auth on, good creds -> 200
```
**`WEB_AUTHENTICATION*` is fully covered by `CUSTOM_USER`/`PASSWORD`. Do not add a second, parallel set of variables.**

- [ ] **Step 10: Multiple watch folders — confirm Plan 1 already handles it**

```bash
cd /d/nextcloud/it/github/handbrake
grep -n "resolve_watch_dirs" -A 14 rootfs/usr/local/bin/handbrake-watch.sh
```
Expected: the function loops `for (( i = 1; i <= MAX_WATCH_FOLDERS; i++ ))` over `/watch` and `/watch${i}`. **Multiple watch folders are already satisfied; this plan adds nothing for them.**

- [ ] **Step 11: Optical drives — confirm the base already owns the device-group logic**

```bash
docker run --rm --entrypoint sh handbrake:dev -c 'cat /etc/s6-overlay/s6-rc.d/init-device-perms/run'
```
Expected: a script guarded by `if [[ -z ${LSIO_NON_ROOT_USER} ]] && [[ -n ${ATTACHED_DEVICES_PERMS} ]]` that `usermod -a -G`s `abc` into the device's group and `chmod g+rw`s it. **The plumbing exists; Task 10 only has to give `ATTACHED_DEVICES_PERMS` a default.** If this file is missing, stop and report — Task 10's approach depends on it.

- [ ] **Step 12: Clean up**

```bash
docker rm -f hb-base hb-auth 2>/dev/null || true
```

No commit: this task produces the branch and knowledge, not files.

---

### Task 2: `handbrake-web.sh` — the `WEB_*` translation layer

**Files:**
- Create: `d:\nextcloud\it\github\handbrake\rootfs\usr\local\bin\handbrake-web.sh`
- Test/Verify: `bash -n` parses; `shellcheck -S warning -x -e SC1091` is clean.

**Interfaces:**
- Consumes: `FILE_MANAGER_PATH`, `SELKIES_FILE_TRANSFERS`, `SELKIES_UPLOAD_DIR`, `SELKIES_UI_SIDEBAR_SHOW_FILES`, `DISABLE_TERMINALS`, `SUBFOLDER` (all base-image knobs); `AUTOMATED_CONVERSION_MAX_WATCH_FOLDERS`, `AUTOMATED_CONVERSION_WATCH_DIR`, `AUTOMATED_CONVERSION_OUTPUT_DIR` and `HANDBRAKE_THEME` (Plan 1's Dockerfile ENV); `/etc/nginx/sites-available/default` and `/etc/xdg/openbox/rc.xml` (base-image files).
- Produces, for Tasks 3, 4, 9 and 12:
  - `/run/handbrake/webfm/` — the symlink farm nginx serves at `/files/`.
  - `/run/handbrake/webfm.map` — tab-separated `farm-entry-name<TAB>real-path`, read by the `post-config` phase.
  - `/run/handbrake/session-env` — an abc-writable file the desktop session fills in (Task 9) and `handbrake-notify.sh` reads (Task 3).
  - `/config/.config/dunst/dunstrc` — the themed notification style.
  - `/config/.config/openbox/rc.xml` — carries the `Ctrl+Alt+T` keybind when `WEB_TERMINAL=1`.

- [ ] **Step 1: Write the script**

`d:\nextcloud\it\github\handbrake\rootfs\usr\local\bin\handbrake-web.sh`:

```bash
#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# handbrake-web.sh <pre-nginx|post-config>
# ---------------------------------------------------------------------------
# Translates the jlesage-style WEB_* variables onto knobs the LinuxServer
# Selkies base ALREADY provides, instead of re-implementing a file manager, a
# terminal, a clipboard bridge or an auth layer that the base ships for free:
#
#   WEB_FILE_MANAGER*  -> FILE_MANAGER_PATH + SELKIES_FILE_TRANSFERS +
#                         SELKIES_UPLOAD_DIR + nginx deny locations
#   WEB_TERMINAL*      -> DISABLE_TERMINALS + an openbox keybind
#   WEB_NOTIFICATION   -> a themed dunstrc (dunst itself is started by
#                         /defaults/autostart, inside the desktop session)
#
# Deliberately NOT translated, because the base already does them and a second
# variable doing the same job two different ways is worse than none:
#   WEB_AUDIO                 -> PulseAudio + SELKIES_AUDIO_ENABLED, on by default
#   WEB_HOST_CLIPBOARD_SYNC   -> SELKIES_CLIPBOARD_ENABLED, on by default
#   WEB_AUTHENTICATION*       -> CUSTOM_USER / PASSWORD (the house pattern)
#   SECURE_CONNECTION         -> HTTPS on 3001, always
#   ENABLE_CJK_FONT           -> fonts-noto-cjk, always installed
#
# TWO PHASES, because the base consumes some of these before it writes the nginx
# config and produces others only afterwards:
#
#   pre-nginx     run by init-handbrake-web BEFORE the base's init-nginx, which
#                 substitutes $FILE_MANAGER_PATH into
#                 /etc/nginx/sites-available/default and deletes the entire
#                 files{} block when SELKIES_FILE_TRANSFERS carries no
#                 "download". Setting these later has no effect at all.
#   post-config   run by init-handbrake-web-post AFTER the base's
#                 init-selkies-config, which restores /etc/xdg/openbox/rc.xml
#                 from its .bak on EVERY start — a keybind written earlier is
#                 silently thrown away. The nginx config also only exists once
#                 init-nginx has run.
#
# All logging goes to STDERR on purpose: resolve_allowed() prints its result on
# stdout and must not have log lines mixed into it.
# ---------------------------------------------------------------------------
set -u

log() { echo "[handbrake-web] $*" >&2; }

truthy() {
    case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

set_env() {
    mkdir -p /run/s6/container_environment
    printf '%s' "$2" > "/run/s6/container_environment/$1"
}

FARM_ROOT="/run/handbrake/webfm"
FARM_MAP="/run/handbrake/webfm.map"
NGINX_CONFIG="/etc/nginx/sites-available/default"
SYS_RC_XML="/etc/xdg/openbox/rc.xml"
USER_RC_XML="/config/.config/openbox/rc.xml"
TERMINAL_LAUNCHER="/usr/local/bin/handbrake-terminal.sh"

# Directories the file manager must never publish. /config is the important one:
# it holds the WebUI's TLS PRIVATE KEY at /config/ssl/cert.key, which anyone who
# can reach the port could then simply download. The rest are the container's own
# guts and are never what a user meant. Subdirectories (/config/hooks, say) stay
# allowed — only these exact paths are refused.
FORBIDDEN_PATHS="/ /bin /boot /config /dev /etc /lib /lib64 /proc /root /run /sbin /sys /usr /var"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# Reject anything that could break out of an nginx directive or a shell word.
# Glob characters are rejected too: allowed paths are used as case patterns when
# denied paths are matched against them, where a "*" would silently over-match.
safe_path() {
    case "$1" in
        "")  return 1 ;;
        /*)  : ;;
        *)   return 1 ;;
    esac
    case "$1" in
        *[\"\\\$\;\{\}\#\`\'\*\?\[\]]*) return 1 ;;
    esac
    case "$1" in
        *"$(printf '\n')"*) return 1 ;;
    esac
    return 0
}

forbidden() {
    local p="${1%/}" f
    [ -z "${p}" ] && p="/"
    for f in ${FORBIDDEN_PATHS}; do
        [ "${p}" = "${f}" ] && return 0
    done
    return 1
}

# Prints one absolute, existing, permitted directory per line.
resolve_allowed() {
    local setting="${WEB_FILE_MANAGER_ALLOWED_PATHS:-AUTO}"
    local list="" p i max
    if [ "${setting}" = "AUTO" ]; then
        max="${AUTOMATED_CONVERSION_MAX_WATCH_FOLDERS:-5}"
        case "${max}" in ''|*[!0-9]*) max=5 ;; esac
        [ "${max}" -lt 1 ] && max=1
        for (( i = 1; i <= max; i++ )); do
            if [ "${i}" -eq 1 ]; then
                list="${list}/watch"$'\n'
            else
                list="${list}/watch${i}"$'\n'
            fi
        done
        if [ "${AUTOMATED_CONVERSION_WATCH_DIR:-AUTO}" != "AUTO" ]; then
            list="${list}${AUTOMATED_CONVERSION_WATCH_DIR}"$'\n'
        fi
        list="${list}${AUTOMATED_CONVERSION_OUTPUT_DIR:-/output}"$'\n'
        list="${list}/output"$'\n'
        list="${list}/storage"$'\n'
    else
        # Comma-separated, so paths may contain spaces. Never split on IFS here.
        list="$(printf '%s' "${setting}" | tr ',' '\n')"$'\n'
    fi

    printf '%s' "${list}" | while IFS= read -r p; do
        p="${p%/}"
        [ -n "${p}" ] || continue
        if ! safe_path "${p}"; then
            log "WARNING: ignoring allowed path '${p}' — not absolute, or it contains a character that is unsafe in an nginx directive"
            continue
        fi
        if forbidden "${p}"; then
            log "REFUSED allowed path '${p}': publishing it would expose container internals."
            log "        /config in particular holds the WebUI TLS private key (/config/ssl/cert.key)."
            log "        Point WEB_FILE_MANAGER_ALLOWED_PATHS at data mounts such as /output, /watch or /storage."
            continue
        fi
        [ -d "${p}" ] || continue
        printf '%s\n' "${p}"
    done | awk '!seen[$0]++'
}

# URL- and filesystem-safe entry name for one farm symlink.
farm_name() {
    local n
    n="$(basename -- "$1")"
    n="$(printf '%s' "${n}" | tr -c 'A-Za-z0-9._-' '-')"
    [ -n "${n}" ] || n="root"
    printf '%s' "${n}"
}

# The base's nginx block serves exactly ONE directory. A tree of symlinks under
# that one directory is what turns it into the multi-path file manager jlesage
# exposes. nginx follows symlinks by default (disable_symlinks is off), and the
# farm lives on tmpfs so it is rebuilt from scratch on every start and can never
# go stale.
build_farm() {
    rm -rf -- "${FARM_ROOT}"
    mkdir -p -- "${FARM_ROOT}"
    chmod 0755 "${FARM_ROOT}"
    chown abc:abc "${FARM_ROOT}" 2>/dev/null || true
    : > "${FARM_MAP}"
    local p name candidate n
    while IFS= read -r p; do
        [ -n "${p}" ] || continue
        name="$(farm_name "${p}")"
        candidate="${name}"
        n=1
        while [ -e "${FARM_ROOT}/${candidate}" ]; do
            n=$(( n + 1 ))
            candidate="${name}-${n}"
        done
        ln -s -- "${p}" "${FARM_ROOT}/${candidate}"
        printf '%s\t%s\n' "${candidate}" "${p}" >> "${FARM_MAP}"
        log "file manager: /files/${candidate}/ -> ${p}"
    done < <(resolve_allowed)
    if [ ! -s "${FARM_MAP}" ]; then
        log "WARNING: no allowed path resolved to an existing directory — /files/ will be empty."
    fi
}

# Uploads land in a REAL directory, not in the farm. The first writable allowed
# path wins, which under AUTO is /watch: upload a video in the browser and the
# watch-folder daemon converts it.
pick_upload_dir() {
    local p
    while IFS= read -r p; do
        [ -n "${p}" ] || continue
        if s6-setuidgid abc /usr/bin/test -w "${p}" 2>/dev/null; then
            printf '%s' "${p}"
            return 0
        fi
    done < <(cut -f2 "${FARM_MAP}" 2>/dev/null)
    printf '%s' "/config/Desktop"
}

write_dunstrc() {
    local dir="/config/.config/dunst" bg fg frame
    case "$(printf '%s' "${HANDBRAKE_THEME:-dark}" | tr '[:upper:]' '[:lower:]')" in
        light|adwaita) bg="#ffffff"; fg="#1f2328"; frame="#c9ccd1" ;;
        *)             bg="#242424"; fg="#e3e3e3"; frame="#3d3d3d" ;;
    esac
    mkdir -p "${dir}"
    cat > "${dir}/dunstrc" <<EOF
# Written by handbrake-web.sh on every container start — do not edit.
# Colours follow HANDBRAKE_THEME so a notification never flashes a white box
# across a dark desktop.
[global]
    monitor = 0
    follow = none
    width = 440
    height = 200
    origin = top-right
    offset = 24x24
    frame_width = 1
    frame_color = "${frame}"
    separator_color = frame
    font = DejaVu Sans 10
    markup = full
    format = "<b>%s</b>\n%b"
    icon_position = left
    max_icon_size = 48
    corner_radius = 8
    ignore_newline = no

[urgency_low]
    background = "${bg}"
    foreground = "${fg}"
    timeout = 6

[urgency_normal]
    background = "${bg}"
    foreground = "${fg}"
    timeout = 8

[urgency_critical]
    background = "${bg}"
    foreground = "${fg}"
    frame_color = "#e01b24"
    timeout = 0
EOF
    chown -R abc:abc "${dir}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# phase: pre-nginx
# ---------------------------------------------------------------------------
phase_pre_nginx() {
    mkdir -p /run/handbrake

    # The desktop session runs as abc and writes its DISPLAY and D-Bus address
    # here (see /defaults/autostart) so the root-supervised watch daemon can send
    # notifications into it. /run/handbrake is root-owned, so the file has to be
    # created with abc ownership up front.
    install -o abc -g abc -m 0644 /dev/null /run/handbrake/session-env 2>/dev/null \
        || : > /run/handbrake/session-env

    # ---- web file manager --------------------------------------------------
    if truthy "${WEB_FILE_MANAGER:-1}"; then
        build_farm
        set_env FILE_MANAGER_PATH "${FARM_ROOT}"
        set_env SELKIES_UPLOAD_DIR "$(pick_upload_dir)"
        log "file manager: ON — browse /files/, uploads go to $(cat /run/s6/container_environment/SELKIES_UPLOAD_DIR)"
    else
        # Removing "download" from SELKIES_FILE_TRANSFERS makes the base delete
        # the whole nginx files{} block, and SELKIES_UI_SIDEBAR_SHOW_FILES=false
        # hides the sidebar's upload panel. No code of our own is needed to turn
        # the feature off.
        set_env SELKIES_FILE_TRANSFERS ""
        set_env SELKIES_UI_SIDEBAR_SHOW_FILES "false"
        rm -rf -- "${FARM_ROOT}"
        rm -f -- "${FARM_MAP}"
        log "file manager: OFF (WEB_FILE_MANAGER=${WEB_FILE_MANAGER:-1})"
    fi

    # ---- web terminal ------------------------------------------------------
    if [ -n "${DISABLE_TERMINALS+x}" ]; then
        log "terminal: DISABLE_TERMINALS is set explicitly ('${DISABLE_TERMINALS}') — WEB_TERMINAL is ignored"
    elif truthy "${WEB_TERMINAL:-0}"; then
        set_env DISABLE_TERMINALS "false"
        log "terminal: ON — press Ctrl+Alt+T on the web desktop (shell ${WEB_TERMINAL_SHELL_PATH:-/bin/bash})"
    else
        set_env DISABLE_TERMINALS "true"
        log "terminal: OFF (WEB_TERMINAL=0) — the base chmods every terminal binary to 0000"
    fi

    # ---- notifications -----------------------------------------------------
    if truthy "${WEB_NOTIFICATION:-0}"; then
        write_dunstrc
        log "notifications: ON — conversion results are shown on the web desktop"
    else
        log "notifications: OFF (WEB_NOTIFICATION=0)"
    fi
}

# ---------------------------------------------------------------------------
# phase: post-config
# ---------------------------------------------------------------------------
apply_nginx_denies() {
    local raw="${WEB_FILE_MANAGER_DENIED_PATHS:-}"
    truthy "${WEB_FILE_MANAGER:-1}" || return 0
    [ -n "${raw}" ] || return 0
    if [ ! -f "${NGINX_CONFIG}" ]; then
        log "WARNING: ${NGINX_CONFIG} is missing — denied paths cannot be applied"
        return 0
    fi

    local sub blocks="" d name p rel uri matched closers
    sub="${SUBFOLDER:-/}"
    sub="${sub%/}"

    while IFS= read -r d; do
        d="${d%/}"
        [ -n "${d}" ] || continue
        if ! safe_path "${d}"; then
            log "WARNING: ignoring denied path '${d}' — not absolute, or unsafe characters"
            continue
        fi
        matched=0
        # A denied path can sit under more than one allowed path; block every
        # URI that would reach it, not just the first.
        while IFS="$(printf '\t')" read -r name p; do
            [ -n "${name}" ] || continue
            case "${d}/" in
                "${p}"/*)
                    rel="${d#"${p}"}"
                    uri="${sub}/files/${name}${rel}"
                    blocks="${blocks}  location = \"${uri}\" { return 403; }"$'\n'
                    blocks="${blocks}  location ^~ \"${uri}/\" { return 403; }"$'\n'
                    log "denied: ${uri} -> 403"
                    matched=1
                    ;;
            esac
        done < "${FARM_MAP}"
        [ "${matched}" -eq 1 ] || log "denied path '${d}' is not inside any allowed path — nothing to block"
    done < <(printf '%s' "${raw}" | tr ',' '\n')

    [ -n "${blocks}" ] || return 0

    # The generated config ends each of its two server blocks with a "}" in
    # column 1 and indents everything else. If that ever stops being true the
    # base changed its template and the insertion point is no longer safe.
    closers="$(grep -c '^}$' "${NGINX_CONFIG}" || true)"
    if [ "${closers}" != "2" ]; then
        log "ERROR: expected 2 server blocks in ${NGINX_CONFIG} but found ${closers}."
        log "       The Selkies base changed its nginx template — denied paths were NOT applied."
        log "       Set WEB_FILE_MANAGER=0 until this is fixed if the denied paths are load-bearing."
        return 0
    fi

    cp -a "${NGINX_CONFIG}" "${NGINX_CONFIG}.hb-bak"
    HB_DENY_BLOCKS="${blocks}" awk '/^}$/ { printf "%s", ENVIRON["HB_DENY_BLOCKS"] } { print }' \
        "${NGINX_CONFIG}.hb-bak" > "${NGINX_CONFIG}"
    if nginx -t >/dev/null 2>&1; then
        log "denied paths applied to both server blocks"
    else
        cp -a "${NGINX_CONFIG}.hb-bak" "${NGINX_CONFIG}"
        log "ERROR: nginx rejected the generated denied-path rules — reverted to the base config."
        nginx -t 2>&1 | sed 's/^/[handbrake-web]   /' >&2
    fi
}

apply_terminal_keybind() {
    local dir
    dir="$(dirname "${USER_RC_XML}")"

    # The base writes a root-owned, read-only user rc.xml when HARDEN_OPENBOX,
    # DISABLE_MOUSE_BUTTONS or HARDEN_KEYBINDS is on. Do not fight hardening.
    if [ -f "${USER_RC_XML}" ] && [ "$(stat -c '%U' "${USER_RC_XML}" 2>/dev/null)" = "root" ]; then
        log "openbox rc.xml is locked by the base's hardening — terminal keybind not installed"
        return 0
    fi

    if ! truthy "${WEB_TERMINAL:-0}"; then
        if [ -f "${USER_RC_XML}" ] && grep -q "${TERMINAL_LAUNCHER}" "${USER_RC_XML}" 2>/dev/null; then
            rm -f -- "${USER_RC_XML}"
            log "removed the terminal keybind (WEB_TERMINAL=0)"
        fi
        return 0
    fi

    if [ ! -f "${SYS_RC_XML}" ]; then
        log "WARNING: ${SYS_RC_XML} is missing — no terminal keybind installed"
        return 0
    fi

    # Copy the SYSTEM file every start so the base's own openbox tweaks (window
    # maximisation, decoration and keybind changes) keep flowing through, then
    # add one keybind on top. Same insertion point the base itself uses for its
    # C-S-d keybind, so the pattern is proven against this exact rc.xml.
    mkdir -p "${dir}"
    cp -f "${SYS_RC_XML}" "${USER_RC_XML}"
    sed -i "s|</keyboard>|  <keybind key=\"C-A-t\"><action name=\"Execute\"><command>${TERMINAL_LAUNCHER}</command></action></keybind>\n</keyboard>|" \
        "${USER_RC_XML}"
    if grep -q "${TERMINAL_LAUNCHER}" "${USER_RC_XML}"; then
        log "terminal keybind installed: Ctrl+Alt+T -> ${TERMINAL_LAUNCHER}"
    else
        log "WARNING: no </keyboard> element in ${SYS_RC_XML} — terminal keybind not installed."
        log "         The terminal is still reachable from the openbox root menu if a window is not covering the desktop."
    fi
    chown abc:abc "${dir}" "${USER_RC_XML}" 2>/dev/null || true
    chmod 0644 "${USER_RC_XML}"
}

phase_post_config() {
    apply_nginx_denies
    apply_terminal_keybind
}

# ---------------------------------------------------------------------------
case "${1:-}" in
    pre-nginx)   phase_pre_nginx ;;
    post-config) phase_post_config ;;
    *)
        echo "[handbrake-web] usage: handbrake-web.sh <pre-nginx|post-config>" >&2
        exit 2
        ;;
esac
exit 0
```

- [ ] **Step 2: Verify**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
bash -n rootfs/usr/local/bin/handbrake-web.sh && echo "web parses"
shellcheck -S warning -x -e SC1091 rootfs/usr/local/bin/handbrake-web.sh && echo "shellcheck OK"
bash rootfs/usr/local/bin/handbrake-web.sh 2>&1 | head -1
```
Expected:
```
web parses
shellcheck OK
[handbrake-web] usage: handbrake-web.sh <pre-nginx|post-config>
```

- [ ] **Step 3: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add rootfs/usr/local/bin/handbrake-web.sh
git commit -m "feat: translate the WEB_* variables onto the Selkies base's own knobs"
```

---

### Task 3: Terminal launcher and notification sender

**Files:**
- Create: `d:\nextcloud\it\github\handbrake\rootfs\usr\local\bin\handbrake-terminal.sh`
- Create: `d:\nextcloud\it\github\handbrake\rootfs\usr\local\bin\handbrake-notify.sh`
- Test/Verify: both parse and pass shellcheck; `handbrake-notify.sh` exits `0` silently when notifications are off.

**Interfaces:**
- Consumes: `WEB_TERMINAL_SHELL_PATH`, `GTK_THEME` (written by Plan 1's `handbrake-theme.sh`), `WEB_NOTIFICATION`, `/run/handbrake/session-env` (Task 2 creates it, Task 9 fills it), `/usr/local/share/handbrake-icon.png` (Plan 1's Dockerfile).
- Produces: `/usr/local/bin/handbrake-terminal.sh` (target of the `Ctrl+Alt+T` keybind installed in Task 2) and `/usr/local/bin/handbrake-notify.sh` (called by the watch daemon in Task 8).

- [ ] **Step 1: Write the terminal launcher**

`d:\nextcloud\it\github\handbrake\rootfs\usr\local\bin\handbrake-terminal.sh`:

```bash
#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# handbrake-terminal.sh
# ---------------------------------------------------------------------------
# Opens a terminal on the Selkies web desktop. Bound to Ctrl+Alt+T by
# handbrake-web.sh when WEB_TERMINAL=1.
#
# WHY A KEYBIND AND NOT THE MENU: the Selkies base's openbox rc.xml carries
# <application class="*"><maximized>yes</maximized></application>, so HandBrake's
# window covers the whole desktop and the openbox root menu (which already has an
# xterm entry) can never be right-clicked. A keybind works regardless.
#
# WHY xterm AND NOT A BROWSER-PAGE TERMINAL: the Selkies web client has no
# terminal page, and adding one would mean forking /usr/share/selkies/web, which
# the base recreates from scratch on every start. xterm ships in the base and is
# streamed to the browser exactly like the rest of the desktop.
# ---------------------------------------------------------------------------
set -u

SHELL_PATH="${WEB_TERMINAL_SHELL_PATH:-/bin/bash}"
if [ ! -x "${SHELL_PATH}" ]; then
    echo "[handbrake-terminal] WEB_TERMINAL_SHELL_PATH='${SHELL_PATH}' is not executable — falling back to /bin/sh" >&2
    SHELL_PATH="/bin/sh"
fi

# Match the container's theme instead of xterm's white-on-black default.
case "${GTK_THEME:-Adwaita:dark}" in
    *:dark) BG="#1e1e1e"; FG="#e3e3e3"; CUR="#e3e3e3" ;;
    *)      BG="#ffffff"; FG="#1f2328"; CUR="#1f2328" ;;
esac

exec xterm \
    -class HandBrakeTerminal \
    -title "HandBrake terminal" \
    -fa "DejaVu Sans Mono" -fs 11 \
    -bg "${BG}" -fg "${FG}" -cr "${CUR}" \
    -geometry 110x30 \
    -sb -sl 5000 \
    -e "${SHELL_PATH}"
```

- [ ] **Step 2: Write the notification sender**

`d:\nextcloud\it\github\handbrake\rootfs\usr\local\bin\handbrake-notify.sh`:

```bash
#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# handbrake-notify.sh <urgency> <summary> [body]
# ---------------------------------------------------------------------------
# Shows a notification on the Selkies web desktop. Called by handbrake-watch.sh;
# never fatal, never blocking, silent when WEB_NOTIFICATION is off.
#
# HONEST SCOPE: these are DESKTOP notifications rendered by dunst inside the
# streamed session, not browser/OS notifications via the Notification API.
# jlesage's WEB_NOTIFICATION produces the latter because his web client has a
# bridge for it; the Selkies client has none, and building one would mean forking
# /usr/share/selkies/web, which the base recreates on every start. The practical
# difference: you see the popup while the HandBrake tab is open, not when it is in
# the background. Documented as such in the README.
#
# The desktop session runs as abc under its own dbus-launch, so its DISPLAY and
# DBUS_SESSION_BUS_ADDRESS are not in this process's environment — /defaults/autostart
# writes them to /run/handbrake/session-env and this script reads them back.
# ---------------------------------------------------------------------------
set -u

case "$(printf '%s' "${WEB_NOTIFICATION:-0}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) : ;;
    *) exit 0 ;;
esac

SESSION_ENV="/run/handbrake/session-env"
[ -s "${SESSION_ENV}" ] || exit 0

# shellcheck source=/dev/null
. "${SESSION_ENV}"
export DISPLAY="${DISPLAY:-:1}"
[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] && export DBUS_SESSION_BUS_ADDRESS
[ -n "${XAUTHORITY:-}" ] && export XAUTHORITY

command -v notify-send >/dev/null 2>&1 || exit 0

# timeout: without a running dunst, notify-send waits on D-Bus activation that
# will never happen. A stuck notification must never stall a conversion loop.
timeout 5 notify-send \
    --app-name="HandBrake" \
    --icon="/usr/local/share/handbrake-icon.png" \
    --urgency="${1:-normal}" \
    -- "${2:-HandBrake}" "${3:-}" 2>/dev/null || true

exit 0
```

- [ ] **Step 3: Verify**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
bash -n rootfs/usr/local/bin/handbrake-terminal.sh && echo "terminal parses"
bash -n rootfs/usr/local/bin/handbrake-notify.sh && echo "notify parses"
shellcheck -S warning -x -e SC1091 \
  rootfs/usr/local/bin/handbrake-terminal.sh \
  rootfs/usr/local/bin/handbrake-notify.sh && echo "shellcheck OK"
WEB_NOTIFICATION=0 bash rootfs/usr/local/bin/handbrake-notify.sh normal "test" "body"; echo "exit=$?"
```
Expected:
```
terminal parses
notify parses
shellcheck OK
exit=0
```
(the notify call prints nothing, because notifications are off).

- [ ] **Step 4: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add rootfs/usr/local/bin/handbrake-terminal.sh rootfs/usr/local/bin/handbrake-notify.sh
git commit -m "feat: add the web-desktop terminal launcher and the notification sender"
```

---

### Task 4: The two s6 oneshots

**Files:**
- Create: `rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web/run`
- Create: `rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web/type`
- Create: `rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web/up`
- Create: `rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web/dependencies.d/init-os-end` (empty)
- Create: `rootfs/etc/s6-overlay/s6-rc.d/init-nginx/dependencies.d/init-handbrake-web` (empty)
- Create: `rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/init-handbrake-web` (empty)
- Create: `rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web-post/run`
- Create: `rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web-post/type`
- Create: `rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web-post/up`
- Create: `rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web-post/dependencies.d/init-handbrake` (empty)
- Create: `rootfs/etc/s6-overlay/s6-rc.d/init-config-end/dependencies.d/init-handbrake-web-post` (empty)
- Create: `rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/init-handbrake-web-post` (empty)
- Test/Verify: `shellcheck -S warning` clean on both `run` scripts; all twelve paths exist.

**Interfaces:**
- Consumes: `/usr/local/bin/handbrake-web.sh` (Task 2); the base's `init-os-end`, `init-nginx`, `init-config-end` and Plan 1's `init-handbrake`.
- Produces: the two ordering positions the translation layer needs. **Ordering is the entire point of this task; do not collapse the two oneshots into one.**

Why these exact edges:

- `init-handbrake-web` → **before** `init-nginx`, because `init-nginx` substitutes `$FILE_MANAGER_PATH` into the nginx config and deletes the whole `files {}` block when `SELKIES_FILE_TRANSFERS` has no `download`. Anything written after it is ignored. Its own `dependencies.d/init-os-end` makes it run late enough that `init-adduser` has already remapped `abc` to `PUID`/`PGID`, which `pick_upload_dir` and the farm's `chown` depend on. (`init-nginx` is already downstream of `init-os-end` through `init-selkies`, so this adds no cycle.)
- `init-handbrake-web-post` → **after** Plan 1's `init-handbrake` (and therefore after `init-nginx` and `init-selkies-config`), because the nginx config only exists once `init-nginx` has run, and `init-selkies-config` restores `/etc/xdg/openbox/rc.xml` from its `.bak` on **every** start. `init-config-end/dependencies.d/init-handbrake-web-post` is what makes the base wait for it before `init-services` starts `svc-nginx` — exactly the convention Plan 1 documents under "Established conventions".

- [ ] **Step 1: Create the directory tree and the empty marker files**

```bash
cd /d/nextcloud/it/github/handbrake
S6=rootfs/etc/s6-overlay/s6-rc.d
mkdir -p "$S6/init-handbrake-web/dependencies.d" \
         "$S6/init-handbrake-web-post/dependencies.d" \
         "$S6/init-nginx/dependencies.d" \
         "$S6/init-config-end/dependencies.d" \
         "$S6/user/contents.d"
: > "$S6/init-handbrake-web/dependencies.d/init-os-end"
: > "$S6/init-nginx/dependencies.d/init-handbrake-web"
: > "$S6/user/contents.d/init-handbrake-web"
: > "$S6/init-handbrake-web-post/dependencies.d/init-handbrake"
: > "$S6/init-config-end/dependencies.d/init-handbrake-web-post"
: > "$S6/user/contents.d/init-handbrake-web-post"
```

- [ ] **Step 2: Write `init-handbrake-web/run`**

`d:\nextcloud\it\github\handbrake\rootfs\etc\s6-overlay\s6-rc.d\init-handbrake-web\run`:

```bash
#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# -----------------------------------------------------------------------------
# init-handbrake-web — the WEB_* translation layer, PRE-nginx half
# -----------------------------------------------------------------------------
# Ordered before the base's init-nginx by
# init-nginx/dependencies.d/init-handbrake-web. That is load-bearing: init-nginx
# bakes $FILE_MANAGER_PATH into /etc/nginx/sites-available/default and deletes
# the entire files{} block when SELKIES_FILE_TRANSFERS carries no "download",
# so these values have to exist before it runs.
#
# dependencies.d/init-os-end keeps it late enough that init-adduser has already
# remapped abc to PUID/PGID.
# -----------------------------------------------------------------------------
exec /usr/local/bin/handbrake-web.sh pre-nginx
```

- [ ] **Step 3: Write `init-handbrake-web/type` and `up`**

`rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web/type`:

```text
oneshot
```

`rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web/up`:

```text
/etc/s6-overlay/s6-rc.d/init-handbrake-web/run
```

- [ ] **Step 4: Write `init-handbrake-web-post/run`**

`d:\nextcloud\it\github\handbrake\rootfs\etc\s6-overlay\s6-rc.d\init-handbrake-web-post\run`:

```bash
#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# -----------------------------------------------------------------------------
# init-handbrake-web-post — the WEB_* translation layer, POST-config half
# -----------------------------------------------------------------------------
# Ordered after Plan 1's init-handbrake, which itself runs after the base's
# init-selkies-config. Two things force this position:
#   * /etc/nginx/sites-available/default only exists once init-nginx wrote it,
#     and the denied-path locations are appended to that generated file.
#   * init-selkies-config restores /etc/xdg/openbox/rc.xml from its .bak on
#     EVERY start, so a terminal keybind written earlier would be thrown away.
#
# init-config-end/dependencies.d/init-handbrake-web-post makes the base wait for
# this oneshot before init-services brings svc-nginx up.
# -----------------------------------------------------------------------------
exec /usr/local/bin/handbrake-web.sh post-config
```

- [ ] **Step 5: Write `init-handbrake-web-post/type` and `up`**

`rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web-post/type`:

```text
oneshot
```

`rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web-post/up`:

```text
/etc/s6-overlay/s6-rc.d/init-handbrake-web-post/run
```

- [ ] **Step 6: Verify**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
find rootfs/etc/s6-overlay -type f -name '*handbrake-web*' -o -path '*handbrake-web*' -type f | sort
shellcheck -S warning -x -e SC1091 \
  rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web/run \
  rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web-post/run
```
Expected file list (exactly these twelve, in this order):
```
rootfs/etc/s6-overlay/s6-rc.d/init-config-end/dependencies.d/init-handbrake-web-post
rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web-post/dependencies.d/init-handbrake
rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web-post/run
rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web-post/type
rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web-post/up
rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web/dependencies.d/init-os-end
rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web/run
rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web/type
rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web/up
rootfs/etc/s6-overlay/s6-rc.d/init-nginx/dependencies.d/init-handbrake-web
rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/init-handbrake-web
rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/init-handbrake-web-post
```
and shellcheck prints nothing. (The `find` also lists Plan 1's unrelated files if the expression is mistyped — if you see `init-nologin` or `svc-handbrake-watch` in the output, the shell glob was wrong, not the tree.)

- [ ] **Step 7: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web \
        rootfs/etc/s6-overlay/s6-rc.d/init-handbrake-web-post \
        rootfs/etc/s6-overlay/s6-rc.d/init-nginx/dependencies.d/init-handbrake-web \
        rootfs/etc/s6-overlay/s6-rc.d/init-config-end/dependencies.d/init-handbrake-web-post \
        rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/init-handbrake-web \
        rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/init-handbrake-web-post
git commit -m "feat: run the web translation layer before init-nginx and after init-selkies-config"
```

---

### Task 5: Example hook scripts

**Files:**
- Create: `rootfs/defaults/hooks/pre_conversion.sh.example`
- Create: `rootfs/defaults/hooks/post_conversion.sh.example`
- Create: `rootfs/defaults/hooks/post_watch_folder_processing.sh.example`
- Create: `rootfs/defaults/hooks/hb_custom_args.sh.example`
- Test/Verify: all four parse with `sh -n`; the file names match the hook names the daemon looks for, minus `.example`.

**Interfaces:**
- Consumes: nothing.
- Produces: `/defaults/hooks/*.example`, copied to `/config/hooks/` by `seed_hooks()` in Task 6. **The argument order in these files is the contract Task 8 implements — it is jlesage's, verbatim from his README, so a migrating user's hook keeps working.**

- [ ] **Step 1: Create the directory and write `pre_conversion.sh.example`**

```bash
mkdir -p /d/nextcloud/it/github/handbrake/rootfs/defaults/hooks
```

`d:\nextcloud\it\github\handbrake\rootfs\defaults\hooks\pre_conversion.sh.example`:

```sh
#!/bin/sh
# HandBrake pre-conversion hook.
#
# ENABLE IT: copy this file to /config/hooks/pre_conversion.sh (drop the
# .example suffix). The .example files themselves are refreshed from the image on
# every start and are never executed.
#
# Runs immediately before HandBrakeCLI starts on a file.
#   $1  final output file (where the converted video will end up)
#   $2  source file
#   $3  HandBrake preset
#
# The same values are also in the environment, which is easier to read:
#   HB_INPUT   HB_OUTPUT   HB_PRESET   HB_FORMAT   HB_WATCH_DIR
#
# EXIT CODE MATTERS: a non-zero exit REFUSES the file. The conversion is skipped
# and the source is recorded in failed.list, so it is not retried until the file
# itself changes.
#
# Hooks are executed with /bin/sh; the shebang above is ignored.

echo "pre_conversion: ${2} -> ${1} (preset ${3})"
exit 0
```

- [ ] **Step 2: Write `post_conversion.sh.example`**

`d:\nextcloud\it\github\handbrake\rootfs\defaults\hooks\post_conversion.sh.example`:

```sh
#!/bin/sh
# HandBrake post-conversion hook.
#
# ENABLE IT: copy this file to /config/hooks/post_conversion.sh.
#
# Runs after every conversion attempt, successful or not, and after the finished
# file has already been moved from the staging directory to its final location.
#   $1  status: 0 on success, non-zero on failure
#   $2  final output file
#   $3  source file
#   $4  HandBrake preset
#
# Also in the environment: HB_STATUS HB_INPUT HB_OUTPUT HB_PRESET HB_FORMAT
# HB_WATCH_DIR.
#
# The exit code is ignored: a failing post hook is logged but never changes the
# conversion result.
#
# Hooks are executed with /bin/sh; the shebang above is ignored.

if [ "${1}" = "0" ]; then
    echo "post_conversion: OK ${3} -> ${2}"
else
    echo "post_conversion: FAILED (status ${1}) ${3}"
fi
exit 0
```

- [ ] **Step 3: Write `post_watch_folder_processing.sh.example`**

`d:\nextcloud\it\github\handbrake\rootfs\defaults\hooks\post_watch_folder_processing.sh.example`:

```sh
#!/bin/sh
# HandBrake post-watch-folder hook.
#
# ENABLE IT: copy this file to /config/hooks/post_watch_folder_processing.sh.
#
# Runs once at the end of a scan pass over a watch folder, and only when that
# pass actually converted at least one file. An idle container never calls it.
#   $1  the watch folder that was just processed
#
# Also in the environment: HB_WATCH_DIR HB_PRESET HB_FORMAT.
#
# Typical use: kick a media-library rescan now that new files exist.
#
# Hooks are executed with /bin/sh; the shebang above is ignored.

echo "post_watch_folder_processing: finished a pass over ${1}"
exit 0
```

- [ ] **Step 4: Write `hb_custom_args.sh.example`**

`d:\nextcloud\it\github\handbrake\rootfs\defaults\hooks\hb_custom_args.sh.example`:

```sh
#!/bin/sh
# HandBrake custom-argument hook.
#
# ENABLE IT: copy this file to /config/hooks/hb_custom_args.sh.
#
# Runs just before HandBrakeCLI and decides extra arguments per file.
#   $1  source file
#   $2  HandBrake preset
#
# Print ONE space-separated line of extra HandBrakeCLI arguments on stdout, or
# print nothing to add nothing. Anything on stderr goes to
# /config/handbrake-watch.log.
#
# The arguments are appended AFTER AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS, so
# where both set the same flag this hook wins.
#
# Hooks are executed with /bin/sh; the shebang above is ignored.

case "${1}" in
    *.mkv) echo "--all-subtitles" ;;
    *)     : ;;
esac
exit 0
```

- [ ] **Step 5: Verify**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
for f in rootfs/defaults/hooks/*.example; do sh -n "$f" && echo "OK  $f"; done
ls rootfs/defaults/hooks/
```
Expected: four `OK` lines, and exactly these four names:
```
hb_custom_args.sh.example
post_conversion.sh.example
post_watch_folder_processing.sh.example
pre_conversion.sh.example
```

- [ ] **Step 6: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add rootfs/defaults/hooks
git commit -m "feat: ship example conversion hooks documenting the hook contract"
```

---

### Task 6: Watch daemon — configuration and helper functions

Six additive edits to Plan 1's `handbrake-watch.sh`. Each quotes the exact text Plan 1 created; if a quoted block does not match byte for byte, stop and re-read the file rather than guessing — Plan 1 Task 9 Step 5 allows the `case "${FORMAT}"` muxer names to have been corrected, but nothing in the blocks below.

**Files:**
- Modify: `d:\nextcloud\it\github\handbrake\rootfs\usr\local\bin\handbrake-watch.sh`
- Test/Verify: `bash -n` parses; `shellcheck -S warning -x -e SC1091` is clean.

**Interfaces:**
- Consumes: Plan 1's `PRESET`, `FORMAT`, `OUTPUT_DIR`, `JOB_LOG`, `STATE_DIR`, `log()`, `truthy()`, `CURRENT_PARTIAL`, `CURRENT_PID`, `cleanup()`, `hb_run()`; `/usr/local/bin/handbrake-notify.sh` (Task 3); the hook contract from Task 5.
- Produces, for Tasks 7 and 8: `HOOKS_DIR`, `STAGING_DIR`, `INSTANCE`, the exported `HB_*` hook context, and the functions `run_hook()`, `seed_hooks()`, `notify()`, `staging_path()`, `finalise_output()`, `lock_path()`, `acquire_lock()`, `release_lock()`, `clear_own_locks()`.

- [ ] **Step 1: Add the new configuration block**

Find this exact block:

```bash
STATE_DIR="/config/handbrake/watch-state"
DONE_LIST="${STATE_DIR}/done.list"
FAILED_LIST="${STATE_DIR}/failed.list"
JOB_LOG="/config/handbrake-watch.log"
```

Replace it with:

```bash
STATE_DIR="/config/handbrake/watch-state"
DONE_LIST="${STATE_DIR}/done.list"
FAILED_LIST="${STATE_DIR}/failed.list"
JOB_LOG="/config/handbrake-watch.log"

# Conversion hooks. Fixed path, same as jlesage/handbrake, so a migrating user's
# scripts land where they already expect.
HOOKS_DIR="/config/hooks"

# Staging: an in-progress conversion is written here and only moved to its final
# destination once HandBrakeCLI succeeded. Empty means "a hidden directory under
# the output root", which is exactly what jlesage does. Point it at a fast local
# disk (an Unraid cache pool, say) to keep the array out of the write path while
# a transcode runs, then let the finished file land on the array.
STAGING_DIR="${AUTOMATED_CONVERSION_STAGING_DIR:-}"
[ -z "${STAGING_DIR}" ] && STAGING_DIR="${OUTPUT_DIR}/.handbrake-staging"

# Short, stable tag for THIS container. Two instances may share a staging
# directory or a watch folder, so every file we create carries our own tag: on
# restart we may only clean up our own leftovers, never another live instance's.
INSTANCE="$(tr -cd 'a-zA-Z0-9' < /etc/hostname 2>/dev/null | head -c 12)"
[ -z "${INSTANCE}" ] && INSTANCE="handbrake"

# Hook context. Exported once so every hook sees the same variable names no
# matter which hook it is; the values are reassigned at each call site.
HB_INPUT=""
HB_OUTPUT=""
HB_STATUS=""
HB_WATCH_DIR=""
export HB_INPUT HB_OUTPUT HB_STATUS HB_WATCH_DIR
export HB_PRESET="${PRESET}"
export HB_FORMAT="${FORMAT}"
```

- [ ] **Step 2: Track the lock in the shutdown handler**

Find this exact block:

```bash
CURRENT_PARTIAL=""
CURRENT_PID=""
```

Replace it with:

```bash
CURRENT_PARTIAL=""
CURRENT_PID=""
CURRENT_LOCK=""
LOCK_WARNED=0
```

Then find this exact line inside `cleanup()`:

```bash
    exit 0
}
trap cleanup TERM INT
```

Replace it with:

```bash
    release_lock
    exit 0
}
trap cleanup TERM INT
```

- [ ] **Step 3: Replace `partial_path()` with the staging helpers**

Find this exact function:

```bash
partial_path() {
    # Plan 4 replaces this single helper when it adds a configurable staging
    # directory. Everything else in the daemon keeps working unchanged.
    printf '%s/.%s.partial' "$1" "$2"
}
```

Replace it with:

```bash
staging_path() {
    # $1 = final file name (stem.ext). Replaces Plan 1's partial_path(): the
    # in-progress file now lives in STAGING_DIR instead of next to the finished
    # output, so a media scanner watching /output never sees it at all, and the
    # staging directory can sit on a different (faster) disk. The instance tag
    # keeps two containers that share a staging directory apart.
    printf '%s/.%s.%s.partial' "${STAGING_DIR}" "${INSTANCE}" "$1"
}

finalise_output() {
    # $1 = finished staging file, $2 = final destination.
    #
    # Two steps on purpose. When STAGING_DIR is on a different filesystem than
    # the output, `mv` is a copy and is NOT atomic, so a scanner could index a
    # half-copied file. Copying to a hidden sibling INSIDE the destination
    # directory first makes the last step a same-filesystem rename, which is.
    local stage="$1" dst="$2" tmp
    tmp="$(dirname -- "${dst}")/.${INSTANCE}.$(basename -- "${dst}").moving"
    rm -f -- "${tmp}"
    if ! mv -f -- "${stage}" "${tmp}"; then
        log "ERROR: could not move '${stage}' to '${tmp}' — is the output folder writable and does it have room?"
        return 1
    fi
    if ! mv -f -- "${tmp}" "${dst}"; then
        log "ERROR: could not rename '${tmp}' to '${dst}'"
        rm -f -- "${tmp}"
        return 1
    fi
    return 0
}
```

- [ ] **Step 4: Add the hook, notification and locking helpers**

Insert the following immediately **after** the `finalise_output()` function you just created and **before** the `hb_run()` function:

```bash
seed_hooks() {
    # The .example files document the contract and are refreshed from the image
    # on every start. A real hook the user installed is never touched.
    mkdir -p -- "${HOOKS_DIR}" 2>/dev/null || return 0
    local ex
    for ex in /defaults/hooks/*.example; do
        [ -e "${ex}" ] || continue
        cp -f -- "${ex}" "${HOOKS_DIR}/$(basename -- "${ex}")" 2>/dev/null || true
    done
}

run_hook() {
    # $1 = hook file name, the rest = positional arguments for the hook.
    # Returns the hook's exit code; returns 0 when the hook does not exist.
    local name="$1" rc=0
    shift
    local hook="${HOOKS_DIR}/${name}"
    [ -f "${hook}" ] || return 0
    log "hook ${name}: running"
    {
        echo "=== $(date -Is) hook ${name} $*"
    } >> "${JOB_LOG}"
    # /bin/sh on purpose, shebang ignored — the same contract jlesage documents,
    # so a hook copied over from that image behaves identically here.
    /bin/sh "${hook}" "$@" >> "${JOB_LOG}" 2>&1 || rc=$?
    [ "${rc}" -ne 0 ] && log "hook ${name}: exited ${rc}"
    return "${rc}"
}

notify() {
    # Desktop notification on the web desktop. Never fatal, never blocking, and
    # a no-op unless WEB_NOTIFICATION is on.
    /usr/local/bin/handbrake-notify.sh "$1" "$2" "${3:-}" 2>/dev/null || true
}

lock_path() {
    # $1 = watch folder, $2 = source path.
    printf '%s/.handbrake-lock-%s' "$1" "$(printf '%s' "$2" | sha1sum | cut -d' ' -f1)"
}

acquire_lock() {
    # $1 = watch folder, $2 = source path.
    # Returns 0 when this instance may convert the file, 1 when another instance
    # already owns it. `mkdir` is the atomic primitive here: exactly one caller
    # can create a given directory, which is what makes two containers sharing a
    # watch folder safe.
    local dir="$1" src="$2" lock
    lock="$(lock_path "${dir}" "${src}")"
    if mkdir -- "${lock}" 2>/dev/null; then
        printf '%s\n%s\n' "${INSTANCE}" "$(date +%s)" > "${lock}/.owner" 2>/dev/null || true
        CURRENT_LOCK="${lock}"
        return 0
    fi
    if [ -d "${lock}" ]; then
        return 1
    fi
    # mkdir failed and no lock is there: the watch folder is read-only. That is
    # fine for a single container, so carry on unlocked and say so exactly once.
    if [ "${LOCK_WARNED}" -eq 0 ]; then
        log "NOTE: '${dir}' is not writable, so cross-container locking is off."
        log "      Fine for one container. Do NOT point a second instance at this"
        log "      folder, or both would convert the same file at the same time."
        LOCK_WARNED=1
    fi
    CURRENT_LOCK=""
    return 0
}

release_lock() {
    [ -n "${CURRENT_LOCK}" ] || return 0
    rm -f -- "${CURRENT_LOCK}/.owner" 2>/dev/null || true
    rmdir -- "${CURRENT_LOCK}" 2>/dev/null || true
    CURRENT_LOCK=""
}

clear_own_locks() {
    # Only ever removes locks THIS container left behind after an unclean stop.
    # Another running instance's lock is never touched.
    local dir="$1" lock owner
    for lock in "${dir}"/.handbrake-lock-*; do
        [ -d "${lock}" ] || continue
        owner="$(head -n1 -- "${lock}/.owner" 2>/dev/null || true)"
        if [ "${owner}" = "${INSTANCE}" ]; then
            rm -f -- "${lock}/.owner" 2>/dev/null || true
            rmdir -- "${lock}" 2>/dev/null || true
            log "cleared our own stale lock in ${dir}"
        fi
    done
}
```

- [ ] **Step 5: Let `hb_run()` consult the `hb_custom_args.sh` hook**

Find this exact block inside `hb_run()`:

```bash
    [ "${#HB_GPU_ARGS[@]}" -gt 0 ] && args+=( "${HB_GPU_ARGS[@]}" )
    [ "${#HB_EXTRA_ARGS[@]}" -gt 0 ] && args+=( "${HB_EXTRA_ARGS[@]}" )
```

Replace it with:

```bash
    [ "${#HB_GPU_ARGS[@]}" -gt 0 ] && args+=( "${HB_GPU_ARGS[@]}" )
    [ "${#HB_EXTRA_ARGS[@]}" -gt 0 ] && args+=( "${HB_EXTRA_ARGS[@]}" )

    # Per-file arguments from the hb_custom_args.sh hook, appended LAST so they
    # win over both the GPU seam and AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS
    # (HandBrakeCLI takes the last occurrence of a repeated flag).
    local -a hook_args=()
    local hook_out
    if [ -f "${HOOKS_DIR}/hb_custom_args.sh" ]; then
        hook_out="$(/bin/sh "${HOOKS_DIR}/hb_custom_args.sh" "${src}" "${PRESET}" 2>> "${JOB_LOG}")" || hook_out=""
        [ -n "${hook_out}" ] && read -r -a hook_args <<< "${hook_out}"
    fi
    [ "${#hook_args[@]}" -gt 0 ] && args+=( "${hook_args[@]}" )
```

- [ ] **Step 6: Verify**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
bash -n rootfs/usr/local/bin/handbrake-watch.sh && echo "watch parses"
shellcheck -S warning -x -e SC1091 rootfs/usr/local/bin/handbrake-watch.sh && echo "shellcheck OK"
grep -c 'partial_path' rootfs/usr/local/bin/handbrake-watch.sh
grep -n 'staging_path\|finalise_output\|acquire_lock\|release_lock\|clear_own_locks\|run_hook\|seed_hooks\|^notify()' rootfs/usr/local/bin/handbrake-watch.sh | head -20
```
Expected: `watch parses`, `shellcheck OK`, then `1` (the single remaining `partial_path` call in the main loop, which Task 8 replaces), and the function definitions listed. If the `partial_path` count is `0` you deleted the call site too early; if it is `2` the function definition was not replaced.

- [ ] **Step 7: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add rootfs/usr/local/bin/handbrake-watch.sh
git commit -m "feat: add hook, staging and cross-instance locking helpers to the watch daemon"
```

---

### Task 7: Watch daemon — startup block

**Files:**
- Modify: `d:\nextcloud\it\github\handbrake\rootfs\usr\local\bin\handbrake-watch.sh`
- Test/Verify: `bash -n` parses; shellcheck clean; the new startup log lines appear in Task 11.

**Interfaces:**
- Consumes: `STAGING_DIR`, `INSTANCE`, `HOOKS_DIR`, `seed_hooks()`, `clear_own_locks()` (Task 6); `WATCH_DIRS` and `OUTPUT_DIR` (Plan 1).
- Produces: a validated, empty staging directory and a seeded `/config/hooks` before the first pass; the extra startup log lines the CI gate greps for in Task 12.

- [ ] **Step 1: Validate the staging directory and clear our own leftovers**

Find this exact block:

```bash
mkdir -p "${OUTPUT_DIR}"
log "watching: ${WATCH_DIRS[*]}"
```

Replace it with:

```bash
mkdir -p "${OUTPUT_DIR}"

# ---- staging directory ------------------------------------------------------
# Refuse to run rather than fail every single conversion: an unwritable staging
# directory is a permanent misconfiguration, not a transient error, and silently
# retrying it forever would just fill the log.
mkdir -p -- "${STAGING_DIR}" 2>/dev/null || true
if [ ! -d "${STAGING_DIR}" ] || [ ! -w "${STAGING_DIR}" ]; then
    log "ERROR: the staging directory '${STAGING_DIR}' does not exist or is not writable."
    log "       Every conversion would fail. Either fix the host folder's owner,"
    log "       e.g. on the Unraid console:  chown nobody:users /mnt/user/<share>"
    log "       or point AUTOMATED_CONVERSION_STAGING_DIR at a writable path."
    log "       Refusing to convert anything until this is fixed. The GUI still works."
    exec sleep infinity
fi

# Leftovers from an unclean stop of THIS container. Another instance's files
# carry a different instance tag and are deliberately left alone.
find "${STAGING_DIR}" -maxdepth 1 -type f -name ".${INSTANCE}.*.partial" -delete 2>/dev/null || true
find "${OUTPUT_DIR}" -type f -name ".${INSTANCE}.*.moving" -delete 2>/dev/null || true
for _wd in "${WATCH_DIRS[@]}"; do
    clear_own_locks "${_wd}"
done

seed_hooks

log "watching: ${WATCH_DIRS[*]}"
```

- [ ] **Step 2: Report the new settings at startup**

Find this exact line:

```bash
log "job log:  ${JOB_LOG}   state: ${STATE_DIR}"
```

Replace it with:

```bash
log "job log:  ${JOB_LOG}   state: ${STATE_DIR}"
log "staging:  ${STAGING_DIR}   instance: ${INSTANCE}"
log "hooks:    ${HOOKS_DIR}   notifications=${WEB_NOTIFICATION:-0}"
```

- [ ] **Step 3: Verify**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
bash -n rootfs/usr/local/bin/handbrake-watch.sh && echo "watch parses"
shellcheck -S warning -x -e SC1091 rootfs/usr/local/bin/handbrake-watch.sh && echo "shellcheck OK"
grep -n 'seed_hooks$\|clear_own_locks "\${_wd}"\|staging:  ' rootfs/usr/local/bin/handbrake-watch.sh
```
Expected: `watch parses`, `shellcheck OK`, and three matching lines — the `seed_hooks` call, the `clear_own_locks` call inside the loop, and the `staging:` log line.

- [ ] **Step 4: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add rootfs/usr/local/bin/handbrake-watch.sh
git commit -m "feat: validate the staging directory and seed the hooks folder at daemon startup"
```

---

### Task 8: Watch daemon — the conversion loop

One replacement of the whole main loop. It is presented as a single edit on purpose: hooks, staging, locking and notifications interleave inside the loop body, and four separate edits to the same twenty lines would each depend on the previous one having landed exactly right.

**Files:**
- Modify: `d:\nextcloud\it\github\handbrake\rootfs\usr\local\bin\handbrake-watch.sh`
- Test/Verify: `bash -n` parses; shellcheck clean; the real behaviour is proven in Task 11 and gated in CI in Task 12.

**Interfaces:**
- Consumes: every helper from Task 6.
- Produces: the runtime behaviour the README (Task 13) documents and the CI gate (Task 12) asserts.

- [ ] **Step 1: Replace the main loop**

Find this exact block — it starts at Plan 1's `# ---- main loop` comment and runs to the end of the file:

```bash
# ---- main loop -------------------------------------------------------------
while true; do
    for watch_dir in "${WATCH_DIRS[@]}"; do
        while IFS= read -r -d '' src; do
```

…through to the final three lines:

```bash
        done < <(find "${watch_dir}" -type f -print0 2>/dev/null)
    done
    sleep "${CHECK_INTERVAL}"
done
```

Replace the entire block with:

```bash
# ---- main loop -------------------------------------------------------------
while true; do
    for watch_dir in "${WATCH_DIRS[@]}"; do
        processed=0
        while IFS= read -r -d '' src; do
            base="$(basename -- "${src}")"
            case "${base}" in .*) continue ;; esac

            ext="$(printf '%s' "${base##*.}" | tr '[:upper:]' '[:lower:]')"
            [ "${ext}" = "${base}" ] && continue
            is_video "${ext}" || continue

            key="$(file_key "${src}")"
            in_list "${DONE_LIST}"   "${key}" && continue
            in_list "${FAILED_LIST}" "${key}" && continue

            now="$(date +%s)"
            if [ "${SEEN_KEY[${src}]:-}" != "${key}" ]; then
                SEEN_KEY["${src}"]="${key}"
                SEEN_AT["${src}"]="${now}"
                continue
            fi
            [ $(( now - ${SEEN_AT[${src}]} )) -ge "${STABLE_TIME}" ] || continue

            # -- cross-instance lock -----------------------------------------
            # Two containers may watch the same folder to convert twice as many
            # files at once. Whoever creates the lock directory first owns this
            # file; everybody else moves on to the next one.
            if ! acquire_lock "${watch_dir}" "${src}"; then
                continue
            fi

            # -- destination -------------------------------------------------
            out_base="${OUTPUT_DIR}"
            case "${OUTPUT_SUBDIR}" in
                "") : ;;
                SAME_AS_SRC)
                    rel="${src#"${watch_dir}"/}"
                    rel_dir="$(dirname -- "${rel}")"
                    [ "${rel_dir}" != "." ] && out_base="${OUTPUT_DIR}/${rel_dir}"
                    ;;
                *) out_base="${OUTPUT_DIR}/${OUTPUT_SUBDIR}" ;;
            esac
            mkdir -p -- "${out_base}"

            stem="${base%.*}"
            dst="${out_base}/${stem}.${FORMAT}"

            if [ -e "${dst}" ] && ! truthy "${AUTOMATED_CONVERSION_OVERWRITE_OUTPUT:-0}"; then
                log "skip '${base}': ${dst} already exists (AUTOMATED_CONVERSION_OVERWRITE_OUTPUT=0)"
                printf '%s\n' "${key}" >> "${DONE_LIST}"
                release_lock
                continue
            fi

            # -- pre-conversion hook -----------------------------------------
            HB_INPUT="${src}"
            HB_OUTPUT="${dst}"
            HB_STATUS=""
            HB_WATCH_DIR="${watch_dir}"
            if ! run_hook pre_conversion.sh "${dst}" "${src}" "${PRESET}"; then
                log "pre_conversion.sh refused '${base}' — skipping it (recorded as failed)"
                printf '%s\n' "${key}" >> "${FAILED_LIST}"
                release_lock
                continue
            fi

            CURRENT_PARTIAL="$(staging_path "${stem}.${FORMAT}")"
            rm -f -- "${CURRENT_PARTIAL}"

            log "converting '${src}' -> '${dst}'"
            started="$(date +%s)"
            processed=$(( processed + 1 ))
            if hb_run "${src}" "${CURRENT_PARTIAL}" \
               && [ -s "${CURRENT_PARTIAL}" ] \
               && finalise_output "${CURRENT_PARTIAL}" "${dst}"; then
                CURRENT_PARTIAL=""
                took=$(( $(date +%s) - started ))
                log "done '${base}' in ${took}s -> ${dst}"
                notify normal "Conversion finished" "${base} in ${took}s"
                HB_STATUS="0"
                if truthy "${AUTOMATED_CONVERSION_KEEP_SOURCE:-1}"; then
                    printf '%s\n' "${key}" >> "${DONE_LIST}"
                else
                    rm -f -- "${src}"
                    log "removed source '${src}' (AUTOMATED_CONVERSION_KEEP_SOURCE=0)"
                    unset "SEEN_KEY[${src}]" "SEEN_AT[${src}]"
                fi
            else
                rm -f -- "${CURRENT_PARTIAL}"
                CURRENT_PARTIAL=""
                printf '%s\n' "${key}" >> "${FAILED_LIST}"
                log "FAILED '${src}' — it will not be retried until the file changes."
                log "last 20 lines of ${JOB_LOG}:"
                tail -n 20 "${JOB_LOG}" || true
                notify critical "Conversion failed" "${base} — see /config/handbrake-watch.log"
                HB_STATUS="1"
            fi

            # -- post-conversion hook ----------------------------------------
            # Runs for success and failure alike, and only after the finished
            # file already reached its final path. Its exit code is ignored.
            run_hook post_conversion.sh "${HB_STATUS}" "${dst}" "${src}" "${PRESET}" || true
            release_lock
        done < <(find "${watch_dir}" -type f -print0 2>/dev/null)

        # -- per-folder hook, only after a pass that actually did something ---
        # An idle container must stay quiet, so this never fires on an empty pass.
        if [ "${processed}" -gt 0 ]; then
            HB_INPUT=""
            HB_OUTPUT=""
            HB_STATUS=""
            HB_WATCH_DIR="${watch_dir}"
            run_hook post_watch_folder_processing.sh "${watch_dir}" || true
        fi
    done
    sleep "${CHECK_INTERVAL}"
done
```

- [ ] **Step 2: Verify the whole daemon**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
bash -n rootfs/usr/local/bin/handbrake-watch.sh && echo "watch parses"
shellcheck -S warning -x -e SC1091 rootfs/usr/local/bin/handbrake-watch.sh && echo "shellcheck OK"
grep -c 'partial_path' rootfs/usr/local/bin/handbrake-watch.sh
grep -c 'release_lock' rootfs/usr/local/bin/handbrake-watch.sh
grep -c 'run_hook' rootfs/usr/local/bin/handbrake-watch.sh
```
Expected:
```
watch parses
shellcheck OK
0
5
4
```
`partial_path` must be gone entirely: `0`. `release_lock` appears on five lines — the definition, the `cleanup()` call, and the three call sites in the loop (the "already exists" skip, the hook refusal, and the end of a conversion). `run_hook` appears on four lines — the definition plus `pre_conversion.sh`, `post_conversion.sh` and `post_watch_folder_processing.sh`. A count of `3` means the per-folder hook block at the end of the `for watch_dir` body is missing.

- [ ] **Step 3: Prove the hook contract with a dry run of the hook itself**

The daemon cannot run outside the container, but the hook contract can be checked directly:

```bash
cd /d/nextcloud/it/github/handbrake
sh rootfs/defaults/hooks/pre_conversion.sh.example /output/x.mp4 /watch/x.mkv "General/Very Fast 1080p30"
sh rootfs/defaults/hooks/post_conversion.sh.example 0 /output/x.mp4 /watch/x.mkv "General/Very Fast 1080p30"
sh rootfs/defaults/hooks/hb_custom_args.sh.example /watch/x.mkv "General/Very Fast 1080p30"
```
Expected:
```
pre_conversion: /watch/x.mkv -> /output/x.mp4 (preset General/Very Fast 1080p30)
post_conversion: OK /watch/x.mkv -> /output/x.mp4
--all-subtitles
```

- [ ] **Step 4: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add rootfs/usr/local/bin/handbrake-watch.sh
git commit -m "feat: run conversion hooks, stage conversions and lock shared watch folders"
```

---

### Task 9: Notifications in the desktop session

**Files:**
- Modify: `d:\nextcloud\it\github\handbrake\rootfs\defaults\autostart`
- Test/Verify: `sh -n` parses (POSIX sh, openbox runs it with dash and ignores the shebang); shellcheck clean.

**Interfaces:**
- Consumes: `WEB_NOTIFICATION`, `/run/handbrake/session-env` (created abc-writable by Task 2), `dunst` and its config from `write_dunstrc()` (Task 2).
- Produces: `/run/handbrake/session-env` filled in with the live session's `DISPLAY` and `DBUS_SESSION_BUS_ADDRESS`, which `handbrake-notify.sh` (Task 3) reads, and a running `dunst` when notifications are enabled.

- [ ] **Step 1: Insert the session handoff and the notification daemon**

Find this exact block near the end of `rootfs/defaults/autostart`:

```sh
: > "${GUI_LOG}" 2>/dev/null || true
fast_exits=0
```

Replace it with:

```sh
: > "${GUI_LOG}" 2>/dev/null || true

# --- Session handoff ---------------------------------------------------------
# The s6-supervised watch daemon runs outside this desktop session and therefore
# has neither its DISPLAY nor its D-Bus address (startwm.sh wraps the session in
# `dbus-launch --exit-with-session`, so the bus address only exists in here).
# Hand both over through a file init-handbrake-web pre-created with abc
# ownership; handbrake-notify.sh reads it back. Single quotes because a D-Bus
# address contains "=" and "," and must survive being sourced verbatim.
{
    printf "DISPLAY='%s'\n"                  "${DISPLAY:-:1}"
    printf "DBUS_SESSION_BUS_ADDRESS='%s'\n" "${DBUS_SESSION_BUS_ADDRESS:-}"
    printf "XAUTHORITY='%s'\n"               "${XAUTHORITY:-}"
} > /run/handbrake/session-env 2>/dev/null \
    || echo "[handbrake-autostart] could not write /run/handbrake/session-env — desktop notifications will stay silent" >&2

# --- Desktop notification daemon (WEB_NOTIFICATION) --------------------------
# dunst ships in the Selkies base but nothing starts it. Its style comes from
# /config/.config/dunst/dunstrc, written by handbrake-web.sh from HANDBRAKE_THEME.
case "$(printf '%s' "${WEB_NOTIFICATION:-0}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on)
        if command -v dunst >/dev/null 2>&1; then
            if pgrep -x dunst >/dev/null 2>&1; then
                echo "[handbrake-autostart] notification daemon already running" >&2
            else
                dunst >> "${GUI_LOG}" 2>&1 &
                echo "[handbrake-autostart] notification daemon (dunst) started" >&2
            fi
        else
            echo "[handbrake-autostart] WEB_NOTIFICATION=1 but dunst is not installed — notifications disabled" >&2
        fi
        ;;
esac

fast_exits=0
```

- [ ] **Step 2: Verify**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
sh -n rootfs/defaults/autostart && echo "autostart parses"
shellcheck -S warning -x -e SC1091 rootfs/defaults/autostart && echo "shellcheck OK"
grep -c '\[\[' rootfs/defaults/autostart
```
Expected: `autostart parses`, `shellcheck OK`, and `0` — openbox executes this file with dash and ignores the shebang, so a single bashism would fail silently.

- [ ] **Step 3: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add rootfs/defaults/autostart
git commit -m "feat: publish the desktop session environment and start the notification daemon"
```

---

### Task 10: Dockerfile — ENV, `/staging`, device permissions, `chmod +x`

**Files:**
- Modify: `d:\nextcloud\it\github\handbrake\Dockerfile`
- Test/Verify: `hadolint Dockerfile --ignore DL3008 --ignore DL3009` is clean; the image builds in Task 11.

**Interfaces:**
- Consumes: every script and service created in Tasks 2-9.
- Produces: the complete env contract for Tasks 12 and 13, plus `ATTACHED_DEVICES_PERMS`, which activates the base's existing `init-device-perms`.

- [ ] **Step 1: Add `/staging` to the mount points**

Find this exact block:

```dockerfile
RUN set -eux; \
    mkdir -p /storage /watch /watch2 /watch3 /watch4 /watch5 /output; \
    chmod 0777 /watch /watch2 /watch3 /watch4 /watch5 /output
```

Replace it with:

```dockerfile
RUN set -eux; \
    mkdir -p /storage /watch /watch2 /watch3 /watch4 /watch5 /output /staging; \
    chmod 0777 /watch /watch2 /watch3 /watch4 /watch5 /output /staging
```

`/staging` is unused by default (the staging directory defaults to a hidden folder under the output root). It exists so the Unraid template can offer a path mapping for the common case of staging on a cache pool while the finished file lands on the array.

- [ ] **Step 2: Add the new executables to the `chmod +x` layer**

Find this exact block:

```dockerfile
RUN chmod +x \
    /usr/local/bin/print-banner.sh \
    /usr/local/bin/handbrake-theme.sh \
    /usr/local/bin/handbrake-gpu.sh \
    /usr/local/bin/handbrake-watch.sh \
    /etc/s6-overlay/s6-rc.d/init-nologin/run \
    /etc/s6-overlay/s6-rc.d/init-handbrake/run \
    /etc/s6-overlay/s6-rc.d/svc-handbrake-watch/run \
    /etc/s6-overlay/s6-rc.d/svc-handbrake-ready/run \
    /defaults/autostart \
    /defaults/startwm.sh
```

Replace it with:

```dockerfile
# The hook .example files are deliberately NOT here: hooks are executed with
# `/bin/sh <file>`, so they never need an executable bit, and leaving them
# non-executable is a second reminder that a template is not a live hook.
RUN chmod +x \
    /usr/local/bin/print-banner.sh \
    /usr/local/bin/handbrake-theme.sh \
    /usr/local/bin/handbrake-gpu.sh \
    /usr/local/bin/handbrake-watch.sh \
    /usr/local/bin/handbrake-web.sh \
    /usr/local/bin/handbrake-terminal.sh \
    /usr/local/bin/handbrake-notify.sh \
    /etc/s6-overlay/s6-rc.d/init-nologin/run \
    /etc/s6-overlay/s6-rc.d/init-handbrake/run \
    /etc/s6-overlay/s6-rc.d/init-handbrake-web/run \
    /etc/s6-overlay/s6-rc.d/init-handbrake-web-post/run \
    /etc/s6-overlay/s6-rc.d/svc-handbrake-watch/run \
    /etc/s6-overlay/s6-rc.d/svc-handbrake-ready/run \
    /defaults/autostart \
    /defaults/startwm.sh
```

- [ ] **Step 3: Add the new ENV block**

Find this exact line (the last line of Plan 1's `AUTOMATED_CONVERSION` block):

```dockerfile
    AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS=
```

Replace it with:

```dockerfile
    AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS=

# Staging directory for in-progress conversions. Empty resolves to a hidden
# folder under the output root (<output>/.handbrake-staging), matching what
# jlesage/handbrake does. Set it to /staging and map that to a cache pool to keep
# the array out of the write path during a transcode.
ENV AUTOMATED_CONVERSION_STAGING_DIR=

# ---------------------------------------------------------------------------
# Web-surface parity with jlesage/docker-handbrake
# ---------------------------------------------------------------------------
# Every variable here maps onto something the Selkies base ALREADY provides.
# The translation lives in /usr/local/bin/handbrake-web.sh.
#
# WEB_FILE_MANAGER               1 (default) publishes the data mounts at
#                                https://<host>:3001/files/ for browsing,
#                                download and upload; 0 removes the endpoint and
#                                the sidebar panel entirely. Defaulting to ON
#                                (jlesage defaults to OFF) adds no attack surface:
#                                anyone who can reach the WebUI already has a full
#                                desktop session with the same file access.
# WEB_FILE_MANAGER_ALLOWED_PATHS AUTO = the watch folders, the output folder and
#                                /storage, whichever of them exist. Otherwise a
#                                comma-separated list of absolute paths. /config
#                                is refused on purpose: it holds the WebUI's TLS
#                                private key at /config/ssl/cert.key.
# WEB_FILE_MANAGER_DENIED_PATHS  Comma-separated paths inside the allowed ones
#                                that must answer 403.
# WEB_TERMINAL                   0 (default) makes the base chmod every terminal
#                                binary in the image to 0000. 1 enables
#                                Ctrl+Alt+T on the web desktop. A keybind is
#                                needed because HandBrake's window is maximised
#                                and the openbox root menu cannot be reached.
# WEB_TERMINAL_SHELL_PATH        The shell that keybind opens. jlesage defaults to
#                                /bin/sh; here that is dash, with no history and
#                                no line editing, so this defaults to bash, which
#                                is also the container user's login shell.
# WEB_NOTIFICATION               1 shows conversion results on the web desktop
#                                through dunst. These are desktop notifications
#                                inside the streamed session, not browser
#                                Notification-API popups: the Selkies web client
#                                has no bridge for those.
ENV WEB_FILE_MANAGER=1 \
    WEB_FILE_MANAGER_ALLOWED_PATHS=AUTO \
    WEB_FILE_MANAGER_DENIED_PATHS= \
    WEB_TERMINAL=0 \
    WEB_TERMINAL_SHELL_PATH=/bin/bash \
    WEB_NOTIFICATION=0

# HandBrake is a transcoder, not a telephone. Audio OUT stays on (the base
# provides it and HandBrake's preview player uses it, which is why jlesage's
# WEB_AUDIO has no counterpart here), but an always-on microphone capture path
# has no use in this container and is switched off.
ENV SELKIES_MICROPHONE_ENABLED=false

# Optical drives. The LinuxServer base already carries the device-group logic in
# init-device-perms: for every path listed here it adds the container user to the
# device's owning group and chmod g+rw's the node. The base ships no default, so
# this line is the entire optical-drive wiring.
#
# /dev/sg* is deliberately NOT listed. On a NAS the generic-SCSI group owns every
# raw disk, and joining it would hand the container read access to the whole
# array for no benefit: libdvdread and libdvdnav talk to /dev/srX directly.
ENV ATTACHED_DEVICES_PERMS="/dev/sr*"
```

- [ ] **Step 4: Verify**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
hadolint Dockerfile --ignore DL3008 --ignore DL3009 && echo "hadolint clean"
grep -c '^ENV \|^    [A-Z_]*=' Dockerfile >/dev/null
grep -n 'WEB_FILE_MANAGER=\|WEB_TERMINAL=\|WEB_NOTIFICATION=\|ATTACHED_DEVICES_PERMS=\|AUTOMATED_CONVERSION_STAGING_DIR=\|SELKIES_MICROPHONE_ENABLED=' Dockerfile
grep -n '/staging' Dockerfile
grep -c 'handbrake-web.sh\|handbrake-terminal.sh\|handbrake-notify.sh' Dockerfile
```
Expected: `hadolint clean`; the six new variables each appear once; `/staging` appears twice (mkdir and chmod); and the last count is `3` (the three new scripts in the `chmod +x` layer).

- [ ] **Step 5: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add Dockerfile
git commit -m "feat: declare the web-parity, staging and optical-drive environment"
```

---

### Task 11: Local build and full manual verification

Nothing after this task may be skipped on the grounds that "CI will catch it": `build.yml` does not run on branches, so this is the only gate before the merge.

**Files:**
- Modify: none. Any defect found here is fixed in the owning task's file and this task is re-run from Step 1.

**Interfaces:**
- Consumes: everything from Tasks 2-10.
- Produces: proof that the CI assertions written in Task 12 are true, and the honest optical-drive finding the README records in Task 13.

- [ ] **Step 1: Lint everything and build**

```bash
cd /d/nextcloud/it/github/handbrake
just check
docker build -t handbrake:parity .
```
Expected: `All lint checks passed.` and a successful build. The lint chain now covers three more `*.sh` files and two more s6 `run` scripts than it did in Plan 1.

- [ ] **Step 2: Boot with the defaults and wait for READY**

```bash
docker rm -f hb-p 2>/dev/null || true
docker run -d --name hb-p -p 3000:3000 -p 3001:3001 handbrake:parity
for i in $(seq 1 240); do
  c=$(curl -k -o /dev/null -s -w '%{http_code}' --max-time 5 https://localhost:3001/ || true)
  [ -n "$c" ] && [ "$c" != "000" ] && { echo "WebUI up after ${i}s (HTTP $c)"; break; }
  sleep 1
done
docker logs hb-p 2>&1 | grep -E '\[handbrake-web\]|HANDBRAKE IS READY'
```
Expected: the WebUI answers, and the log contains lines like
```
[handbrake-web] file manager: /files/watch/ -> /watch
[handbrake-web] file manager: /files/output/ -> /output
[handbrake-web] file manager: /files/storage/ -> /storage
[handbrake-web] file manager: ON — browse /files/, uploads go to /watch
[handbrake-web] terminal: OFF (WEB_TERMINAL=0) — the base chmods every terminal binary to 0000
[handbrake-web] notifications: OFF (WEB_NOTIFICATION=0)
  ✓ HANDBRAKE IS READY
```
`/watch2`…`/watch5` also appear if those directories exist in the image, which they do.

- [ ] **Step 3: The file manager really serves the data mounts**

```bash
docker exec hb-p sh -c 'ls -l /run/handbrake/webfm; cat /run/handbrake/webfm.map'
docker exec hb-p sh -c 'grep -n "alias /run/handbrake/webfm/;" /etc/nginx/sites-available/default | wc -l'
docker exec hb-p sh -c 'echo hello > /output/parity-probe.txt'
curl -k -s https://localhost:3001/files/ | grep -o 'output' | head -1
curl -k -s https://localhost:3001/files/output/ | grep -o 'parity-probe.txt' | head -1
curl -k -s -o /dev/null -w 'download -> %{http_code}\n' https://localhost:3001/files/output/parity-probe.txt
```
Expected: the farm contains one symlink per data mount, the map lists them, the `alias` line count is `2` (one per server block), the listing shows `output`, the sub-listing shows `parity-probe.txt`, and the download returns `200`. If the alias count is `0` the pre-nginx oneshot did not run before `init-nginx` — check the `init-nginx/dependencies.d/init-handbrake-web` marker.

- [ ] **Step 4: `/config` is refused even when asked for explicitly**

```bash
docker rm -f hb-cfg 2>/dev/null || true
docker run -d --name hb-cfg -p 3010:3001 \
  -e WEB_FILE_MANAGER_ALLOWED_PATHS=/config,/output handbrake:parity >/dev/null
sleep 45
docker logs hb-cfg 2>&1 | grep -E 'REFUSED allowed path'
docker exec hb-cfg sh -c 'ls /run/handbrake/webfm'
docker rm -f hb-cfg >/dev/null
```
Expected: a `REFUSED allowed path '/config'` line mentioning the TLS private key, and the farm containing only `output`. A farm that contains `config` is a security defect — fix `FORBIDDEN_PATHS` in Task 2 before continuing.

- [ ] **Step 5: Denied paths answer 403**

```bash
docker rm -f hb-deny 2>/dev/null || true
docker run -d --name hb-deny -p 3011:3001 \
  -e WEB_FILE_MANAGER_DENIED_PATHS=/output/private handbrake:parity >/dev/null
sleep 45
docker exec hb-deny sh -c 'mkdir -p /output/private /output/publicish; echo x > /output/private/secret.txt; echo y > /output/publicish/ok.txt'
docker logs hb-deny 2>&1 | grep -E '\[handbrake-web\] denied'
curl -k -s -o /dev/null -w 'denied dir   -> %{http_code}\n' https://localhost:3011/files/output/private/
curl -k -s -o /dev/null -w 'denied file  -> %{http_code}\n' https://localhost:3011/files/output/private/secret.txt
curl -k -s -o /dev/null -w 'sibling dir  -> %{http_code}\n' https://localhost:3011/files/output/publicish/
docker rm -f hb-deny >/dev/null
```
Expected:
```
[handbrake-web] denied: /files/output/private -> 403
denied dir   -> 403
denied file  -> 403
sibling dir  -> 200
```
The sibling check matters: a prefix location written without the trailing slash would also block `/files/output/privateer`, and this proves it does not.

- [ ] **Step 6: The web terminal is off by default and works when switched on**

```bash
docker exec hb-p sh -c 'ls -l /usr/bin/xterm'
docker exec hb-p sh -c 'ls /config/.config/openbox/rc.xml 2>/dev/null || echo "no user rc.xml (correct for WEB_TERMINAL=0)"'

docker rm -f hb-term 2>/dev/null || true
docker run -d --name hb-term -p 3012:3001 -e WEB_TERMINAL=1 handbrake:parity >/dev/null
sleep 60
docker exec hb-term sh -c 'ls -l /usr/bin/xterm'
docker exec hb-term sh -c 'grep -c handbrake-terminal /config/.config/openbox/rc.xml'
docker exec hb-term sh -c 'grep -c "</keyboard>" /config/.config/openbox/rc.xml'
```
Expected: in `hb-p` the mode is `----------` (0000) and there is no user `rc.xml`; in `hb-term` the mode is `-rwxr-xr-x`, the keybind count is `1` and the `</keyboard>` count is still `1`.

- [ ] **Step 7: Open the terminal in a real browser**

Open `https://localhost:3012/` and press **Ctrl+Alt+T**. Expected: a dark xterm window opens on top of HandBrake, running bash, with a working prompt as user `abc`. Type `id` and confirm it prints `uid=911(abc)` (or the configured PUID). Close it with `exit`.

If nothing happens, check `docker logs hb-term 2>&1 | grep handbrake-web` for `terminal keybind installed`. If the line is there but the key does nothing, the browser swallowed the shortcut — confirm from a shell instead with `docker exec hb-term sh -c 'DISPLAY=:1 /usr/local/bin/handbrake-terminal.sh &'` and record the finding for the README's troubleshooting section.

```bash
docker rm -f hb-term >/dev/null
```

- [ ] **Step 8: Hooks run with the documented arguments**

```bash
docker exec hb-p sh -c 'ls /config/hooks'
docker exec hb-p sh -c 'cat > /config/hooks/pre_conversion.sh <<EOF
echo "PRE|\$1|\$2|\$3|env=\$HB_INPUT" > /config/hook-pre.txt
EOF
cat > /config/hooks/post_conversion.sh <<EOF
echo "POST|\$1|\$2|\$3|\$4" > /config/hook-post.txt
EOF
cat > /config/hooks/post_watch_folder_processing.sh <<EOF
echo "FOLDER|\$1" > /config/hook-folder.txt
EOF
chown -R abc:abc /config/hooks'
```
Expected from the first command: the four `.example` files.

- [ ] **Step 9: A real conversion through hooks, staging and the lock**

```bash
command -v ffmpeg >/dev/null || echo "install ffmpeg first"
ffmpeg -v error -y -f lavfi -i testsrc=size=320x240:rate=15:duration=2 \
       -f lavfi -i sine=frequency=440:duration=2 \
       -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest /tmp/hb-parity.mkv
docker cp /tmp/hb-parity.mkv hb-p:/watch/hb-parity.mkv
docker exec hb-p chown abc:abc /watch/hb-parity.mkv
for i in $(seq 1 180); do
  if docker exec hb-p test -s /output/hb-parity.mp4 2>/dev/null; then echo "converted after ${i}s"; break; fi
  sleep 1
done
docker exec hb-p sh -c 'cat /config/hook-pre.txt /config/hook-post.txt /config/hook-folder.txt'
docker exec hb-p sh -c 'ls -a /output; echo "--- staging ---"; ls -a /output/.handbrake-staging'
docker exec hb-p sh -c 'ls -a /watch | grep -c handbrake-lock || true'
```
Expected:
```
converted after <n>s
PRE|/output/hb-parity.mp4|/watch/hb-parity.mkv|General/Very Fast 1080p30|env=/watch/hb-parity.mkv
POST|0|/output/hb-parity.mp4|/watch/hb-parity.mkv|General/Very Fast 1080p30
FOLDER|/watch
```
`/output` contains `hb-parity.mp4`, `.handbrake-staging` and `parity-probe.txt` but **no** `*.partial` and no `*.moving`; the staging directory is empty apart from `.` and `..`; and the lock count is `0` — the lock was released.

- [ ] **Step 10: A pre-conversion hook that refuses actually blocks the file**

```bash
docker exec hb-p sh -c 'printf "exit 3\n" > /config/hooks/pre_conversion.sh; chown abc:abc /config/hooks/pre_conversion.sh'
docker cp /tmp/hb-parity.mkv hb-p:/watch/hb-refused.mkv
docker exec hb-p chown abc:abc /watch/hb-refused.mkv
sleep 25
docker logs hb-p 2>&1 | grep 'refused'
docker exec hb-p sh -c 'test -e /output/hb-refused.mp4 && echo "OUTPUT EXISTS — the refusal did not work" || echo "no output (correct)"'
docker exec hb-p sh -c 'wc -l < /config/handbrake/watch-state/failed.list'
docker exec hb-p sh -c 'rm -f /config/hooks/pre_conversion.sh'
```
Expected: a `pre_conversion.sh refused 'hb-refused.mkv'` line, `no output (correct)`, and a `failed.list` with one line.

- [ ] **Step 11: A configurable staging directory on its own mount**

```bash
docker rm -f hb-stage 2>/dev/null || true
docker run -d --name hb-stage -p 3013:3001 \
  -e AUTOMATED_CONVERSION_STAGING_DIR=/staging handbrake:parity >/dev/null
sleep 45
docker logs hb-stage 2>&1 | grep '\[handbrake-watch\] staging:'
docker cp /tmp/hb-parity.mkv hb-stage:/watch/hb-stage.mkv
docker exec hb-stage chown abc:abc /watch/hb-stage.mkv
for i in $(seq 1 180); do
  if docker exec hb-stage test -s /output/hb-stage.mp4 2>/dev/null; then echo "converted after ${i}s"; break; fi
  sleep 1
done
docker exec hb-stage sh -c 'ls -a /staging'
docker exec hb-stage sh -c 'ls -a /output'
docker rm -f hb-stage >/dev/null
```
Expected: `staging:  /staging   instance: <id>`, the conversion completes, `/staging` is empty afterwards and `/output` holds only `hb-stage.mp4` — no `.partial`, no `.moving`, and no `.handbrake-staging` directory (because the staging directory was overridden).

- [ ] **Step 12: Refuse to run on an unwritable staging directory**

```bash
docker rm -f hb-badstage 2>/dev/null || true
docker run -d --name hb-badstage \
  -e AUTOMATED_CONVERSION_STAGING_DIR=/proc/nowhere handbrake:parity >/dev/null
sleep 45
docker logs hb-badstage 2>&1 | grep -A 4 'staging directory'
docker exec hb-badstage sh -c 'pgrep -x ghb >/dev/null && echo "GUI still up (correct)"'
docker rm -f hb-badstage >/dev/null
```
Expected: the four-line loud error ending in `Refusing to convert anything until this is fixed. The GUI still works.` and `GUI still up (correct)`. A misconfiguration must be visible and must not take the GUI down with it.

- [ ] **Step 13: Notifications appear on the desktop**

```bash
docker rm -f hb-note 2>/dev/null || true
docker run -d --name hb-note -p 3014:3001 -e WEB_NOTIFICATION=1 handbrake:parity >/dev/null
sleep 60
docker exec hb-note sh -c 'cat /run/handbrake/session-env'
docker exec hb-note sh -c 'pgrep -x dunst >/dev/null && echo "dunst running"'
docker exec hb-note sh -c 'cat /config/.config/dunst/dunstrc | head -12'
```
Expected: a `session-env` with a non-empty `DISPLAY='...'` and `DBUS_SESSION_BUS_ADDRESS='unix:...'`, `dunst running`, and a dunstrc whose `frame_color` is the dark `#3d3d3d`.

Now open `https://localhost:3014/`, drop a clip in and watch for the popup:

```bash
docker cp /tmp/hb-parity.mkv hb-note:/watch/hb-note.mkv
docker exec hb-note chown abc:abc /watch/hb-note.mkv
```
Expected: within a minute a dark notification titled **Conversion finished** appears in the top-right corner of the web desktop. Take a screenshot for the README while it is on screen and save it as `.github/assets/screenshots/handbrake-notification.png`.

```bash
docker rm -f hb-note >/dev/null
```

- [ ] **Step 14: CJK fonts and clipboard tooling are present without any work of ours**

```bash
docker exec hb-p sh -c 'fc-list :lang=ja | wc -l; fc-list :lang=ko | wc -l; fc-list :lang=zh-cn | wc -l'
docker exec hb-p sh -c 'which xclip xsel wl-copy 2>/dev/null'
docker exec hb-p sh -c 'cat /run/s6/container_environment/SELKIES_MICROPHONE_ENABLED'
```
Expected: three counts greater than `0`, at least `xclip` and `xsel` resolving, and `false` for the microphone.

Then confirm CJK really renders: create a file with a CJK name and look at it in the file manager.

```bash
docker exec hb-p sh -c 'echo hi > "/output/テスト-测试-테스트.txt"'
curl -k -s https://localhost:3001/files/output/ | grep -c 'テスト'
```
Expected: `1`. Also open `https://localhost:3001/files/output/` in the browser and confirm the characters are drawn as glyphs, not as tofu boxes.

- [ ] **Step 15: Optical drive — the honest verification**

**There is no optical drive available to test against, so this step cannot and does not prove that ripping works.** What it proves is that the plumbing is wired and that its absence breaks nothing. Do not claim more than this anywhere, in the README, in the release notes or in a support reply.

```bash
# 15a) With no drive present the container must boot normally and say nothing alarming.
docker logs hb-p 2>&1 | grep -ci 'permissions for /dev/sr' || true
docker exec hb-p sh -c 'ls /dev/sr* 2>/dev/null || echo "no optical device present (expected on this machine)"'
docker exec hb-p sh -c 'pgrep -x ghb >/dev/null && pgrep -f handbrake-watch.sh >/dev/null && echo "GUI and daemon both alive with no /dev/sr0"'

# 15b) The variable really reaches the base's device-perms init.
docker exec hb-p sh -c 'cat /run/s6/container_environment/ATTACHED_DEVICES_PERMS 2>/dev/null || echo "(from image ENV)"'
docker run --rm --entrypoint sh handbrake:parity -c 'env | grep ATTACHED_DEVICES_PERMS'

# 15c) Exercise the code path with a fake device node, so we at least know the
#      group-add branch runs. This is NOT a rip test.
docker rm -f hb-sr 2>/dev/null || true
docker run -d --name hb-sr --privileged handbrake:parity >/dev/null
docker exec hb-sr sh -c 'mknod /dev/sr0 b 11 0 && chgrp cdrom /dev/sr0 && chmod 0660 /dev/sr0 && ls -l /dev/sr0'
docker restart hb-sr >/dev/null
sleep 60
docker logs hb-sr 2>&1 | grep -i 'dev/sr0' || echo "no device-perms line (the node did not survive the restart — see note)"
docker exec hb-sr sh -c 'id abc'
docker rm -f hb-sr >/dev/null

# 15d) Which disc libraries HandBrake in this image can actually use.
docker run --rm --entrypoint sh handbrake:parity -c \
  'ldd /usr/bin/HandBrakeCLI | grep -E "dvdnav|dvdread|bluray" || echo "no dynamically linked disc libraries (they may be built in statically)"'
```
Expected and how to read it:
- 15a: the grep count is `0`, `no optical device present`, and both processes alive. **This is the real assertion: absence of a drive must be a non-event.**
- 15b: `ATTACHED_DEVICES_PERMS=/dev/sr*` is present in the image environment.
- 15c: `/dev/sr0` is created inside the container. A `docker restart` recreates `/dev` from the image, so the node usually does **not** survive; if the device-perms line is absent, that is the expected outcome of this shortcut, not a defect. If it does survive, the base logs `**** adding /dev/sr0 to group cdrom ... ****` and `id abc` lists `cdrom`. Record whichever you saw.
- 15d: record the exact output verbatim for the README. Whatever it prints, it does not prove a disc can be read.

**Write down, for Task 13: "Optical-drive support is wired but UNVERIFIED — no drive was available."** Do not soften that wording.

- [ ] **Step 16: Nothing regressed from Plan 1**

```bash
docker exec hb-p cat /run/s6/container_environment/GTK_THEME; echo
p1=$(docker exec hb-p pgrep -x ghb | head -n1); sleep 20
p2=$(docker exec hb-p pgrep -x ghb | head -n1)
[ -n "$p1" ] && [ "$p1" = "$p2" ] && echo "GUI stable" || echo "GUI NOT stable"
curl -k -o /dev/null -s -w 'no login -> %{http_code}\n' https://localhost:3001/
docker logs hb-p 2>&1 | tail -n 12
```
Expected: `Adwaita:dark`, `GUI stable`, `no login -> 200`, and the tail of the log still ending on the READY block — the watch daemon must remain quiet when idle.

- [ ] **Step 17: Clean up and commit the screenshot**

```bash
docker rm -f hb-p hb-cfg hb-deny hb-term hb-stage hb-badstage hb-note hb-sr 2>/dev/null || true
rm -f /tmp/hb-parity.mkv
cd /d/nextcloud/it/github/handbrake
git add .github/assets/screenshots/handbrake-notification.png
git commit -m "docs: add the desktop notification screenshot"
```

---

### Task 12: CI feature-parity gate

**Files:**
- Modify: `d:\nextcloud\it\github\handbrake\.github\workflows\build.yml`
- Test/Verify: the YAML parses locally; the job runs green on both arches after the merge in Task 15.

**Interfaces:**
- Consumes: the image built by Plan 1's existing `Build ${{ matrix.arch }} image for the smoke gate` step (tag `handbrake:smoke-${{ matrix.arch }}`).
- Produces: a second gate that fails the build if any parity feature regresses. Plan 1's smoke step is **not** modified — this is a new, self-contained step appended after it, so the two gates cannot break each other.

- [ ] **Step 1: Insert the new step**

Find this exact line in `.github/workflows/build.yml` (the step that follows Plan 1's smoke gate):

```yaml
      # CVE scan of the locally-loaded smoke image. Report-only: exit-code 0 so
```

Insert the following **immediately before** it, at the same indentation:

```yaml
      # ---------------------------------------------------------------------
      # FEATURE-PARITY GATE. Plan 1's smoke gate proves the container boots and
      # transcodes with the DEFAULT environment. This one boots a second
      # container with the parity features switched on and proves each of them
      # actually does something: the file manager serves the data mounts, denied
      # paths answer 403, the terminal binary is unlocked and keybound, dunst
      # runs, hooks fire with the documented arguments, and the staging directory
      # is used and left clean.
      # ---------------------------------------------------------------------
      - name: Feature-parity gate — ${{ matrix.arch }}
        run: |
          set -euo pipefail
          img=handbrake:smoke-${{ matrix.arch }}
          name=hb-parity

          fail() {
            echo "::error::$1"
            echo "---- container log ----"
            docker logs "$name" 2>&1 | tail -n 150 || true
            echo "---- watch job log ----"
            docker exec "$name" cat /config/handbrake-watch.log 2>/dev/null | tail -n 60 || true
            docker rm -f "$name" >/dev/null 2>&1 || true
            exit 1
          }

          echo "== boot with the parity features on =="
          docker run -d --name "$name" \
            -p 3100:3000 -p 3101:3001 \
            -e CUSTOM_USER=parity \
            -e PASSWORD=parity-secret \
            -e WEB_TERMINAL=1 \
            -e WEB_NOTIFICATION=1 \
            -e WEB_FILE_MANAGER_DENIED_PATHS=/output/private \
            -e AUTOMATED_CONVERSION_STAGING_DIR=/staging \
            "$img"

          CURL="curl -k -s -u parity:parity-secret"

          deadline=$((SECONDS + 240))
          webui=0
          while [ "$SECONDS" -lt "$deadline" ]; do
            c=$($CURL -o /dev/null -w '%{http_code}' --max-time 5 https://localhost:3101/ || true)
            if [ -n "$c" ] && [ "$c" != "000" ]; then echo "WebUI responded after ${SECONDS}s (HTTP $c)"; webui=1; break; fi
            if [ -z "$(docker ps -q --filter "name=$name")" ]; then fail "parity container exited early"; fi
            sleep 2
          done
          [ "$webui" -eq 1 ] || fail "the parity container's WebUI did not respond within 240s"

          echo "== authentication: the house pattern, not a second variable set =="
          anon=$(curl -k -s -o /dev/null -w '%{http_code}' --max-time 10 https://localhost:3101/ || true)
          [ "$anon" = "401" ] || fail "expected 401 without credentials, got '${anon}' — CUSTOM_USER/PASSWORD did not enable basic auth"
          auth=$($CURL -o /dev/null -w '%{http_code}' --max-time 10 https://localhost:3101/ || true)
          [ "$auth" = "200" ] || fail "expected 200 with credentials, got '${auth}'"

          echo "== web file manager =="
          aliases=$(docker exec "$name" sh -c 'grep -c "alias /run/handbrake/webfm/;" /etc/nginx/sites-available/default' || echo 0)
          [ "$aliases" = "2" ] || fail "expected the farm alias in both nginx server blocks, found ${aliases} — did init-handbrake-web run before init-nginx?"
          docker exec "$name" sh -c 'test -L /run/handbrake/webfm/output && test -L /run/handbrake/webfm/watch' \
            || fail "the file-manager farm is missing the /output or /watch symlink"
          $CURL https://localhost:3101/files/ | grep -q 'output' \
            || fail "/files/ does not list the output folder"
          upload=$(docker exec "$name" cat /run/s6/container_environment/SELKIES_UPLOAD_DIR 2>/dev/null || echo "")
          [ "$upload" = "/watch" ] || fail "expected uploads to land in /watch, got '${upload}'"

          echo "== denied paths =="
          docker exec "$name" sh -c 'mkdir -p /output/private /output/publicish; echo x > /output/private/secret.txt; echo y > /output/publicish/ok.txt'
          d1=$($CURL -o /dev/null -w '%{http_code}' https://localhost:3101/files/output/private/ || true)
          d2=$($CURL -o /dev/null -w '%{http_code}' https://localhost:3101/files/output/private/secret.txt || true)
          d3=$($CURL -o /dev/null -w '%{http_code}' https://localhost:3101/files/output/publicish/ || true)
          [ "$d1" = "403" ] || fail "denied directory returned ${d1}, expected 403"
          [ "$d2" = "403" ] || fail "denied file returned ${d2}, expected 403"
          [ "$d3" = "200" ] || fail "a sibling of the denied path returned ${d3}, expected 200 — the deny location is over-matching"

          echo "== web terminal =="
          mode=$(docker exec "$name" stat -c '%A' /usr/bin/xterm)
          case "$mode" in -rwx*) : ;; *) fail "WEB_TERMINAL=1 but /usr/bin/xterm is ${mode}" ;; esac
          docker exec "$name" sh -c 'grep -q handbrake-terminal.sh /config/.config/openbox/rc.xml' \
            || fail "the Ctrl+Alt+T keybind is not in /config/.config/openbox/rc.xml"
          kb=$(docker exec "$name" sh -c 'grep -c "</keyboard>" /config/.config/openbox/rc.xml')
          [ "$kb" = "1" ] || fail "openbox rc.xml has ${kb} </keyboard> elements — the keybind insertion corrupted it"

          echo "== notifications =="
          docker exec "$name" sh -c 'pgrep -x dunst >/dev/null' || fail "WEB_NOTIFICATION=1 but dunst is not running"
          docker exec "$name" sh -c 'grep -q "^DISPLAY=" /run/handbrake/session-env' \
            || fail "/run/handbrake/session-env has no DISPLAY — the desktop session never wrote it"

          echo "== CJK fonts come from the base, no ENABLE_CJK_FONT needed =="
          cjk=$(docker exec "$name" sh -c 'fc-list :lang=ja | wc -l')
          [ "$cjk" -gt 0 ] || fail "no Japanese-capable font in the image"

          echo "== hooks + staging: one real transcode =="
          docker exec "$name" sh -c 'mkdir -p /config/hooks; cat > /config/hooks/pre_conversion.sh <<"EOF"
echo "PRE|$1|$2|$3" > /config/hook-pre.txt
EOF
cat > /config/hooks/post_conversion.sh <<"EOF"
echo "POST|$1|$2|$3|$4" > /config/hook-post.txt
EOF
cat > /config/hooks/post_watch_folder_processing.sh <<"EOF"
echo "FOLDER|$1" > /config/hook-folder.txt
EOF
chown -R abc:abc /config/hooks'

          command -v ffmpeg >/dev/null 2>&1 || { sudo apt-get update -qq && sudo apt-get install -y -qq ffmpeg; }
          ffmpeg -v error -y -f lavfi -i testsrc=size=320x240:rate=15:duration=2 \
                 -c:v libx264 -pix_fmt yuv420p /tmp/hb-parity.mkv
          docker cp /tmp/hb-parity.mkv "$name":/watch/hb-parity.mkv
          docker exec "$name" chown abc:abc /watch/hb-parity.mkv

          converted=0
          deadline=$((SECONDS + 300))
          while [ "$SECONDS" -lt "$deadline" ]; do
            if docker exec "$name" test -s /output/hb-parity.mp4 2>/dev/null; then converted=1; break; fi
            sleep 3
          done
          [ "$converted" -eq 1 ] || fail "the parity container never produced /output/hb-parity.mp4 within 300s"

          # The post-folder hook fires at the end of the pass, so give the loop
          # one more interval to come round.
          sleep 15

          docker exec "$name" sh -c 'cat /config/hook-pre.txt' | grep -q '^PRE|/output/hb-parity.mp4|/watch/hb-parity.mkv|' \
            || fail "pre_conversion.sh did not receive (output, source, preset) in that order"
          docker exec "$name" sh -c 'cat /config/hook-post.txt' | grep -q '^POST|0|/output/hb-parity.mp4|/watch/hb-parity.mkv|' \
            || fail "post_conversion.sh did not receive (status, output, source, preset) in that order"
          docker exec "$name" sh -c 'cat /config/hook-folder.txt' | grep -q '^FOLDER|/watch$' \
            || fail "post_watch_folder_processing.sh did not receive the watch folder"

          docker exec "$name" sh -c 'ls -A /staging | grep -q .' \
            && fail "the staging directory still holds files after a successful conversion"
          docker exec "$name" sh -c 'ls -a /output | grep -qE "\.partial$|\.moving$"' \
            && fail "a .partial or .moving file was left behind in /output"
          docker exec "$name" sh -c 'ls -a /watch | grep -q handbrake-lock' \
            && fail "a watch-folder lock was not released"

          echo "✅ feature-parity gate passed on ${{ matrix.arch }}"
          docker rm -f "$name" >/dev/null
```

- [ ] **Step 2: Verify the YAML parses and the step landed in the right job**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
python -c "
import yaml
d = yaml.safe_load(open('.github/workflows/build.yml'))
names = [s.get('name','') for s in d['jobs']['build']['steps']]
print('\n'.join(names))
"
```
Expected: the step list contains, in this order, `Smoke test — ${{ matrix.arch }} must boot, stay up and transcode`, then `Feature-parity gate — ${{ matrix.arch }}`, then `Scan image for CVEs (Trivy)`. If the parity gate is missing or after Trivy, the insertion anchor was wrong.

- [ ] **Step 3: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add .github/workflows/build.yml
git commit -m "ci: gate the file manager, terminal, notifications, hooks and staging"
```

---

### Task 13: README

Four edits. Sections 1-8 keep their numbers on purpose: Plan 2 rewrites section 8 (Hardware Encoding) and this plan must not move it out from under that edit.

**Files:**
- Modify: `d:\nextcloud\it\github\handbrake\README.md`
- Test/Verify: every anchor in the table of contents resolves; the page renders correctly in a clean browser.

**Interfaces:**
- Consumes: the verified behaviour from Task 11, including the honest optical-drive finding.
- Produces: the text `build.yml` mirrors to the Docker Hub description.

- [ ] **Step 1: Extend the table of contents**

Find this exact block:

````markdown
9. [Migrating from jlesage/handbrake](#9-migrating-from-jlesagehandbrake)
10. [Building Locally](#10-building-locally)
11. [Troubleshooting](#11-troubleshooting)
12. [License](#12-license)
13. [Support this project](#13-support-this-project)
````

Replace it with:

````markdown
9. [Conversion Hooks](#9-conversion-hooks)
10. [Web Desktop Features](#10-web-desktop-features)
11. [Running More Than One Instance](#11-running-more-than-one-instance)
12. [Optical Drives](#12-optical-drives)
13. [Migrating from jlesage/handbrake](#13-migrating-from-jlesagehandbrake)
14. [Building Locally](#14-building-locally)
15. [Troubleshooting](#15-troubleshooting)
16. [License](#16-license)
17. [Support this project](#17-support-this-project)
````

- [ ] **Step 2: Add the staging row to the watch-folder table and the four new sections**

Find this exact row in the Automated Watch-Folder Conversion table:

````markdown
| `AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS` | empty | Extra `HandBrakeCLI` arguments appended to every job |
````

Replace it with:

````markdown
| `AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS` | empty | Extra `HandBrakeCLI` arguments appended to every job |
| `AUTOMATED_CONVERSION_STAGING_DIR` | empty | Where in-progress conversions are written. Empty means `<output>/.handbrake-staging` |
````

Then find this exact bullet in the same section:

````markdown
- Output is written as `.<name>.<ext>.partial` and renamed only after
  `HandBrakeCLI` succeeds.
````

Replace it with:

````markdown
- Output is written into the **staging directory** and only moved to its final
  place after `HandBrakeCLI` succeeds, so a media scanner watching `/output`
  never sees a half-written file. By default the staging directory is a hidden
  folder under the output root (`<output>/.handbrake-staging`). Map `/staging`
  to a cache pool and set `AUTOMATED_CONVERSION_STAGING_DIR=/staging` to keep the
  array out of the write path while a transcode runs. When staging and output are
  on different filesystems the finished file is copied to a hidden sibling inside
  the output folder first and then renamed, so the last step stays atomic.
- If the staging directory cannot be written, the daemon says so loudly and
  refuses to convert anything instead of failing every file one by one. The GUI
  keeps working.
````

- [ ] **Step 3: Insert the four new sections**

Find this exact line (the start of the old section 9):

````markdown
## 9. Migrating from jlesage/handbrake
````

Replace it with the following, which inserts sections 9-12 and renumbers this one to 13:

````markdown
## 9. Conversion Hooks

Drop a shell script into `/config/hooks/` and the watch-folder daemon runs it at
the matching point. The folder is created on first start and always contains an
up-to-date `.example` for each hook; copy one and remove the `.example` suffix to
enable it. Hooks are executed with `/bin/sh` and their shebang is ignored, which
is the same contract `jlesage/handbrake` uses, so scripts written for that image
work here unchanged.

| Hook | When | Arguments |
|---|---|---|
| `pre_conversion.sh` | Before `HandBrakeCLI` starts on a file | `$1` output file, `$2` source file, `$3` preset |
| `post_conversion.sh` | After every attempt, once the file has reached its final path | `$1` status (`0` = success), `$2` output file, `$3` source file, `$4` preset |
| `post_watch_folder_processing.sh` | End of a scan pass that converted at least one file | `$1` watch folder |
| `hb_custom_args.sh` | Just before `HandBrakeCLI`, to add per-file arguments | `$1` source file, `$2` preset. Print the arguments on stdout |

The same values are also in the environment, which is usually easier to read:
`HB_INPUT`, `HB_OUTPUT`, `HB_STATUS`, `HB_PRESET`, `HB_FORMAT`, `HB_WATCH_DIR`.

Two behaviours worth knowing:

- **A non-zero exit from `pre_conversion.sh` refuses the file.** The conversion
  is skipped and the source is recorded in `failed.list`, so it is not retried
  until the file itself changes. Every other hook's exit code is logged and
  otherwise ignored.
- `hb_custom_args.sh` output is appended **after**
  `AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS`, so where both set the same flag
  the hook wins.

Everything a hook prints goes to `/config/handbrake-watch.log`.

<br>

## 10. Web Desktop Features

Most of what other HandBrake images expose through their own variables comes
straight from the Selkies desktop and needs no configuration at all.

| Variable | Default | Description |
|---|---|---|
| `WEB_FILE_MANAGER` | `1` | Serves the data folders at `https://<host>:3001/files/` for browsing, download and upload. `0` removes the endpoint and the sidebar panel |
| `WEB_FILE_MANAGER_ALLOWED_PATHS` | `AUTO` | `AUTO` publishes the watch folders, the output folder and `/storage`, whichever exist. Otherwise a comma-separated list of absolute paths |
| `WEB_FILE_MANAGER_DENIED_PATHS` | empty | Comma-separated paths inside the allowed ones that answer `403` |
| `WEB_TERMINAL` | `0` | `1` enables a terminal on the web desktop with **Ctrl+Alt+T**. `0` disables every terminal program in the container |
| `WEB_TERMINAL_SHELL_PATH` | `/bin/bash` | The shell that terminal opens |
| `WEB_NOTIFICATION` | `0` | `1` shows a popup on the web desktop when a conversion finishes or fails |

**File manager.** Upload a video in the browser and it lands in `/watch`, where
the watch-folder daemon picks it up; browse `/output` and download the result
without touching a share. `/config` is refused as an allowed path even if you ask
for it explicitly, because it holds the WebUI's TLS private key. If you expose
this container beyond your LAN, set `CUSTOM_USER` and `PASSWORD`.

**Terminal.** A keyboard shortcut rather than a separate web page: HandBrake's
window is maximised, so the desktop's right-click menu cannot be reached. The
terminal is a real window on the same desktop, streamed like everything else.

**Notifications** are shown by the desktop itself, in the corner of the HandBrake
tab. They are not browser or operating-system notifications, so you see them
while the tab is open rather than in the background. Their colours follow
`HANDBRAKE_THEME`.

**Clipboard** works in both directions out of the box, no variable required. It
needs the HTTPS port (`3001`): browsers only allow clipboard access on a secure
origin. Firefox additionally blocks the silent clipboard read the web client uses
on focus, which can lower-case pasted capitals; set
`dom.events.testing.asyncClipboard` to `true` in `about:config` if you hit that.

**Audio** works out of the box as well, so there is no variable for it. The
microphone path is switched off, since a transcoder has no use for one.

**CJK fonts** (Japanese, Korean, Chinese) are always installed. Nothing to enable,
and filenames or subtitle tracks in those scripts render correctly everywhere in
the UI.

**HTTPS** is always available on port `3001` with a self-signed certificate that
is generated on first start and kept in `/config/ssl`.

**Login** is off by default and switched on by setting `CUSTOM_USER` and
`PASSWORD`, which is the same pattern every container in this fleet uses.

<br>

## 11. Running More Than One Instance

Two independent containers, each with its own `/config`, watch folder and output
folder, need nothing special: no path outside `/config`, `/watch*`, `/output` and
`/staging` is shared, and everything else the container writes lives in its own
`/run`.

Two containers **sharing one watch folder** to convert twice as many files at
once also works. Each file is claimed with a lock directory in the watch folder,
so exactly one container converts it. Some ground rules:

- The watch folder must be **writable** by both containers. If it is read-only,
  locking is off, the log says so, and you must not point a second instance at it.
- Give each container its own `/config`. The conversion bookkeeping is per
  container; the lock is what keeps them from colliding.
- If both containers share one output folder, leave
  `AUTOMATED_CONVERSION_OVERWRITE_OUTPUT=0` (the default). A file the other
  container already converted is then simply skipped.
- Sharing one staging directory is fine. Every in-progress file carries the
  container's own tag, and on restart a container only cleans up its own
  leftovers.
- If a container is killed hard, its lock is cleared automatically the next time
  it starts. To clear one by hand: `rm -rf /path/to/watch/.handbrake-lock-*` while
  no conversion is running.

<br>

## 12. Optical Drives

> **Unverified.** The device plumbing is wired and the container is proven to run
> correctly when no drive is present, but no optical drive was available to test
> ripping end to end. Treat this section as best effort until somebody reports
> back. Reports very welcome.

Pass the drive in and HandBrake can use it as a source:

```sh
docker run -d \
  --name=handbrake \
  --device /dev/sr0 \
  -p 3000:3000 \
  -p 3001:3001 \
  -e PUID=99 \
  -e PGID=100 \
  -v /mnt/user/appdata/handbrake:/config \
  -v /mnt/user/media/converted:/output \
  --restart unless-stopped \
  ghcr.io/junkerderprovinz/handbrake:latest
```

In Unraid, add `--device /dev/sr0` under **Extra Parameters**. The container adds
itself to the group that owns the device automatically, so no permission changes
on the host should be needed. Open the drive from the GUI with **Open Source**
and browse to `/dev/sr0`.

ISO images, DVD folders containing `VIDEO_TS` and Blu-ray folders containing
`BDMV` also work as ordinary sources, and `.iso` files dropped into a watch
folder are picked up by the automatic converter like any other video.

Commercially encrypted DVDs are **not** supported: the container ships no
decryption library, and adding one is out of scope for this image.

<br>

## 13. Migrating from jlesage/handbrake
````

- [ ] **Step 4: Rewrite the migration section and renumber the tail**

Find this exact block (the body of the old section 9 plus the four headings after it):

````markdown
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
````

Replace it with:

````markdown
- Ports change: `5800`/`5900` become `3000` (HTTP) and `3001` (HTTPS). There is
  no direct VNC port — Selkies is the only access path, by design.
- All `AUTOMATED_CONVERSION*` variables keep their names and defaults, so you can
  copy those values over unchanged.
- `/config/hooks/` keeps its name and its argument order, so existing hook
  scripts work without edits.
- `/config`, `/storage`, `/watch` and `/output` keep their meaning, but the
  `/config` contents are not compatible: start with a fresh appdata folder and
  re-import your custom presets from the GUI.

Variables that changed, and why:

| jlesage | Here | Note |
|---|---|---|
| `USER_ID` / `GROUP_ID` | `PUID` / `PGID` | The LinuxServer convention this image is built on |
| `DARK_MODE=1` | `HANDBRAKE_THEME=dark` | Already the default |
| `WEB_AUTHENTICATION`, `_USERNAME`, `_PASSWORD` | `CUSTOM_USER`, `PASSWORD` | HTTP basic auth on the WebUI. `WEB_AUTHENTICATION_TOKEN_VALIDITY_TIME` has no counterpart: basic auth has no token to expire |
| `SECURE_CONNECTION=1` | (none) | HTTPS on port `3001` is always available |
| `WEB_HOST_CLIPBOARD_SYNC` | (none) | Clipboard sync is always on |
| `WEB_AUDIO` | (none) | Browser audio is always on. The microphone is off, which a transcoder has no use for |
| `ENABLE_CJK_FONT` | (none) | CJK fonts are always installed |
| `KEEP_APP_RUNNING` | (none) | The GUI is always restarted if it exits |
| `WEB_FILE_MANAGER*`, `WEB_TERMINAL*`, `WEB_NOTIFICATION` | same names | See [Web Desktop Features](#10-web-desktop-features). `WEB_FILE_MANAGER` defaults to `1` here, and `WEB_NOTIFICATION` shows its popups on the web desktop rather than as browser notifications |
| `VNC_PASSWORD`, `VNC_LISTENING_PORT`, `SECURE_CONNECTION_VNC_METHOD` | (none) | There is no VNC port |
| `AUTOMATED_CONVERSION_USE_TRASH`, `_TRASH_DIR` | (none) | Not implemented. `AUTOMATED_CONVERSION_KEEP_SOURCE=1` (the default) never deletes a source |
| `AUTOMATED_CONVERSION_NON_VIDEO_FILE_ACTION`, `_NON_VIDEO_FILE_EXTENSIONS` | (none) | Not implemented. Non-video files in a watch folder are ignored |
| `AUTOMATED_CONVERSION_SOURCE_MIN_DURATION`, `_SOURCE_MAIN_TITLE_DETECTION` | (none) | Not implemented. Disc sources convert their first title |
| `AUTOMATED_CONVERSION_NO_GUI_PROGRESS` | (none) | The watch daemon never draws in the GUI, so there is nothing to hide |
| `INSTALL_PACKAGES`, `PACKAGES_MIRROR` | (none) | Build a derived image instead |

<br>

## 14. Building Locally
````

Then renumber the remaining three headings. Find and replace each of these exact lines:

| Find | Replace with |
|---|---|
| `## 11. Troubleshooting` | `## 15. Troubleshooting` |
| `## 12. License` | `## 16. License` |
| `## 13. Support this project` | `## 17. Support this project` |

- [ ] **Step 5: Add the new troubleshooting entries**

Find this exact block at the end of the troubleshooting section:

````markdown
**Which image am I actually running?**

```sh
docker exec handbrake cat /etc/handbrake-build
```
````

Replace it with:

````markdown
**`/files/` is empty or returns 404.** Check the startup log:
`docker logs handbrake 2>&1 | grep handbrake-web`. Every published folder is
listed there as `/files/<name>/ -> <path>`. A folder that is not mounted is not
published. If a path was refused, the log says why.

**A conversion never starts and the log mentions the staging directory.** The
staging directory is not writable. Fix the owner of the mapped host folder
(`chown nobody:users /mnt/user/<share>`) or point
`AUTOMATED_CONVERSION_STAGING_DIR` somewhere writable.

**Ctrl+Alt+T does nothing.** Confirm `WEB_TERMINAL=1` and look for
`terminal keybind installed` in `docker logs handbrake`. Some browser extensions
capture the shortcut before the page sees it; try another browser or a private
window.

**A file in a shared watch folder is never converted.** A lock left behind by a
container that no longer exists blocks it. With no conversion running:

```sh
rm -rf /mnt/user/<watch-share>/.handbrake-lock-*
```

**A hook does not run.** It must be at `/config/hooks/<name>.sh` without the
`.example` suffix, and readable by the container user. Its output and any error
are in `/config/handbrake-watch.log`.

**Which image am I actually running?**

```sh
docker exec handbrake cat /etc/handbrake-build
```
````

- [ ] **Step 6: Update the comparison table in the overview**

Find this exact row:

````markdown
| File upload via WebUI | ✅ | ❌ |
````

Replace it with:

````markdown
| File upload via WebUI | ✅ | ❌ |
| Web file manager | ✅ on by default | opt-in via `WEB_FILE_MANAGER=1` |
| Conversion hooks | ✅ | ✅ |
| Staging on a separate disk | ✅ configurable | ❌ fixed under the output folder |
| Shared-watch-folder locking | ✅ | ✅ |
| CJK fonts | ✅ always | opt-in via `ENABLE_CJK_FONT=1` |
````

- [ ] **Step 7: Verify**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
grep -nE '^## [0-9]+\. ' README.md
grep -nE '^\| `AUTOMATED_CONVERSION_STAGING_DIR`|^\| `WEB_FILE_MANAGER`|^\| `WEB_TERMINAL`|^\| `WEB_NOTIFICATION`' README.md
python - <<'PY'
import re
md = open('README.md', encoding='utf-8').read()
heads = re.findall(r'^## (\d+)\. (.+)$', md, re.M)
def slug(n, t):
    s = t.lower().replace(' ', '-')
    s = re.sub(r'[^a-z0-9-]', '', s)
    return f'#{n}-{s}'
have = {slug(n, t) for n, t in heads}
want = set(re.findall(r'\]\((#\d+-[a-z0-9-]+)\)', md))
missing = sorted(want - have)
print('headings:', len(heads))
print('broken anchors:', missing if missing else 'none')
PY
```
Expected: seventeen headings numbered `1.` to `17.` with no gaps and no duplicates, the four new variable rows present, `headings: 17`, and `broken anchors: none`.

- [ ] **Step 8: Look at the rendered page**

Push the branch and open
`https://github.com/junkerderprovinz/handbrake/blob/feat/feature-parity/README.md`
in a clean browser profile (not a preview pane).

```bash
cd /d/nextcloud/it/github/handbrake
git add README.md
git commit -m "docs: document the web desktop features, hooks, staging, multi-instance and optical drives"
git push -u origin feat/feature-parity
```
Expected: the banner, badges and both new screenshots render; every table-of-contents link jumps to the right section; the optical-drive warning block is visible as a blockquote.

---

### Task 14: `CLAUDE.md` and `justfile`

**Files:**
- Modify: `d:\nextcloud\it\github\handbrake\CLAUDE.md`
- Modify: `d:\nextcloud\it\github\handbrake\justfile`
- Test/Verify: `just --list` shows the new recipe; `just check` still passes.

**Interfaces:**
- Consumes: everything above.
- Produces: the repo guide a future agent reads before touching any of this, and a one-command local parity check.

- [ ] **Step 1: Extend the layout section of `CLAUDE.md`**

Find this exact block:

````markdown
    Services: `init-nologin`, `init-handbrake` (oneshots),
    `svc-handbrake-watch`, `svc-handbrake-ready` (longruns).
  - `rootfs/usr/local/bin/` — `handbrake-theme.sh`, `handbrake-gpu.sh`,
    `handbrake-watch.sh`, `print-banner.sh`.
  - `rootfs/defaults/` — `autostart` (openbox session, POSIX sh only) and
    `startwm.sh`.
````

Replace it with:

````markdown
    Services: `init-nologin`, `init-handbrake`, `init-handbrake-web`,
    `init-handbrake-web-post` (oneshots), `svc-handbrake-watch`,
    `svc-handbrake-ready` (longruns).
  - `rootfs/usr/local/bin/` — `handbrake-theme.sh`, `handbrake-gpu.sh`,
    `handbrake-watch.sh`, `handbrake-web.sh`, `handbrake-terminal.sh`,
    `handbrake-notify.sh`, `print-banner.sh`.
  - `rootfs/defaults/` — `autostart` (openbox session, POSIX sh only),
    `startwm.sh`, and `hooks/*.example` (the conversion-hook templates copied to
    `/config/hooks` on every start).
````

- [ ] **Step 2: Add the new gotchas**

Find this exact bullet in the "Conventions / gotchas" section:

````markdown
- **GPU support lives in `handbrake-gpu.sh` only.** It resolves `GPU_VENDOR` into
````

Insert the following **immediately before** it:

````markdown
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
````

- [ ] **Step 3: Add the parity recipe to the `justfile`**

Find this exact recipe:

````makefile
# End-to-end watch-folder test against a running `just smoke` container
convert-test:
    ffmpeg -v error -y -f lavfi -i testsrc=size=320x240:rate=15:duration=2 -c:v libx264 -pix_fmt yuv420p /tmp/hb-smoke.mkv
    docker cp /tmp/hb-smoke.mkv hb-smoke:/watch/hb-smoke.mkv
    docker exec hb-smoke chown abc:abc /watch/hb-smoke.mkv
    @echo "dropped /watch/hb-smoke.mkv — watch: docker logs -f hb-smoke"
````

Replace it with:

````makefile
# End-to-end watch-folder test against a running `just smoke` container
convert-test:
    ffmpeg -v error -y -f lavfi -i testsrc=size=320x240:rate=15:duration=2 -c:v libx264 -pix_fmt yuv420p /tmp/hb-smoke.mkv
    docker cp /tmp/hb-smoke.mkv hb-smoke:/watch/hb-smoke.mkv
    docker exec hb-smoke chown abc:abc /watch/hb-smoke.mkv
    @echo "dropped /watch/hb-smoke.mkv — watch: docker logs -f hb-smoke"

# Boot a throwaway container with every parity feature on (WebUI on 3101/HTTPS,
# user parity / parity-secret). Mirrors the CI feature-parity gate.
parity: build
    -docker rm -f hb-parity
    docker run -d --name hb-parity -p 3100:3000 -p 3101:3001 \
      -e CUSTOM_USER=parity -e PASSWORD=parity-secret \
      -e WEB_TERMINAL=1 -e WEB_NOTIFICATION=1 \
      -e WEB_FILE_MANAGER_DENIED_PATHS=/output/private \
      -e AUTOMATED_CONVERSION_STAGING_DIR=/staging \
      handbrake:smoke-amd64
    @echo "https://localhost:3101/  (parity / parity-secret) — stop with: docker rm -f hb-parity"

# Assert the parity surface of a running `just parity` container
parity-check:
    curl -k -s -o /dev/null -w 'anonymous      -> %{http_code}\n' https://localhost:3101/
    curl -k -s -u parity:parity-secret -o /dev/null -w 'authenticated  -> %{http_code}\n' https://localhost:3101/
    curl -k -s -u parity:parity-secret -o /dev/null -w 'file manager   -> %{http_code}\n' https://localhost:3101/files/
    docker exec hb-parity sh -c 'stat -c "xterm %A" /usr/bin/xterm; pgrep -x dunst >/dev/null && echo "dunst running"; grep -c handbrake-terminal /config/.config/openbox/rc.xml | sed "s/^/keybinds /"'
    @echo "expected: 401, 200, 200, xterm -rwxr-xr-x, dunst running, keybinds 1"
````

- [ ] **Step 4: Verify**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
just --list
just check
```
Expected: the recipe list includes `parity` and `parity-check`, and `just check` ends with `All lint checks passed.`

- [ ] **Step 5: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add CLAUDE.md justfile
git commit -m "docs: record the web translation layer conventions and add the parity recipes"
```

---

### Task 15: Merge, CI, release notes and the gated tag

**Files:**
- Create: `d:\nextcloud\it\github\handbrake\.github\release-notes\v1.3.0.md`
- Test/Verify: `Lint` and `Build & Push` green on `main` for both arches, including the new feature-parity gate.

**Interfaces:**
- Consumes: everything above.
- Produces: `ghcr.io/junkerderprovinz/handbrake:1.3.0` / `:1.3` / `:1` / `:latest` and the GitHub release `v1.3.0` — **after approval only**.

- [ ] **Step 1: Confirm the version number before writing anything**

```bash
cd /d/nextcloud/it/github/handbrake
git fetch origin --tags
git tag --list 'v*.*.*' --sort=-v:refname | head -n 3
```
Expected: `v1.2.0`, `v1.1.0`, `v1.0.0`, which makes this release `v1.3.0`. If the newest tag is different, this release is the next **minor** after it (`v1.<latest minor + 1>.0`), and every `v1.3.0` below refers to that number instead. If the newest tag is already `v1.3.0` or higher, stop and report — a plan was executed out of order.

- [ ] **Step 2: Merge to `main`**

```bash
cd /d/nextcloud/it/github/handbrake
git checkout main
git pull --rebase origin main
git merge --no-ff feat/feature-parity -m "feat: close the remaining feature-parity gap with jlesage/handbrake"
git push origin main
```

- [ ] **Step 3: Watch both workflows and read the parity gate's output**

```bash
cd /d/nextcloud/it/github/handbrake
gh run watch "$(gh run list --workflow=lint.yml  --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
gh run watch "$(gh run list --workflow=build.yml --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
```
Expected: both conclude `success`, and each of the `amd64` and `arm64` build jobs shows
```
✅ smoke gate passed on <arch>
✅ feature-parity gate passed on <arch>
```
If a gate fails, fix the cause in the owning task's file, push to `main`, and re-run this step. Never disable a gate to get green.

- [ ] **Step 4: Delete the merged branch**

```bash
cd /d/nextcloud/it/github/handbrake
git branch -d feat/feature-parity
git push origin --delete feat/feature-parity
```

- [ ] **Step 5: Write the release notes**

`d:\nextcloud\it\github\handbrake\.github\release-notes\v1.3.0.md`:

```markdown
Everything the community image does that this one did not yet: a file manager and a terminal in the browser, conversion hooks, a staging folder you can put on a fast disk, and two containers can now share one watch folder without fighting over the same file.

## ✨ Added

- **File manager in the browser.** The watch folders, the output folder and `/storage` are served at `https://<host>:3001/files/` for browsing and download, and anything you upload from the sidebar lands in `/watch`, where it is converted automatically. On by default; `WEB_FILE_MANAGER_ALLOWED_PATHS` picks the folders and `WEB_FILE_MANAGER_DENIED_PATHS` blocks anything inside them that should stay private. The config folder is refused as a published path even if you ask for it, because it holds the WebUI's TLS private key.
- **Terminal on the web desktop.** `WEB_TERMINAL=1` opens a shell with Ctrl+Alt+T, themed to match the rest of the UI, with `WEB_TERMINAL_SHELL_PATH` choosing the shell. Off by default, and when it is off every terminal program in the container is disabled rather than merely hidden.
- **Conversion hooks.** Drop a script into `/config/hooks/` and it runs before a conversion, after one, at the end of a watch-folder pass, or to add per-file HandBrake arguments. Same file names and same argument order as the community image, so existing hook scripts work unchanged, and a commented example for each one is created for you on first start. A pre-conversion hook that exits non-zero refuses the file.
- **Configurable staging folder.** In-progress conversions are written to a staging folder and only moved to their final place when HandBrake reports success. Point `AUTOMATED_CONVERSION_STAGING_DIR` at a cache pool to keep the array out of the write path during a transcode; the finished file still arrives in one atomic step even when the two are on different disks.
- **Two containers, one watch folder.** Each file is claimed with a lock, so a second instance pointed at the same folder doubles throughput instead of converting the same video twice. A container that was killed hard clears its own leftover locks when it starts again.
- **Desktop notifications.** `WEB_NOTIFICATION=1` shows a popup on the web desktop when a conversion finishes or fails, in the colours of the current theme.
- **Optical drive plumbing.** Pass `--device /dev/sr0` and the container joins the drive's group on its own. Wired but not yet verified against real hardware, and the README says so plainly.

## ⚡ Improved

- Clipboard sync, browser audio, HTTPS, the login and CJK fonts turned out to need no work at all: the desktop already provides every one of them, so they have no variables here and simply always work. The README's migration table maps each of the community image's variables to what replaces it.
- The microphone is switched off. A video transcoder has no use for one, and it was capturing by default.
- A staging folder that cannot be written now says so once, loudly, and stops, instead of failing every single file in silence. The GUI keeps working.

## 🐛 Fixed

- Uploads from the browser sidebar landed in a folder nobody could see. They now go to the watch folder, so an uploaded video is converted straight away.
```

- [ ] **Step 6: Sanity-check the notes against the house rules**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
grep -nE '^#[^#]' .github/release-notes/v1.3.0.md && echo "H1 FOUND — remove it" || echo "no H1 heading (correct)"
grep -nE '^## ' .github/release-notes/v1.3.0.md
grep -nE 'v?1\.3\.0' .github/release-notes/v1.3.0.md && echo "VERSION IN BODY — remove it" || echo "no version heading in the body (correct)"
grep -n '—' .github/release-notes/v1.3.0.md | head
```
Expected: `no H1 heading (correct)`, exactly the three category headings `## ✨ Added`, `## ⚡ Improved`, `## 🐛 Fixed`, `no version heading in the body (correct)`, and no em dashes (release notes are GitHub prose).

- [ ] **Step 7: Commit and push the notes**

```bash
cd /d/nextcloud/it/github/handbrake
git add .github/release-notes/v1.3.0.md
git commit -m "docs: add the v1.3.0 release notes"
git push origin main
```

- [ ] **Step 8: STOP — ask for approval before tagging**

Do not run Step 9 until jdp has explicitly approved cutting `v1.3.0`. Report:
- both workflows green on both arches, with the parity gate passing,
- the manual verification results from Task 11, **including that optical-drive support is wired but unverified because no drive was available**,
- the one behaviour change a user will notice: the web file manager is on by default and now publishes the watch and output folders. Anyone whose container is reachable beyond their LAN should set `CUSTOM_USER` and `PASSWORD`.

Then ask.

- [ ] **Step 9: Tag the release (only after approval)**

```bash
cd /d/nextcloud/it/github/handbrake
git fetch origin && git pull --rebase origin main
git tag v1.3.0
git push origin v1.3.0
gh run watch "$(gh run list --workflow=release.yml --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
gh release view v1.3.0
```
Expected: the release title is exactly `v1.3.0`, the body is the notes file, and the tag build publishes `:1.3.0`, `:1.3`, `:1` and `:latest`.

- [ ] **Step 10: Verify the published manifest**

```bash
docker buildx imagetools inspect ghcr.io/junkerderprovinz/handbrake:1.3.0
```
Expected: a manifest list with `linux/amd64` and `linux/arm64`.

---

### Task 16: Follow-ups outside this repo

House requirements, not optional. Do these in the same session as the release.

**Files:**
- Modify: files in `d:\nextcloud\it\github\unraid-apps` and the Obsidian vault. Nothing in this repo.

**Interfaces:**
- Consumes: the released `v1.3.0` image and its environment contract.
- Produces: a Community Applications template that actually exposes the new settings, and the vault record.

- [ ] **Step 1: Add the new settings to the Unraid template**

The template lives in the central feed repo, not here. Add one `<Config>` element per new variable to `d:\nextcloud\it\github\unraid-apps\handbrake\handbrake.xml`, following the existing entries' shape:

| Name | Target | Type | Default | Notes |
|---|---|---|---|---|
| Web file manager | `WEB_FILE_MANAGER` | Variable | `1` | fixed-option dropdown, `1` / `0` |
| File manager: allowed paths | `WEB_FILE_MANAGER_ALLOWED_PATHS` | Variable | `AUTO` | advanced |
| File manager: denied paths | `WEB_FILE_MANAGER_DENIED_PATHS` | Variable | (empty) | advanced |
| Web terminal | `WEB_TERMINAL` | Variable | `0` | fixed-option dropdown, `1` / `0` |
| Web terminal shell | `WEB_TERMINAL_SHELL_PATH` | Variable | `/bin/bash` | advanced |
| Desktop notifications | `WEB_NOTIFICATION` | Variable | `0` | fixed-option dropdown, `1` / `0` |
| Staging folder | `AUTOMATED_CONVERSION_STAGING_DIR` | Variable | (empty) | advanced |
| Staging | `/staging` | Path | (empty) | rw, advanced. Point it at a cache pool, then set the variable above to `/staging` |

Two house rules apply and are easy to get wrong:
- A fixed-option field's values are pipe-separated in the `Default` attribute; a plain text field's are not.
- Leaving a template field blank **overwrites** the image's `ENV` default with an empty string. Every field above whose image default is non-empty (`WEB_FILE_MANAGER`, `WEB_FILE_MANAGER_ALLOWED_PATHS`, `WEB_TERMINAL`, `WEB_TERMINAL_SHELL_PATH`, `WEB_NOTIFICATION`) must therefore carry that same default in the template, not an empty value.

Validate and hand the file to jdp as importable XML:
```bash
xmllint --noout /d/nextcloud/it/github/unraid-apps/handbrake/handbrake.xml && echo "template XML OK"
```

- [ ] **Step 2: Mirror the change into the Obsidian vault**

Update the PascalCase repo note for HandBrake under `02 Projekte` with the new feature surface, and add a dated changelog entry describing this release.

- [ ] **Step 3: Check the other repos for the same drift**

`jdownloader` and `krusader` sit on the same base and neither sets `FILE_MANAGER_PATH` or `SELKIES_UPLOAD_DIR`, so their file manager still serves the empty `/config/Desktop` and their uploads still land somewhere invisible. That is the same defect this plan fixed here. Raise it as an issue on each repo rather than fixing it silently in passing:

```bash
gh issue create --repo junkerderprovinz/krusader \
  --title "File manager serves an empty folder and uploads are invisible" \
  --body "The Selkies base defaults FILE_MANAGER_PATH to /config/Desktop and never sets SELKIES_UPLOAD_DIR, so the /files/ endpoint lists an empty directory and sidebar uploads land where the browser cannot see them. handbrake v1.3.0 fixes this by pointing both at the container's real data mounts. Same fix applies here."
gh issue create --repo junkerderprovinz/jdownloader \
  --title "File manager serves an empty folder and uploads are invisible" \
  --body "The Selkies base defaults FILE_MANAGER_PATH to /config/Desktop and never sets SELKIES_UPLOAD_DIR, so the /files/ endpoint lists an empty directory and sidebar uploads land where the browser cannot see them. handbrake v1.3.0 fixes this by pointing both at the container's real data mounts. Same fix applies here."
```

Also note the contradiction found while researching this plan, and settle it in one pass across all three READMEs: `krusader/README.md` says port 3000 is not usable directly, while `jdownloader/README.md` says it works as a fallback without clipboard support. Only one can be right. Test it and make all three repos say the same thing.

---

## Deliberately out of scope

Named here so nothing is silently dropped. None of these appear in the design
spec's Feature Parity Checklist, and each is a separate, self-contained piece of
work if it is ever wanted:

- `AUTOMATED_CONVERSION_USE_TRASH` and `_TRASH_DIR`. Plan 1's handoff listed them
  as free for this plan, but the spec's checklist stops at "keep-source toggle",
  which Plan 1 already implements. With the default `AUTOMATED_CONVERSION_KEEP_SOURCE=1`
  nothing is ever deleted, so there is nothing to rescue into a trash folder.
- `AUTOMATED_CONVERSION_NON_VIDEO_FILE_ACTION` and `_NON_VIDEO_FILE_EXTENSIONS`
  (copying subtitle and artwork files alongside the conversion).
- `AUTOMATED_CONVERSION_SOURCE_MIN_DURATION` and `_SOURCE_MAIN_TITLE_DETECTION`.
  These matter for disc and ISO sources, which are adjacent to the optical-drive
  task, but they need a working disc source to develop against and there is none.
  Revisit them together with the optical-drive verification.
- `AUTOMATED_CONVERSION_NO_GUI_PROGRESS`. The watch daemon here is a separate
  process that never draws in the GUI, so there is no progress to hide.
- `HANDBRAKE_GUI=0`. The spec calls the GUI toggle not applicable: this image
  exists to put the GUI in a browser.
- `INSTALL_PACKAGES` / `PACKAGES_MIRROR`. Installing arbitrary packages at
  container start is not a pattern this fleet uses.
- Browser Notification-API popups. Covered in Task 3's header comment: the
  Selkies web client has no bridge, and building one means forking
  `/usr/share/selkies/web`, which the base recreates on every start.
- `START_DOCKER=false`. The base runs a docker daemon inside the container that
  this image has no use for, but that is a fleet-wide question affecting
  `jdownloader` and `krusader` identically, not a HandBrake parity item.

---

## Self-review checklist

Run this before declaring the plan finished — it is the same list the plan author
already walked.

- [ ] No `TBD`, `TODO`, `FIXME`, "similar to Task N", or "add appropriate error handling" anywhere in this document.
- [ ] Every spec Feature Parity Checklist item in this plan's scope is accounted for:
  - Web file manager (allowed/denied paths) — Tasks 2, 4, 10, 11, 12, 13. **Base provides one fixed path; the multi-path farm and the deny locations are new.**
  - Web terminal — Tasks 2, 3, 4, 10, 11, 12, 13. **Base provides the binaries and the off-switch; the keybind and the shell selection are new.**
  - Web notifications — Tasks 2, 3, 9, 10, 11, 12, 13. **Base provides dunst but never starts it; scope difference from jlesage documented in Task 3 and in the README.**
  - Web audio passthrough — **already satisfied by the base, verification only** (Task 1 Step 7), variable explicitly dropped (Task 10 Step 3, README section 10 and the migration table).
  - Host clipboard sync — **already satisfied by the base, verification only** (Task 1 Step 7), variable explicitly dropped, Firefox caveat documented (README section 10).
  - Web authentication — **already satisfied by Plan 1's house pattern, verification only** (Task 1 Step 9, CI in Task 12). No parallel jlesage-named variable added; the mapping is in the README migration table.
  - Secure connection — **already satisfied by the base**, already in Plan 1's README.
  - CJK font installation — **already satisfied by the base, unconditional, verification only** (Task 1 Step 8, Task 11 Step 14, CI in Task 12).
  - Hooks — Tasks 5, 6, 8, 12, 13. Argument order is jlesage's, taken from his README, not guessed.
  - Staging conversion directory — Tasks 6, 7, 8, 10, 12, 13. `partial_path()` replaced by `staging_path()` + `finalise_output()`.
  - Multiple watch folders — **already satisfied by Plan 1**, verified in Task 1 Step 10, no code.
  - Multiple-container capability — Task 8 (locking, because jlesage's README documents a shared watch folder) plus the isolation verification and documentation in Task 11 and README section 11.
  - Optical drive access — Task 10 (one ENV line activating the base's `init-device-perms`), Task 11 Step 15 (honest verification: **no drive available, only proves absence breaks nothing**), README section 12 flagged UNVERIFIED.
  - `KEEP_APP_RUNNING`, `APP_NICENESS`, `USER_ID`/`GROUP_ID`/`UMASK`/`TZ`/`LANG` — already satisfied by Plan 1, mapped in the README migration table.
- [ ] Every new variable that duplicates something the base already does was **dropped instead of added**: no `WEB_AUDIO`, no `WEB_HOST_CLIPBOARD_SYNC`, no `WEB_AUTHENTICATION*`, no `SECURE_CONNECTION`, no `ENABLE_CJK_FONT`.
- [ ] Script names are identical everywhere they appear: `handbrake-web.sh`, `handbrake-terminal.sh`, `handbrake-notify.sh`.
- [ ] Service names are identical everywhere: `init-handbrake-web`, `init-handbrake-web-post`.
- [ ] The Dockerfile's `chmod +x` list gained exactly five entries: the three new scripts and the two new `run` files.
- [ ] Every quoted "find this exact block" is real text from Plan 1's files, not paraphrase.
- [ ] Plan 2's territory is untouched: no edit to `handbrake-gpu.sh`, and README sections 1-8 keep their numbers.
- [ ] The optical-drive task never claims to be tested. Task 11 Step 15 says what it does and does not prove; the README carries a blockquote warning; Task 15 Step 8 repeats it when asking for release approval.
- [ ] Nothing runs on the default branch mid-flight: Task 1 branches, Task 15 merges, Task 15 Step 4 deletes the branch.

---

## Handoff: what this plan changed that other work must respect

**New fixed strings.**
- Log prefix `[handbrake-web]`. Scripts `/usr/local/bin/handbrake-{web,terminal,notify}.sh`.
- Runtime files: `/run/handbrake/webfm/` (symlink farm), `/run/handbrake/webfm.map` (tab-separated `entry<TAB>path`), `/run/handbrake/session-env` (abc-writable, sourced by `handbrake-notify.sh`).
- Config files written every start: `/config/.config/dunst/dunstrc`, `/config/.config/openbox/rc.xml` (only when `WEB_TERMINAL=1`).
- Hook names and argument order under `/config/hooks/`: changing either is a breaking change.

**New s6 ordering edges.** `init-os-end` → `init-handbrake-web` → `init-nginx`, and `init-handbrake` → `init-handbrake-web-post` → `init-config-end`. Anything that also needs to write `/run/s6/container_environment` before `init-nginx` should follow the first pattern rather than inventing a third.

**Watch daemon extension points that still exist.** `hb_run()` remains the single `HandBrakeCLI` call site; `staging_path()` is now the single staging-path helper and `finalise_output()` the single move-to-final helper; `acquire_lock()`/`release_lock()` bracket the per-file critical section. The GPU seam (`/run/handbrake/gpu-args`, `HB_GPU_ARGS`) is unchanged and still spliced before the user's custom args, which are now themselves followed by the `hb_custom_args.sh` hook's output.

**Env contract added.** `WEB_FILE_MANAGER`, `WEB_FILE_MANAGER_ALLOWED_PATHS`, `WEB_FILE_MANAGER_DENIED_PATHS`, `WEB_TERMINAL`, `WEB_TERMINAL_SHELL_PATH`, `WEB_NOTIFICATION`, `AUTOMATED_CONVERSION_STAGING_DIR`, `SELKIES_MICROPHONE_ENABLED`, `ATTACHED_DEVICES_PERMS`. A GPU plan that needs `/dev/dri` group membership should **append** to `ATTACHED_DEVICES_PERMS` rather than redeclare it.

**New mount point.** `/staging`, created 0777 in the image, unused unless `AUTOMATED_CONVERSION_STAGING_DIR` points at it.

