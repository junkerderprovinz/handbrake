#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# handbrake-gpu.sh <vendor>
# ---------------------------------------------------------------------------
# Resolves GPU_VENDOR into the extra HandBrakeCLI arguments used for hardware
# encoding. Prints the argument string on STDOUT (empty = software encoding) and
# a human-readable decision block on STDERR.
#
# Implemented vendors:
#   none    software encoding (x264/x265) — the default
#   nvidia  NVENC hardware encoding, when the container really has a usable
#           NVIDIA GPU. When it does not, this script says so loudly, names the
#           exact fix and falls back to software encoding — it never emits
#           arguments that would make every single job fail.
#
# The arguments only affect the AUTOMATED WATCH-FOLDER daemon, which is the only
# reader of /run/handbrake/gpu-args. In the GUI the user picks the encoder
# themselves; NVENC shows up in HandBrake's own encoder list as soon as the
# driver libraries are present.
#
# HOW AN ENCODER IS FOUND: BY ASKING THE RUNNING HANDBRAKE
#   libhb lists a hardware encoder in --help only when it is BOTH compiled in
#   AND usable on the hardware present right now (libhb/common.c:
#   hb_video_encoder_is_enabled() -> hb_nvenc_h264_available()). One --help call
#   is therefore the identifier lookup and the hardware probe at the same time,
#   and no encoder id is ever hardcoded into an argument.
#
#   Do NOT use the build-time dump /usr/local/share/handbrake-cli-help.txt for
#   this, or for any other hardware-capability question. It is recorded during
#   `docker build` on a machine with no GPU, so it never contains a single
#   hardware encoder and the lookup would fail even on a working GPU. Its
#   static option-syntax text (e.g. "--enable-hw-decoding") also cannot be
#   trusted for whether a feature was actually compiled in: measured on real
#   NVENC hardware, the dump still names 'nvdec' as a valid
#   --enable-hw-decoding value while HandBrakeCLI's own runtime diagnostic
#   says nvdec is not compiled into this build at all. See
#   docs/hardware-encoding-nvidia.md sections 1 and 3.
#
# EXTENSION POINT — this is the ONLY place a GPU plan needs to touch:
#   * add the vendor's branch to gpu_args_for_vendor()
#   * give it a candidate list and resolve it with hb_pick_encoder (never a
#     guessed name, never the build-time dump)
# The watch daemon and the init oneshot need no changes at all.
# ---------------------------------------------------------------------------
set -eu

log() { echo "[handbrake-gpu] $*" >&2; }

# NVENC encoder preference order. H.264 comes FIRST on purpose: the default
# preset (General/Very Fast 1080p30) is an x264 preset, so nvenc_h264 keeps the
# delivered codec identical and swaps only the encoder implementation — the
# whole promise of "hardware acceleration", with no surprise HEVC files that an
# older TV refuses to play. Anyone who wants HEVC appends
# "--encoder nvenc_h265" to AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS, which
# the watch daemon splices in AFTER these arguments, so the later value wins.
NVENC_CANDIDATES=(nvenc_h264 nvenc_h265)

# --- capability probes ------------------------------------------------------

# Cache of the encoder ids the running HandBrakeCLI offers on THIS machine.
# HB_ENCODERS_LOADED is a separate flag on purpose: "the list is empty" is a
# legitimate answer (a build with no hardware encoders), so emptiness must not
# be used as "not loaded yet". Overloading it would re-run HandBrakeCLI --help
# once per candidate and print the warning below once per candidate too.
HB_ENCODERS=""
HB_ENCODERS_LOADED=0

# hb_load_encoders — ask the real binary, once, what it can encode here.
#
# This is the live hardware probe, not a lookup in a recorded file: libhb only
# lists nvenc_* after hb_nvenc_h264_available() has said yes, so an id appearing
# here is proof that HandBrake can use it right now. The build-time dump is
# recorded without a GPU and would always answer "no".
#
# Call this from the PARENT shell before using hb_pick_encoder. hb_pick_encoder
# is used inside a command substitution, which runs in a subshell, so a cache
# filled there would be thrown away and every candidate would cost another
# HandBrakeCLI --help call. Filling it here means exactly one call per start.
hb_load_encoders() {
    if [ "${HB_ENCODERS_LOADED}" = "1" ]; then
        return 0
    fi
    HB_ENCODERS_LOADED=1
    local raw=""
    raw="$(HandBrakeCLI --help 2>/dev/null || true)"
    HB_ENCODERS="$(printf '%s\n' "${raw}" | awk '
        /^[[:space:]]*-e, --encoder[[:space:]]/ { inlist = 1; next }
        inlist && /^[[:space:]]*-/              { inlist = 0 }
        inlist {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            if ($0 != "") print
        }
    ')"
    if [ -z "${HB_ENCODERS}" ]; then
        log "WARNING: 'HandBrakeCLI --help' produced no encoder list — hardware detection cannot run."
    fi
}

