#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# handbrake-gpu.sh <vendor>
# ---------------------------------------------------------------------------
# Resolves GPU_VENDOR into the extra HandBrakeCLI arguments used for hardware
# encoding. Prints the argument string on STDOUT (empty = software encoding) and
# human-readable decision lines on STDERR.
#
# STDOUT IS A COMMAND LINE, NOT A LOG.
#   init-handbrake redirects this script's stdout into /run/handbrake/gpu-args,
#   and handbrake-watch.sh splices that file into every HandBrakeCLI invocation.
#   A single stray echo on stdout becomes a bogus HandBrakeCLI argument and
#   breaks every conversion. Everything human-readable goes through log()/warn(),
#   which write to stderr.
#
# HOW A VENDOR IS DETECTED: BY ASKING HANDBRAKE
#   libhb lists a hardware encoder in --help only when it is BOTH compiled in
#   AND usable on the hardware present right now (libhb/common.c,
#   hb_video_encoder_is_enabled() -> hb_qsv_video_encoder_is_available() /
#   hb_vce_h264_available() / hb_nvenc_h264_available()). One --help call is
#   therefore the identifier lookup and the hardware probe at the same time, and
#   no encoder id is ever hardcoded into an argument.
#
#   Do NOT use the build-time dump /usr/local/share/handbrake-cli-help.txt for
#   this, or for any other hardware-capability question. It is recorded during
#   `docker build` on a machine with no GPU, so it never contains a single
#   hardware encoder. Its static option-syntax text (e.g. "--enable-hw-decoding")
#   also cannot be trusted for whether a feature was actually compiled in:
#   measured on real NVENC hardware, the dump still names 'nvdec' as a valid
#   --enable-hw-decoding value while HandBrakeCLI's own runtime diagnostic says
#   nvdec is not compiled into this build at all. See
#   docs/handbrake-capabilities.md and docs/hardware-encoding-nvidia.md
#   sections 1 and 3.
#
#   The probe runs as abc, the user that later runs the conversions, so a
#   missing /dev/dri group problem is caught here instead of failing every job
#   later. init-handbrake depends on the base image's init-video oneshot, which
#   is what puts abc into the render node's group.
#
# EXTENSION POINT: add a branch to gpu_args_for_vendor() and give it a candidate
# list for hb_pick_encoder. Nothing else in the container needs to change.
# ---------------------------------------------------------------------------
set -eu

GPU_LOG="/config/handbrake-gpu.log"

log()  { echo "[handbrake-gpu] $*" >&2; }
warn() { echo "[handbrake-gpu] WARNING: $*" >&2; }

VENDOR_RAW="${1:-none}"
VENDOR="$(printf '%s' "${VENDOR_RAW}" | tr '[:upper:]' '[:lower:]')"

case "${VENDOR}" in
    ""|none|off|disabled) VENDOR="none" ;;
    nvidia|nvenc)         VENDOR="nvidia" ;;
    intel|qsv)            VENDOR="intel" ;;
    amd|vce|vcn)          VENDOR="amd" ;;
    *)
        warn "unrecognised GPU_VENDOR='${VENDOR_RAW}' — use none, nvidia, intel or amd"
        VENDOR="none"
        ;;
esac

# --- probes -----------------------------------------------------------------

# NVENC encoder preference order. H.264 comes FIRST on purpose: the default
# preset (General/Very Fast 1080p30) is an x264 preset, so nvenc_h264 keeps the
# delivered codec identical and swaps only the encoder implementation — the
# whole promise of "hardware acceleration", with no surprise HEVC files that an
# older TV refuses to play. Anyone who wants HEVC appends
# "--encoder nvenc_h265" to AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS, which
# the watch daemon splices in AFTER these arguments, so the later value wins.
NVENC_CANDIDATES=(nvenc_h264 nvenc_h265)

HB_ENCODERS=""

