#!/usr/bin/env bash
# Watch-folder conversion daemon: polls the watch folders and converts every
# new video with HandBrakeCLI. The variable names mirror jlesage/docker-handbrake
# so a migrating user keeps their template values.
#
# Runs as abc (svc-handbrake-watch/run), so every file gets the right owner and
# the container UMASK. An empty pass logs nothing, which keeps the READY banner
# the last block of `docker logs` on an idle container. A file is picked up once
# its size and mtime stayed the same for AUTOMATED_CONVERSION_SOURCE_STABLE_TIME
# seconds, so a file still being copied in is left alone. Each processed source
# is remembered as sha1(path)|size|mtime in done.list or failed.list, so a
# changed source is converted again and an unchanged one never is.
set -uo pipefail

log() { echo "[handbrake-watch] $*"; }

truthy() {
    case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

PRESET="${AUTOMATED_CONVERSION_PRESET:-General/Very Fast 1080p30}"
FORMAT="$(printf '%s' "${AUTOMATED_CONVERSION_FORMAT:-mp4}" | tr '[:upper:]' '[:lower:]')"
OUTPUT_DIR="${AUTOMATED_CONVERSION_OUTPUT_DIR:-/output}"
OUTPUT_SUBDIR="${AUTOMATED_CONVERSION_OUTPUT_SUBDIR:-}"
WATCH_DIR_SETTING="${AUTOMATED_CONVERSION_WATCH_DIR:-AUTO}"
MAX_WATCH_FOLDERS="${AUTOMATED_CONVERSION_MAX_WATCH_FOLDERS:-5}"
STABLE_TIME="${AUTOMATED_CONVERSION_SOURCE_STABLE_TIME:-5}"
CHECK_INTERVAL="${AUTOMATED_CONVERSION_CHECK_INTERVAL:-5}"
NICE_LEVEL="${APP_NICENESS:-0}"

STATE_DIR="/config/handbrake/watch-state"
DONE_LIST="${STATE_DIR}/done.list"
FAILED_LIST="${STATE_DIR}/failed.list"
JOB_LOG="/config/handbrake-watch.log"

# Directory basenames to prune out of every watch-folder scan, e.g. sync-client
# metadata folders. Space-separated, matched anywhere in the tree.
IGNORE_DIRS_SETTING="${AUTOMATED_CONVERSION_IGNORE_DIRECTORIES:-}"
read -r -a IGNORE_DIR_NAMES <<< "${IGNORE_DIRS_SETTING}"

# Restrict conversion to a daily time window, e.g. "22-06" for overnight only.
# Empty (the default) means always active. Wraps past midnight when start > end.
ACTIVE_HOURS_SETTING="${AUTOMATED_CONVERSION_ACTIVE_HOURS:-}"
ACTIVE_START=-1
ACTIVE_END=-1
if [ -n "${ACTIVE_HOURS_SETTING}" ]; then
    case "${ACTIVE_HOURS_SETTING}" in
        [0-9]*-[0-9]*)
            ACTIVE_START="${ACTIVE_HOURS_SETTING%%-*}"
            ACTIVE_END="${ACTIVE_HOURS_SETTING##*-}"
            case "${ACTIVE_START}" in *[!0-9]*) ACTIVE_START=bad ;; esac
            case "${ACTIVE_END}"   in *[!0-9]*) ACTIVE_END=bad ;; esac
            if [ "${ACTIVE_START}" = "bad" ] || [ "${ACTIVE_END}" = "bad" ] \
               || [ "${ACTIVE_START}" -gt 23 ] || [ "${ACTIVE_END}" -gt 23 ]; then
                log "WARNING: AUTOMATED_CONVERSION_ACTIVE_HOURS='${ACTIVE_HOURS_SETTING}' must be two hours 0-23 separated by '-' (e.g. 22-06); ignoring it, conversion stays always active"
                ACTIVE_START=-1
                ACTIVE_END=-1
            fi
            ;;
        *)
            log "WARNING: AUTOMATED_CONVERSION_ACTIVE_HOURS='${ACTIVE_HOURS_SETTING}' does not match HH-HH; ignoring it, conversion stays always active"
            ;;
    esac
fi

# Same path as in jlesage's image, so a migrating user's hooks land where they
# already expect them.
HOOKS_DIR="/config/hooks"

# A conversion is written here and moved to its destination once HandBrakeCLI
# succeeded. Empty means a hidden directory under the output root, as in
# jlesage's image. On a cache pool it keeps the array out of the write path
# while a transcode runs.
STAGING_DIR="${AUTOMATED_CONVERSION_STAGING_DIR:-}"
[ -z "${STAGING_DIR}" ] && STAGING_DIR="${OUTPUT_DIR}/.handbrake-staging"

