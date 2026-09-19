#!/usr/bin/env bash
# Usage: handbrake-theme.sh <dark|light>
#
# Applies HandBrake's native dark mode. The GUI is GTK4 without libadwaita, so
# dark means the stock Adwaita dark variant inside libgtk-4-1, the same
# mechanism as jlesage's DARK_MODE.
#
# GTK_THEME carries the choice because ghb calls
# color_scheme_set_async(APP_PREFERS_LIGHT) at startup (gtk/src/application.c),
# which turns gtk-application-prefer-dark-theme off whenever the desktop portal
# reports no preference, and this container has no portal. GTK4 reads
# $GTK_THEME before that setting. As a result HandBrake's in-app light/dark
# toggle has no visible effect; HANDBRAKE_THEME decides.
set -eu

log() { echo "[handbrake-theme] $*"; }

REQUESTED="${1:-dark}"
case "$(printf '%s' "${REQUESTED}" | tr '[:upper:]' '[:lower:]')" in
    light|adwaita|breezelight)
        THEME="light"
        GTK_THEME_VALUE="Adwaita"
        PREFER_DARK="0"
        ;;
    *)
        THEME="dark"
        GTK_THEME_VALUE="Adwaita:dark"
        PREFER_DARK="1"
        ;;
esac

CONFIG_HOME="/config/.config"
PROFILE_D="/config/.profile.d"

mkdir -p "${CONFIG_HOME}/gtk-3.0" "${CONFIG_HOME}/gtk-4.0" "${PROFILE_D}"

# settings.ini makes every other GTK app on the desktop follow the same choice;
# ghb itself is pinned by GTK_THEME.
for ver in 3.0 4.0; do
    cat > "${CONFIG_HOME}/gtk-${ver}/settings.ini" <<EOF
[Settings]
gtk-theme-name=Adwaita
gtk-icon-theme-name=Adwaita
gtk-application-prefer-dark-theme=${PREFER_DARK}
gtk-font-name=DejaVu Sans 10
EOF
done

# The Selkies desktop session does not inherit /run/s6/container_environment,
# so /defaults/autostart sources this snippet before launching ghb.
cat > "${PROFILE_D}/handbrake-theme.sh" <<EOF
# Written by handbrake-theme.sh on every start, do not edit.
export GTK_THEME="${GTK_THEME_VALUE}"
export HANDBRAKE_THEME="${THEME}"
EOF
chmod 0644 "${PROFILE_D}/handbrake-theme.sh"

# Every s6 service inherits the container environment, and the CI smoke gate
# checks GTK_THEME there.
mkdir -p /run/s6/container_environment
printf '%s' "${GTK_THEME_VALUE}" > /run/s6/container_environment/GTK_THEME
printf '%s' "${THEME}"           > /run/s6/container_environment/HANDBRAKE_THEME

chown -R abc:abc "${CONFIG_HOME}/gtk-3.0" "${CONFIG_HOME}/gtk-4.0" "${PROFILE_D}" 2>/dev/null || true

log "theme=${THEME} GTK_THEME=${GTK_THEME_VALUE} (native GTK4 Adwaita)"
