#!/usr/bin/env bash
# Usage: handbrake-notify.sh <urgency> <summary> [body]
#
# Shows a notification on the Selkies web desktop for handbrake-watch.sh. Never
# fatal, never blocking, and silent unless WEB_NOTIFICATION is on.
#
# These are desktop notifications drawn by dunst inside the streamed session,
# visible while the HandBrake tab is open. jlesage's image raises browser
# notifications through a bridge in its web client; the Selkies client has none,
# and adding one would mean forking /usr/share/selkies/web, which the base
# recreates on every start.
#
# The session runs as abc under its own dbus-launch, so its DISPLAY and
# DBUS_SESSION_BUS_ADDRESS are not in this environment: /defaults/autostart
# writes them to /run/handbrake/session-env and this script reads them back.
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

# Without a running dunst, notify-send waits for a D-Bus activation that never
# happens, and a stuck notification must not stall the conversion loop.
timeout 5 notify-send \
    --app-name="HandBrake" \
    --icon="/usr/local/share/handbrake-icon.png" \
    --urgency="${1:-normal}" \
    -- "${2:-HandBrake}" "${3:-}" 2>/dev/null || true

exit 0