# A short, stable tag for this container. Two instances may share a staging
# directory or a watch folder, so every file carries its creator's tag and a
# restart cleans up only its own leftovers.
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

DEFAULT_VIDEO_EXTENSIONS="mkv mp4 m4v avi mov wmv flv webm mpg mpeg m2ts mts ts vob 3gp ogv divx asf rm rmvb iso"

# A hand-edited template value must not break the loop.
for _var in MAX_WATCH_FOLDERS STABLE_TIME CHECK_INTERVAL NICE_LEVEL; do
    case "${!_var}" in
        ''|*[!0-9]*) printf -v "${_var}" '%s' "0" ;;
    esac
done
[ "${CHECK_INTERVAL}" -lt 1 ] && CHECK_INTERVAL=5
[ "${MAX_WATCH_FOLDERS}" -lt 1 ] && MAX_WATCH_FOLDERS=1
[ "${NICE_LEVEL}" -gt 19 ] && NICE_LEVEL=19

# Container mux name for the requested extension.
case "${FORMAT}" in
    mp4|m4v) MUX="av_mp4" ;;
    mkv)     MUX="av_mkv" ;;
    webm)    MUX="av_webm" ;;
    *)
        MUX=""
        log "WARNING: unknown AUTOMATED_CONVERSION_FORMAT='${FORMAT}', letting the preset choose the container"
        ;;
esac

EXT_SETTING="${AUTOMATED_CONVERSION_VIDEO_FILE_EXTENSIONS:-}"
[ -z "${EXT_SETTING}" ] && EXT_SETTING="${DEFAULT_VIDEO_EXTENSIONS}"
read -r -a VIDEO_EXTENSIONS <<< "$(printf '%s' "${EXT_SETTING}" | tr ',' ' ' | tr '[:upper:]' '[:lower:]')"

# Extra HandBrakeCLI arguments: the GPU seam first, the user's custom args last
# (so a user can always override what the vendor branch chose).
read -r -a HB_GPU_ARGS <<< "$(cat /run/handbrake/gpu-args 2>/dev/null || true)"
read -r -a HB_EXTRA_ARGS <<< "${AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS:-}"

CURRENT_PARTIAL=""
CURRENT_PID=""
CURRENT_LOCK=""
LOCK_WARNED=0

cleanup() {
    log "stop requested, shutting down"
    if [ -n "${CURRENT_PID}" ] && kill -0 "${CURRENT_PID}" 2>/dev/null; then
        log "cancelling the running conversion (pid ${CURRENT_PID})"
        kill -TERM "${CURRENT_PID}" 2>/dev/null || true
        wait "${CURRENT_PID}" 2>/dev/null || true
    fi
    if [ -n "${CURRENT_PARTIAL}" ] && [ -e "${CURRENT_PARTIAL}" ]; then
        rm -f -- "${CURRENT_PARTIAL}"
        log "removed the partial output ${CURRENT_PARTIAL}"
    fi
    release_lock
    exit 0
}
trap cleanup TERM INT

file_key() {
    local f="$1" sz mt hash
    sz="$(stat -c %s -- "${f}" 2>/dev/null || echo 0)"
    mt="$(stat -c %Y -- "${f}" 2>/dev/null || echo 0)"
    hash="$(printf '%s' "${f}" | sha1sum | cut -d' ' -f1)"
    printf '%s|%s|%s' "${hash}" "${sz}" "${mt}"
}

in_list() { grep -qxF -- "$2" "$1" 2>/dev/null; }

is_video() {
    local ext="$1" e
    for e in "${VIDEO_EXTENSIONS[@]}"; do
        [ "${ext}" = "${e}" ] && return 0
    done
    return 1
}

# Prints every file under $1, NUL-separated, skipping any directory whose
# basename appears in IGNORE_DIR_NAMES anywhere in the tree (not just at the
# watch folder's own top level).
find_watch_dir() {
    local wd="$1"
    if [ "${#IGNORE_DIR_NAMES[@]}" -eq 0 ]; then
        find "${wd}" -type f -print0 2>/dev/null
        return
    fi
    local -a prune_expr=()
    local name first=1
    for name in "${IGNORE_DIR_NAMES[@]}"; do
        [ -n "${name}" ] || continue
        if [ "${first}" -eq 1 ]; then
            prune_expr=( -name "${name}" )
            first=0
        else
            prune_expr+=( -o -name "${name}" )
        fi
    done
    find "${wd}" -type d \( "${prune_expr[@]}" \) -prune -o -type f -print0 2>/dev/null
}

