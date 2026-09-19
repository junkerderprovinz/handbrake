#!/usr/bin/env bash
# Opens a terminal on the Selkies web desktop, bound to Ctrl+Alt+T by
# handbrake-web.sh when WEB_TERMINAL=1.
#
# A keybind, because the base's openbox rc.xml maximises every window, so
# HandBrake covers the desktop and the root menu with its xterm entry can never
# be right-clicked. xterm, because the Selkies web client has no terminal page
# and adding one would mean forking /usr/share/selkies/web, which the base
# recreates on every start; xterm ships in the base and streams like the rest
# of the desktop.
set -u

SHELL_PATH="${WEB_TERMINAL_SHELL_PATH:-/bin/bash}"
if [ ! -x "${SHELL_PATH}" ]; then
    echo "[handbrake-terminal] WEB_TERMINAL_SHELL_PATH='${SHELL_PATH}' is not executable, falling back to /bin/sh" >&2
    SHELL_PATH="/bin/sh"
fi

# Match the container's theme instead of xterm's white-on-black default.
case "${GTK_THEME:-Adwaita:dark}" in
    *:dark) BG="#1e1e1e"; FG="#e3e3e3"; CUR="#e3e3e3" ;;
    *)      BG="#ffffff"; FG="#1f2328"; CUR="#1f2328" ;;
esac

exec xterm \
    -class HandBrakeTerminal \
    -title "HandBrake terminal" \
    -fa "DejaVu Sans Mono" -fs 11 \
    -bg "${BG}" -fg "${FG}" -cr "${CUR}" \
    -geometry 110x30 \
    -sb -sl 5000 \
    -e "${SHELL_PATH}"