# hb_load_encoders — ask the real binary once, as the runtime user, and cache
# the newline-separated encoder ids in HB_ENCODERS.
#
# Each vendor branch calls this DIRECTLY before anything else. That is not
# redundant: hb_pick_encoder is used inside a command substitution, which runs
# in a subshell, so a cache filled in there would be thrown away and every
# candidate would re-run HandBrakeCLI --help. Filling it in the parent first
# means exactly one --help call per container start.
hb_load_encoders() {
    if [ -n "${HB_ENCODERS}" ]; then
        return 0
    fi
    local raw=""
    if command -v s6-setuidgid >/dev/null 2>&1 && id abc >/dev/null 2>&1; then
        raw="$(s6-setuidgid abc env HOME=/config XDG_CONFIG_HOME=/config/.config \
                 HandBrakeCLI --help 2>/dev/null || true)"
    else
        raw="$(HandBrakeCLI --help 2>/dev/null || true)"
    fi
    HB_ENCODERS="$(printf '%s\n' "${raw}" | awk '
        /^[[:space:]]*-e, --encoder[[:space:]]/ { inlist = 1; next }
        inlist && /^[[:space:]]*-/              { inlist = 0 }
        inlist {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            if ($0 != "") print
        }
    ')"
    if [ -z "${HB_ENCODERS}" ]; then
        warn "HandBrakeCLI --help produced no encoder list — hardware detection cannot run."
    fi
}

hb_has_encoder() {
    hb_load_encoders
    printf '%s\n' "${HB_ENCODERS}" | grep -qxF -- "$1"
}

# hb_pick_encoder <id> [id...] — echo the first id this build offers on this
# machine; return 1 when it offers none of them.
hb_pick_encoder() {
    local id
    for id in "$@"; do
        if hb_has_encoder "${id}"; then
            printf '%s' "${id}"
            return 0
        fi
    done
    return 1
}

hb_render_nodes() { ls -1 /dev/dri/renderD* 2>/dev/null || true; }

# hb_nvdec_compiled_in — True when THIS build's libhb actually has NVDEC
# compiled in.
#
# NOT a build-time-dump check, despite the --enable-hw-decoding help entry
# being a static string that always names 'nvdec' as a valid value: that text
# describes the OPTION's syntax, not whether the feature was compiled in, and
# measuring it on real hardware proved it wrong — HandBrakeCLI printed
# "nvdec: is not compiled into this build" on its own diagnostic line while
# --help still listed nvdec as an --enable-hw-decoding value. See
# docs/hardware-encoding-nvidia.md section 3 for the measured proof.
#
# HandBrakeCLI prints this diagnostic to stderr on every invocation once an
# NVIDIA device is present (the nvidia branch only calls this after its own
# device/library probes already passed), so a cheap --version call is a real,
# live probe: "nvdec: version N is available" vs "nvdec: is not compiled into
# this build". Same "ask the running binary" philosophy as the encoder check,
# applied to decode instead of encode.
hb_nvdec_compiled_in() {
    HandBrakeCLI --version 2>&1 | grep -q 'nvdec: version'
}

nvidia_device_present() {
    # The NVIDIA container runtime creates these nodes. Without --runtime=nvidia
    # (Unraid: Extra Parameters) none of them exist.
    local d
    for d in /dev/nvidiactl /dev/nvidia[0-9]* /dev/nvidia-uvm; do
        if [ -e "${d}" ]; then
            return 0
        fi
    done
    return 1
}