# True when conversion should run right now. ACTIVE_START=-1 (the default,
# AUTOMATED_CONVERSION_ACTIVE_HOURS unset or invalid) means always active.
in_active_window() {
    [ "${ACTIVE_START}" -eq -1 ] && return 0
    local h
    h="$(date +%-H)"
    if [ "${ACTIVE_START}" -le "${ACTIVE_END}" ]; then
        [ "${h}" -ge "${ACTIVE_START}" ] && [ "${h}" -lt "${ACTIVE_END}" ]
    else
        # Wraps past midnight, e.g. 22-06: active from 22:00 through 05:59.
        [ "${h}" -ge "${ACTIVE_START}" ] || [ "${h}" -lt "${ACTIVE_END}" ]
    fi
}

staging_path() {
    # $1 = final file name (stem.ext). In STAGING_DIR a media scanner watching
    # the output never sees the file, and the directory can sit on a faster
    # disk. The instance tag keeps two containers sharing it apart.
    printf '%s/.%s.%s.partial' "${STAGING_DIR}" "${INSTANCE}" "$1"
}

finalise_output() {
    # $1 = finished staging file, $2 = final destination.
    #
    # Across filesystems `mv` is a copy and not atomic, so a scanner could index
    # a half-copied file. Moving to a hidden sibling in the destination
    # directory first makes the last step a same-filesystem rename, which is.
    local stage="$1" dst="$2" tmp
    tmp="$(dirname -- "${dst}")/.${INSTANCE}.$(basename -- "${dst}").moving"
    rm -f -- "${tmp}"
    if ! mv -f -- "${stage}" "${tmp}"; then
        log "ERROR: could not move '${stage}' to '${tmp}'. Is the output folder writable and does it have room?"
        return 1
    fi
    if ! mv -f -- "${tmp}" "${dst}"; then
        log "ERROR: could not rename '${tmp}' to '${dst}'"
        rm -f -- "${tmp}"
        return 1
    fi
    return 0
}

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
    # /bin/sh whatever the shebang says, the contract jlesage documents, so a
    # hook copied over from that image behaves the same here.
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
        log "      Fine for one container. Do not point a second instance at this"
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
    # Removes only the locks this container left behind after an unclean stop.
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

hb_run() {
    # $1 = source, $2 = destination. The single place HandBrakeCLI runs.
    local src="$1" dst="$2" rc
    local -a args
    args=( --preset "${PRESET}" --input "${src}" --output "${dst}" )
    [ -n "${MUX}" ] && args+=( --format "${MUX}" )
    [ "${#HB_GPU_ARGS[@]}" -gt 0 ] && args+=( "${HB_GPU_ARGS[@]}" )
    [ "${#HB_EXTRA_ARGS[@]}" -gt 0 ] && args+=( "${HB_EXTRA_ARGS[@]}" )

    # Per-file arguments from the hb_custom_args.sh hook, appended last so they
    # win over both the GPU seam and AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS
    # (HandBrakeCLI takes the last occurrence of a repeated flag).
    local -a hook_args=()
    local hook_out
    if [ -f "${HOOKS_DIR}/hb_custom_args.sh" ]; then
        hook_out="$(/bin/sh "${HOOKS_DIR}/hb_custom_args.sh" "${src}" "${PRESET}" 2>> "${JOB_LOG}")" || hook_out=""
        [ -n "${hook_out}" ] && read -r -a hook_args <<< "${hook_out}"
    fi
    [ "${#hook_args[@]}" -gt 0 ] && args+=( "${hook_args[@]}" )

    {
        echo "=== $(date -Is) HandBrakeCLI ${args[*]}"
    } >> "${JOB_LOG}"

    nice -n "${NICE_LEVEL}" HandBrakeCLI "${args[@]}" >> "${JOB_LOG}" 2>&1 &
    CURRENT_PID=$!
    wait "${CURRENT_PID}"
    rc=$?
    CURRENT_PID=""
    return "${rc}"
}

resolve_watch_dirs() {
    local -a dirs=()
    local i d
    if [ "${WATCH_DIR_SETTING}" = "AUTO" ]; then
        for (( i = 1; i <= MAX_WATCH_FOLDERS; i++ )); do
            if [ "${i}" -eq 1 ]; then d="/watch"; else d="/watch${i}"; fi
            [ -d "${d}" ] && dirs+=( "${d}" )
        done
    else
        [ -d "${WATCH_DIR_SETTING}" ] && dirs+=( "${WATCH_DIR_SETTING}" )
    fi
    printf '%s\n' "${dirs[@]:-}"
}

if ! truthy "${AUTOMATED_CONVERSION:-1}"; then
    log "automated conversion is disabled (AUTOMATED_CONVERSION=${AUTOMATED_CONVERSION:-1}), idling"
    exec sleep infinity
fi

mkdir -p "${STATE_DIR}"
touch "${DONE_LIST}" "${FAILED_LIST}" "${JOB_LOG}"

