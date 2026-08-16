#!/bin/sh
# ---------------------------------------------------------------------------
# handbrake-gui-hook.sh <finished-output-file>
# ---------------------------------------------------------------------------
# Target of HandBrake's own "Send file to" preference (SendFileTo /
# SendFileToTarget in ghb's preferences.json), wired up by
# init-handbrake-gui-hooks/run. Confirmed against HandBrake 1.11.2 GTK source
# (gtk/src/callbacks.c, send_to_external_app()): it is invoked as
# "<SendFileToTarget> <file>" with exactly ONE argument, the finished output
# file, and ONLY when the job succeeded (GHB_ERROR_NONE) — never on failure or
# cancellation, and never with the source file or the preset name.
#
# That is a real, narrower contract than the watch-folder hooks: this is what
# HandBrake's own GUI hands us, not something this container invented.
# post_manual_conversion.sh therefore gets a SEPARATE, shorter contract
# ($1 = output file only) rather than being forced into the four-argument
# watch-folder shape it cannot actually fill in.
# ---------------------------------------------------------------------------
set -u

HOOK="/config/hooks/post_manual_conversion.sh"
JOB_LOG="/config/handbrake-watch.log"

[ -f "${HOOK}" ] || exit 0

{
    echo "=== $(date -Is) hook post_manual_conversion.sh $*"
} >> "${JOB_LOG}" 2>/dev/null

/bin/sh "${HOOK}" "$@" >> "${JOB_LOG}" 2>&1
exit 0
