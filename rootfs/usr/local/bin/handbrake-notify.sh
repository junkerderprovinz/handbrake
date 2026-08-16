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
