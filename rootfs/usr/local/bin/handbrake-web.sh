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
    # $(...) strips trailing newlines, so $(printf '\n') is the EMPTY string and
    # *""* matches everything — that bug once made this function reject every
    # path unconditionally. $'\n' is a literal newline with no substitution
    # involved, so nothing strips it.
    case "$1" in
        *$'\n'*) return 1 ;;
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
    # printf '%s\n', not '%s': a `while read` loop silently DROPS the final
    # line when the input has no trailing newline, so a single denied path (no
    # comma) was never seen at all — found on the first real boot, where a
    # WEB_FILE_MANAGER_DENIED_PATHS with one entry produced no log line and no
    # 403 whatsoever.
    done < <(printf '%s\n' "${raw}" | tr ',' '\n')

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
