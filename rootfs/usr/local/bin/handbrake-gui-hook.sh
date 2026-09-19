#!/bin/sh
# Usage: handbrake-gui-hook.sh <finished-output-file>
#
# Target of ghb's own "Send file to" preference (SendFileTo, SendFileToTarget),
# wired up by init-handbrake. ghb calls it with the finished output file as the
# only argument, and only after a successful job (send_to_external_app() in
# gtk/src/callbacks.c, HandBrake 1.11.2): never on failure or cancellation, and
# never with the source or the preset. post_manual_conversion.sh therefore gets
# just $1 instead of the four arguments of the watch-folder hooks.
set -u

HOOK="/config/hooks/post_manual_conversion.sh"
JOB_LOG="/config/handbrake-watch.log"

[ -f "${HOOK}" ] || exit 0

{
    echo "=== $(date -Is) hook post_manual_conversion.sh $*"
} >> "${JOB_LOG}" 2>/dev/null

/bin/sh "${HOOK}" "$@" >> "${JOB_LOG}" 2>&1
exit 0
