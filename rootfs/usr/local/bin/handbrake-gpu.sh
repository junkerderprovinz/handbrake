#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# handbrake-gpu.sh <vendor>
# ---------------------------------------------------------------------------
# Resolves GPU_VENDOR into the extra HandBrakeCLI arguments used for hardware
# encoding. Prints the argument string on STDOUT (empty = software encoding) and
# a human-readable decision line on STDERR.
#
# v1 SHIPS NO GPU ACCELERATION. Every vendor other than "none" resolves to an
# empty argument string plus a loud warning, so a user who sets GPU_VENDOR early
# gets software encoding and a clear explanation instead of a silent failure.
#
# EXTENSION POINT — this is the ONLY place a GPU plan needs to touch:
#   * add the vendor's branch to gpu_args_for_vendor()
#   * emit the encoder identifier taken from
#     /usr/local/share/handbrake-cli-help.txt (never a guessed name)
#   * install the vendor runtime libraries in the Dockerfile
# The watch daemon and the init oneshot need no changes at all.
# ---------------------------------------------------------------------------
set -eu

VENDOR_RAW="${1:-none}"
VENDOR="$(printf '%s' "${VENDOR_RAW}" | tr '[:upper:]' '[:lower:]')"

case "${VENDOR}" in
    ""|none|off|disabled) VENDOR="none" ;;
    nvidia|nvenc)         VENDOR="nvidia" ;;
    intel|qsv)            VENDOR="intel" ;;
    amd|vce|vcn)          VENDOR="amd" ;;
    *)
        echo "[handbrake-gpu] unrecognised GPU_VENDOR='${VENDOR_RAW}' — use none, nvidia, intel or amd" >&2
        VENDOR="none"
        ;;
esac

gpu_args_for_vendor() {
    case "$1" in
        none)
            printf ''
            echo "[handbrake-gpu] GPU acceleration: none — software encoding (x264/x265)" >&2
            ;;
        *)
            printf ''
            echo "[handbrake-gpu] GPU_VENDOR='$1' requested, but this image build ships no GPU acceleration yet." >&2
            echo "[handbrake-gpu] Falling back to software encoding. Hardware encoding arrives in a later release." >&2
            ;;
    esac
}

printf '%s' "${VENDOR}" > /run/handbrake/gpu-vendor 2>/dev/null || true
gpu_args_for_vendor "${VENDOR}"