nvidia_lib_path() {
    # Prints the path of an injected NVIDIA driver library, or returns 1.
    # The runtime drops the libraries into the distro multiarch directory and
    # runs ldconfig, so both lookups are legitimate.
    local name="$1" p
    for p in /usr/lib/*/"${name}" /usr/lib64/"${name}" /usr/local/nvidia/lib64/"${name}"; do
        if [ -e "${p}" ]; then
            printf '%s' "${p}"
            return 0
        fi
    done
    p="$(ldconfig -p 2>/dev/null | awk -v n="${name}" '$1 == n { print $NF; exit }')" || p=""
    if [ -n "${p}" ] && [ -e "${p}" ]; then
        printf '%s' "${p}"
        return 0
    fi
    return 1
}

nvidia_smi_summary() {
    # Optional detail line. nvidia-smi is only injected with the "utility"
    # capability, so its absence is a missing nicety, never an error.
    command -v nvidia-smi >/dev/null 2>&1 || return 1
    nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | head -n 1
}

# hb_have_amf_runtime — used only to explain WHY an AMD encoder is missing.
# AMD's AMF runtime is proprietary, is not in Ubuntu, and cannot ship in this
# image; a user has to bind-mount it in, which happens after the image was
# built, so the loader cache is refreshed before it is consulted.
hb_have_amf_runtime() {
    ldconfig >/dev/null 2>&1 || true
    if ldconfig -p 2>/dev/null | grep -q 'libamfrt64\.so'; then
        return 0
    fi
    local cand
    for cand in /usr/lib/x86_64-linux-gnu/libamfrt64.so* \
                /usr/lib/libamfrt64.so* \
                /opt/amdgpu-pro/lib/x86_64-linux-gnu/libamfrt64.so*; do
        if [ -e "${cand}" ]; then
            return 0
        fi
    done
    return 1
}

# hb_write_diag <vendor> — everything a hardware report needs, in one file.
# Writes to ${GPU_LOG} ONLY. Never to stdout.
hb_write_diag() {
    local vendor="$1" node
    node="$(hb_render_nodes | head -n 1)"
    {
        echo "=== handbrake-gpu diagnostics ==="
        echo "date             : $(date -Is)"
        echo "GPU_VENDOR (raw) : ${VENDOR_RAW}"
        echo "vendor (parsed)  : ${vendor}"
        echo "architecture     : $(uname -m)"
        echo
        echo "--- image build ---"
        if [ -f /etc/handbrake-build ]; then
            cat /etc/handbrake-build
        else
            echo "no /etc/handbrake-build"
        fi
        head -n 1 /usr/local/share/handbrake-version.txt 2>/dev/null || echo "no version dump"
        echo
        echo "--- /dev/dri ---"
        ls -l /dev/dri 2>&1 || true
        echo
        echo "--- runtime user (must be in the render node's group) ---"
        id abc 2>&1 || true
        echo
        echo "--- DRM kernel drivers ---"
        for drv in /sys/class/drm/renderD*/device/driver; do
            if [ -e "${drv}" ]; then
                echo "${drv} -> $(basename "$(readlink -f "${drv}")")"
            fi
        done
        echo
        echo "--- encoders HandBrakeCLI offers HERE (compiled in AND hardware usable) ---"
        printf '%s\n' "${HB_ENCODERS}"
        echo
        echo "--- vainfo ---"
        if command -v vainfo >/dev/null 2>&1 && [ -n "${node}" ]; then
            vainfo --display drm --device "${node}" 2>&1 || true
        else
            echo "vainfo not installed, or no render node to query"
        fi
        echo
        echo "--- vpl-inspect (Intel oneVPL) ---"
        if command -v vpl-inspect >/dev/null 2>&1; then
            vpl-inspect 2>&1 || true
        else
            echo "vpl-inspect not installed"
        fi
        echo
        echo "--- AMF runtime (AMD VCE) ---"
        ldconfig -p 2>/dev/null | grep -i 'libamfrt64' || echo "libamfrt64.so* is not in the loader cache"
    } > "${GPU_LOG}" 2>&1 || true
    chown "${PUID:-911}:${PGID:-911}" "${GPU_LOG}" 2>/dev/null || true
    chmod 0644 "${GPU_LOG}" 2>/dev/null || true
}

# --- vendor selection -------------------------------------------------------

