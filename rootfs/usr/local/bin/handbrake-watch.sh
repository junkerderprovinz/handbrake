#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# handbrake-watch.sh — automated watch-folder conversion daemon
# ---------------------------------------------------------------------------
# Polls one or more watch folders and converts every new video with
# HandBrakeCLI. Variable names deliberately mirror jlesage/docker-handbrake so a
# migrating user keeps their template values.
#
# DESIGN NOTES
#   * Runs as abc (see svc-handbrake-watch/run), so every produced file gets the
#     right ownership and the container UMASK without any chown afterwards.
#   * QUIET WHEN IDLE. The poll loop logs nothing on an empty pass; only real
#     events reach the container log. This is what keeps the "HANDBRAKE IS
#     READY" banner as the last block of `docker logs` on an idle container.
#   * A file is only picked up once it has been STABLE for
#     AUTOMATED_CONVERSION_SOURCE_STABLE_TIME seconds (size+mtime unchanged
#     between two passes), so a file still being copied in is never transcoded.
#   * Every processed source is remembered by sha1(path)|size|mtime in
#     done.list / failed.list. Re-copying or editing the source changes the key,
#     so it is picked up again; an unchanged source is never re-processed.
#   * Output is written to a hidden .partial sibling and renamed on success.
# ---------------------------------------------------------------------------
set -uo pipefail

log() { echo "[handbrake-watch] $*"; }

truthy() {
    case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

# ---- configuration ---------------------------------------------------------
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

DEFAULT_VIDEO_EXTENSIONS="mkv mp4 m4v avi mov wmv flv webm mpg mpeg m2ts mts ts vob 3gp ogv divx asf rm rmvb iso"

# Numeric guards — a hand-edited template value must not break the loop.
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
        log "WARNING: unknown AUTOMATED_CONVERSION_FORMAT='${FORMAT}' — letting the preset choose the container"
        ;;
esac

# Extension allow-list.
EXT_SETTING="${AUTOMATED_CONVERSION_VIDEO_FILE_EXTENSIONS:-}"
[ -z "${EXT_SETTING}" ] && EXT_SETTING="${DEFAULT_VIDEO_EXTENSIONS}"
read -r -a VIDEO_EXTENSIONS <<< "$(printf '%s' "${EXT_SETTING}" | tr ',' ' ' | tr '[:upper:]' '[:lower:]')"

# Extra HandBrakeCLI arguments: the GPU seam first, the user's custom args last
# (so a user can always override what the vendor branch chose).
read -r -a HB_GPU_ARGS <<< "$(cat /run/handbrake/gpu-args 2>/dev/null || true)"
read -r -a HB_EXTRA_ARGS <<< "${AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS:-}"

# ---- shutdown handling -----------------------------------------------------
CURRENT_PARTIAL=""
CURRENT_PID=""

cleanup() {
    log "stop requested — shutting down"
    if [ -n "${CURRENT_PID}" ] && kill -0 "${CURRENT_PID}" 2>/dev/null; then
        log "cancelling the running conversion (pid ${CURRENT_PID})"
        kill -TERM "${CURRENT_PID}" 2>/dev/null || true
        wait "${CURRENT_PID}" 2>/dev/null || true
    fi
    if [ -n "${CURRENT_PARTIAL}" ] && [ -e "${CURRENT_PARTIAL}" ]; then
        rm -f -- "${CURRENT_PARTIAL}"
        log "removed the partial output ${CURRENT_PARTIAL}"
    fi
    exit 0
}
trap cleanup TERM INT

# ---- helpers ---------------------------------------------------------------
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

partial_path() {
    # Plan 4 replaces this single helper when it adds a configurable staging
    # directory. Everything else in the daemon keeps working unchanged.
    printf '%s/.%s.partial' "$1" "$2"
}

hb_run() {
    # $1 = source, $2 = destination. The ONE HandBrakeCLI invocation site.
    local src="$1" dst="$2" rc
    local -a args
    args=( --preset "${PRESET}" --input "${src}" --output "${dst}" )
    [ -n "${MUX}" ] && args+=( --format "${MUX}" )
    [ "${#HB_GPU_ARGS[@]}" -gt 0 ] && args+=( "${HB_GPU_ARGS[@]}" )
    [ "${#HB_EXTRA_ARGS[@]}" -gt 0 ] && args+=( "${HB_EXTRA_ARGS[@]}" )

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

# ---- watch folder resolution -----------------------------------------------
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

# ---- startup ---------------------------------------------------------------
if ! truthy "${AUTOMATED_CONVERSION:-1}"; then
    log "automated conversion is disabled (AUTOMATED_CONVERSION=${AUTOMATED_CONVERSION:-1}) — idling"
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
    log "no watch folder found (AUTOMATED_CONVERSION_WATCH_DIR=${WATCH_DIR_SETTING}) — idling"
    exec sleep infinity
fi

mkdir -p "${OUTPUT_DIR}"
log "watching: ${WATCH_DIRS[*]}"
log "output:   ${OUTPUT_DIR}${OUTPUT_SUBDIR:+ (subdir ${OUTPUT_SUBDIR})}  format=${FORMAT}${MUX:+ (${MUX})}"
log "preset:   ${PRESET}   keep-source=${AUTOMATED_CONVERSION_KEEP_SOURCE:-1}   nice=${NICE_LEVEL}"
log "extensions: ${VIDEO_EXTENSIONS[*]}"
log "job log:  ${JOB_LOG}   state: ${STATE_DIR}"

declare -A SEEN_KEY
declare -A SEEN_AT

# ---- main loop -------------------------------------------------------------
while true; do
    for watch_dir in "${WATCH_DIRS[@]}"; do
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
                continue
            fi

            CURRENT_PARTIAL="$(partial_path "${out_base}" "${stem}.${FORMAT}")"
            rm -f -- "${CURRENT_PARTIAL}"

            log "converting '${src}' -> '${dst}'"
            started="$(date +%s)"
            if hb_run "${src}" "${CURRENT_PARTIAL}" && [ -s "${CURRENT_PARTIAL}" ]; then
                mv -f -- "${CURRENT_PARTIAL}" "${dst}"
                CURRENT_PARTIAL=""
                took=$(( $(date +%s) - started ))
                log "done '${base}' in ${took}s -> ${dst}"
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
            fi
        done < <(find "${watch_dir}" -type f -print0 2>/dev/null)
    done
    sleep "${CHECK_INTERVAL}"
done