mapfile -t WATCH_DIRS < <(resolve_watch_dirs)
# mapfile keeps one empty element when resolve_watch_dirs printed nothing.
if [ "${#WATCH_DIRS[@]}" -eq 1 ] && [ -z "${WATCH_DIRS[0]}" ]; then
    WATCH_DIRS=()
fi

if [ "${#WATCH_DIRS[@]}" -eq 0 ]; then
    log "no watch folder found (AUTOMATED_CONVERSION_WATCH_DIR=${WATCH_DIR_SETTING}), idling"
    exec sleep infinity
fi

mkdir -p "${OUTPUT_DIR}"

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

# Leftovers from an unclean stop of this container; another instance's files
# carry a different tag.
find "${STAGING_DIR}" -maxdepth 1 -type f -name ".${INSTANCE}.*.partial" -delete 2>/dev/null || true
find "${OUTPUT_DIR}" -type f -name ".${INSTANCE}.*.moving" -delete 2>/dev/null || true
for _wd in "${WATCH_DIRS[@]}"; do
    clear_own_locks "${_wd}"
done

seed_hooks

log "watching: ${WATCH_DIRS[*]}"
log "output:   ${OUTPUT_DIR}${OUTPUT_SUBDIR:+ (subdir ${OUTPUT_SUBDIR})}  format=${FORMAT}${MUX:+ (${MUX})}"
log "preset:   ${PRESET}   keep-source=${AUTOMATED_CONVERSION_KEEP_SOURCE:-1}   nice=${NICE_LEVEL}"
log "extensions: ${VIDEO_EXTENSIONS[*]}"
log "job log:  ${JOB_LOG}   state: ${STATE_DIR}"
log "staging:  ${STAGING_DIR}   instance: ${INSTANCE}"
log "hooks:    ${HOOKS_DIR}   notifications=${WEB_NOTIFICATION:-0}"
[ "${#IGNORE_DIR_NAMES[@]}" -gt 0 ] && log "ignoring directories named: ${IGNORE_DIR_NAMES[*]}"
[ "${ACTIVE_START}" -ne -1 ] && log "active hours: ${ACTIVE_HOURS_SETTING} (idle outside this window)"

declare -A SEEN_KEY
declare -A SEEN_AT
WAS_ACTIVE=1

while true; do
    if ! in_active_window; then
        if [ "${WAS_ACTIVE}" -eq 1 ]; then
            log "outside the active hours window (${ACTIVE_HOURS_SETTING}), idling until it opens again"
            WAS_ACTIVE=0
        fi
        sleep "${CHECK_INTERVAL}"
        continue
    fi
    if [ "${WAS_ACTIVE}" -eq 0 ]; then
        log "active hours window (${ACTIVE_HOURS_SETTING}) opened, resuming conversion"
        WAS_ACTIVE=1
    fi
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

            # Two containers may watch the same folder to convert twice as many
            # files at once. Whoever creates the lock directory first owns this
            # file; everybody else moves on to the next one.
            if ! acquire_lock "${watch_dir}" "${src}"; then
                continue
            fi

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

            HB_INPUT="${src}"
            HB_OUTPUT="${dst}"
            HB_STATUS=""
            HB_WATCH_DIR="${watch_dir}"
            if ! run_hook pre_conversion.sh "${dst}" "${src}" "${PRESET}"; then
                log "pre_conversion.sh refused '${base}', skipping it (recorded as failed)"
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
                elif rm -f -- "${src}" 2>/dev/null && [ ! -e "${src}" ]; then
                    log "removed source '${src}' (AUTOMATED_CONVERSION_KEEP_SOURCE=0)"
                    unset "SEEN_KEY[${src}]" "SEEN_AT[${src}]"
                else
                    # KEEP_SOURCE=0 relies on the file being gone; a failed rm
                    # would otherwise re-convert it on every pass.
                    log "WARNING: could not remove source '${src}', check the watch folder's permissions."
                    log "         Recording it as done instead so it is not converted again."
                    printf '%s\n' "${key}" >> "${DONE_LIST}"
                fi
            else
                rm -f -- "${CURRENT_PARTIAL}"
                CURRENT_PARTIAL=""
                printf '%s\n' "${key}" >> "${FAILED_LIST}"
                log "FAILED '${src}', it will not be retried until the file changes."
                log "last 20 lines of ${JOB_LOG}:"
                tail -n 20 "${JOB_LOG}" || true
                notify critical "Conversion failed" "${base}, see /config/handbrake-watch.log"
                HB_STATUS="1"
            fi

            # Runs for success and failure alike, and only after the finished
            # file already reached its final path. Its exit code is ignored.
            run_hook post_conversion.sh "${HB_STATUS}" "${dst}" "${src}" "${PRESET}" || true
            release_lock
        done < <(find_watch_dir "${watch_dir}")

        # An idle container stays quiet, so the per-folder hook fires only after
        # a pass that converted something.
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