gpu_args_for_vendor() {
    local vendor="$1" enc="" node="" lib_encode="" lib_decode="" detail="" args=""

    case "${vendor}" in
        none)
            printf ''
            log "GPU acceleration: none — software encoding (x264/x265)"
            return 0
            ;;

        nvidia)
            # hb_load_encoders + hb_write_diag come first, matching the intel/amd
            # branches below: a hardware report needs GPU_LOG regardless of which
            # step fails, not only the "no NVENC encoder" case. hb_load_encoders
            # itself needs no GPU (it just parses `HandBrakeCLI --help`), so it is
            # always safe to run before the device/library checks.
            hb_load_encoders
            hb_write_diag "${vendor}"

            # -- 1) Is an NVIDIA GPU passed into this container at all? --------
            if ! nvidia_device_present; then
                printf ''
                log "ERROR: GPU_VENDOR=nvidia, but this container has no /dev/nvidia* device node,"
                log "       so it was not started through the NVIDIA container runtime."
                log "       Fix (Unraid): install the Nvidia-Driver plugin, put '--runtime=nvidia' into the"
                log "       container's Extra Parameters, and set NVIDIA_VISIBLE_DEVICES to a GPU UUID"
                log "       from 'nvidia-smi -L' on the host (or to 'all')."
                log "FALLING BACK TO SOFTWARE ENCODING for this container start."
                return 0
            fi

            # -- 2) Is the NVENC runtime library there? ------------------------
            # libnvidia-encode.so.1 is injected only when
            # NVIDIA_DRIVER_CAPABILITIES contains "video". Without it every
            # NVENC job would abort inside HandBrake with an opaque error.
            if ! lib_encode="$(nvidia_lib_path libnvidia-encode.so.1)"; then
                printf ''
                log "ERROR: GPU_VENDOR=nvidia and an NVIDIA device is present, but libnvidia-encode.so.1"
                log "       is missing — NVENC cannot run without it."
                log "       Fix: set NVIDIA_DRIVER_CAPABILITIES=compute,video,utility on the container."
                log "       The 'video' capability is the one that injects the encoder library ('all' works too)."
                log "FALLING BACK TO SOFTWARE ENCODING for this container start."
                return 0
            fi

            # -- 3) Does the RUNNING HandBrakeCLI offer an NVENC encoder here? -
            # Asking the live binary is both the identifier lookup and the final
            # hardware check: libhb hides nvenc_* until its own availability
            # probe passes. hb_load_encoders already ran above.
            enc="$(hb_pick_encoder "${NVENC_CANDIDATES[@]}" || true)"
            if [ -z "${enc}" ]; then
                printf ''
                log "ERROR: GPU_VENDOR=nvidia, the NVIDIA device node and libnvidia-encode.so.1 are both"
                log "       present, but HandBrakeCLI offers none of '${NVENC_CANDIDATES[*]}' on this machine."
                log "       HandBrake lists a hardware encoder only when it is compiled in AND currently"
                log "       usable, so one of these holds:"
                log "         * the NVIDIA driver is older than HandBrake's documented NVENC minimum"
                log "         * this GPU has no usable NVENC block (too old, or it is a model without one)"
                log "         * this build was not built with --enable-nvenc for this architecture"
                log "       Encoders HandBrakeCLI offers here: $(printf '%s' "${HB_ENCODERS}" | tr '\n' ' ')"
                log "FALLING BACK TO SOFTWARE ENCODING for this container start."
                return 0
            fi

            # -- 4) Do not fight a preset that already picked NVENC ------------
            # HandBrake ships its own hardware presets. If the user selected
            # one, they chose that codec deliberately — leave the preset alone
            # and let it drive the encoder.
            case "$(printf '%s' "${AUTOMATED_CONVERSION_PRESET:-}" | tr '[:upper:]' '[:lower:]')" in
                *nvenc*)
                    args=""
                    ;;
                *)
                    args="--encoder ${enc}"
                    ;;
            esac

            printf '%s' "${args}"

            # -- 5) Say exactly what is in effect ------------------------------
            if detail="$(nvidia_smi_summary)"; then
                log "GPU acceleration: NVIDIA NVENC — ${detail}"
            else
                log "GPU acceleration: NVIDIA NVENC (no nvidia-smi in this container; add the 'utility'"
                log "                  capability to NVIDIA_DRIVER_CAPABILITIES to see the GPU name here)"
            fi
            log "encoder library: ${lib_encode}"
            if [ -z "${args}" ]; then
                log "preset '${AUTOMATED_CONVERSION_PRESET:-}' already selects an NVENC encoder — not overriding it"
            else
                log "HandBrakeCLI arguments: ${args}"
                log "NOTE: every watch-folder job now encodes with '${enc}' and overrides the video"
                log "      encoder of AUTOMATED_CONVERSION_PRESET. Put '--encoder <id>' into"
                log "      AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS to pick a different one."
            fi
            if lib_decode="$(nvidia_lib_path libnvcuvid.so.1)" && hb_nvdec_compiled_in; then
                log "NVDEC is available (${lib_decode}) but stays OFF: HandBrake disables hardware decoding"
                log "      as soon as any filter runs, which every stock preset does. Add"
                log "      '--enable-hw-decoding nvdec' to AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS to force it."
            fi
            log "diagnostics: ${GPU_LOG}"
            ;;

        intel)
            hb_load_encoders
            hb_write_diag "${vendor}"
            node="$(hb_render_nodes | head -n 1)"

            if [ -z "${node}" ]; then
                printf ''
                warn "GPU_VENDOR=intel, but no DRM render node (/dev/dri/renderD*) is visible in this container."
                warn "Pass the iGPU through: Unraid adds '--device=/dev/dri' under Extra Parameters, plain docker run takes '--device /dev/dri'."
                warn "The host also needs the i915 (or xe) kernel driver loaded."
                warn "Falling back to software encoding."
                return 0
            fi

            enc="$(hb_pick_encoder qsv_h264 || true)"
            if [ -z "${enc}" ]; then
                printf ''
                warn "GPU_VENDOR=intel and ${node} exists, but HandBrakeCLI does not offer qsv_h264 on this machine."
                warn "HandBrake lists a hardware encoder only when it is compiled in AND usable, so one of these holds:"
                warn "  * the GPU is not an Intel one, or is older than the oneVPL GPU runtime supports"
                warn "  * the container user cannot use ${node} (check 'runtime user' in ${GPU_LOG})"
                warn "  * this is arm64 — Intel Quick Sync is x86-64 only"
                warn "Full details in ${GPU_LOG}. Falling back to software encoding."
                return 0
            fi

            printf -- '--encoder %s' "${enc}"
            log "Intel QSV enabled: --encoder ${enc} (render node ${node})"
            log "diagnostics: ${GPU_LOG}"
            ;;

        amd)
            hb_load_encoders
            hb_write_diag "${vendor}"
            node="$(hb_render_nodes | head -n 1)"

            if [ -z "${node}" ]; then
                printf ''
                warn "GPU_VENDOR=amd, but no DRM render node (/dev/dri/renderD*) is visible in this container."
                warn "Pass the GPU through: Unraid adds '--device=/dev/dri' under Extra Parameters, plain docker run takes '--device /dev/dri'."
                warn "The host also needs the amdgpu kernel driver loaded."
                warn "Falling back to software encoding."
                return 0
            fi

            # vce_h264   AMD VCE through AMF. Only exists in a HandBrakeCLI built
            #            with --enable-vce (see Dockerfile.gpu), and HandBrake only
            #            lists it once AMD's proprietary AMF runtime has actually
            #            loaded and produced encoder caps.
            # vaapi_h264 Not in HandBrake 1.11; upstream added VA-API encoders on
            #            master. Named here so a later base-image bump lights the
            #            path up with no code change, because ids are looked up.
            enc="$(hb_pick_encoder vce_h264 vaapi_h264 || true)"
            if [ -z "${enc}" ]; then
                printf ''
                warn "GPU_VENDOR=amd and ${node} exists, but HandBrakeCLI offers neither vce_h264 nor vaapi_h264 here."
                if hb_have_amf_runtime; then
                    warn "AMD's AMF runtime IS reachable, so this HandBrakeCLI was simply not built with --enable-vce."
                    warn "Ubuntu never builds HandBrake with VCE. Build the optional variant (Dockerfile.gpu) to get it."
                else
                    warn "AMD's AMF runtime (libamfrt64.so*) is not reachable in this container, and Ubuntu does not build"
                    warn "HandBrake with --enable-vce either, so this image has no AMD hardware encoder at all."
                    warn "The README's Hardware Encoding section explains what AMD hardware encoding needs."
                fi
                warn "Full details in ${GPU_LOG}. Falling back to software encoding."
                return 0
            fi

            printf -- '--encoder %s' "${enc}"
            log "AMD hardware encoding enabled: --encoder ${enc} (render node ${node})"
            log "diagnostics: ${GPU_LOG}"
            ;;

        *)
            printf ''
            warn "GPU_VENDOR='${vendor}' is not implemented in this image build — falling back to software encoding."
            ;;
    esac
}

printf '%s' "${VENDOR}" > /run/handbrake/gpu-vendor 2>/dev/null || true
gpu_args_for_vendor "${VENDOR}"