hb_has_encoder() {
    # True when the running HandBrakeCLI offers encoder id $1 on this machine.
    hb_load_encoders
    printf '%s\n' "${HB_ENCODERS}" | grep -qxF -- "$1"
}

# hb_pick_encoder <id> [id...] — print the first id the binary offers here and
# return 0; return 1 when it offers none of them.
# Callers MUST append '|| true': under 'set -e' a command substitution that
# returns non-zero would otherwise kill the script before the error block runs.
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

hb_nvdec_compiled_in() {
    # True when THIS build's libhb actually has NVDEC compiled in.
    #
    # NOT a build-time-dump check, despite the --enable-hw-decoding help entry
    # being a static string that always names 'nvdec' as a valid value: that
    # text describes the OPTION's syntax, not whether the feature was compiled
    # in, and measuring it on real hardware proved it wrong — HandBrakeCLI
    # printed "nvdec: is not compiled into this build" on its own diagnostic
    # line while --help still listed nvdec as an --enable-hw-decoding value.
    # See docs/hardware-encoding-nvidia.md section 3 for the measured proof.
    #
    # HandBrakeCLI prints this diagnostic to stderr on every invocation once an
    # NVIDIA device is present (before this function ever runs, probes 1 and 2
    # already confirmed that), so a cheap --version call is a real, live probe:
    # "nvdec: version N is available" vs "nvdec: is not compiled into this
    # build". This is the same "ask the running binary" philosophy as the
    # encoder check, applied to decode instead of encode.
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

# --- vendor normalisation ---------------------------------------------------

VENDOR_RAW="${1:-none}"
VENDOR="$(printf '%s' "${VENDOR_RAW}" | tr '[:upper:]' '[:lower:]')"

case "${VENDOR}" in
    ""|none|off|disabled) VENDOR="none" ;;
    nvidia|nvenc)         VENDOR="nvidia" ;;
    intel|qsv)            VENDOR="intel" ;;
    amd|vce|vcn)          VENDOR="amd" ;;
    *)
        log "unrecognised GPU_VENDOR='${VENDOR_RAW}' — use none, nvidia, intel or amd"
        VENDOR="none"
        ;;
esac

gpu_args_for_vendor() {
    local encoder="" lib_encode="" lib_decode="" detail="" args=""
    case "$1" in
        none)
            printf ''
            log "GPU acceleration: none — software encoding (x264/x265)"
            ;;
        nvidia)
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
            # probe passes. hb_load_encoders runs in THIS shell (not inside the
            # command substitution below) so the --help call happens once.
            hb_load_encoders
            encoder="$(hb_pick_encoder "${NVENC_CANDIDATES[@]}" || true)"
            if [ -z "${encoder}" ]; then
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
                    args="--encoder ${encoder}"
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
                log "NOTE: every watch-folder job now encodes with '${encoder}' and overrides the video"
                log "      encoder of AUTOMATED_CONVERSION_PRESET. Put '--encoder <id>' into"
                log "      AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS to pick a different one."
            fi
            if lib_decode="$(nvidia_lib_path libnvcuvid.so.1)" && hb_nvdec_compiled_in; then
                log "NVDEC is available (${lib_decode}) but stays OFF: HandBrake disables hardware decoding"
                log "      as soon as any filter runs, which every stock preset does. Add"
                log "      '--enable-hw-decoding nvdec' to AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS to force it."
            fi
            ;;
        *)
            printf ''
            log "GPU_VENDOR='$1' requested, but this image build ships no GPU acceleration for that vendor yet."
            log "Falling back to software encoding. Hardware encoding for that vendor arrives in a later release."
            ;;
    esac
}

printf '%s' "${VENDOR}" > /run/handbrake/gpu-vendor 2>/dev/null || true
gpu_args_for_vendor "${VENDOR}"
