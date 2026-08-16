#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# handbrake-theme.sh <dark|light>
# ---------------------------------------------------------------------------
# Applies HandBrake's NATIVE dark mode. HandBrake's GUI is GTK4 (no libadwaita),
# so "dark mode" here means the stock Adwaita dark variant that ships inside
# libgtk-4-1 — exactly the mechanism jlesage's DARK_MODE uses, and exactly what
# a well-behaved GTK app picks up on any desktop.
#
# WHY THE ENV VAR IS THE PRIMARY MECHANISM
#   ghb calls color_scheme_set_async(APP_PREFERS_LIGHT) at startup
#   (gtk/src/application.c) which sets GtkSettings:gtk-application-prefer-dark-
#   theme to FALSE whenever the freedesktop desktop portal reports no
#   preference — and this container has no portal. A settings.ini
#   "gtk-application-prefer-dark-theme=1" is therefore overwritten seconds after
#   the app starts. GTK4's theme resolution reads $GTK_THEME FIRST and returns
#   before it ever looks at the setting, so the env var wins deterministically.
#
# TRADE-OFF, DOCUMENT IT IN THE README: because $GTK_THEME wins, HandBrake's own
# in-app light/dark toggle has no visible effect. The container's
# HANDBRAKE_THEME variable is the single source of truth for the theme.
# ---------------------------------------------------------------------------
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

# Second layer: a real settings file, so every OTHER GTK app on the desktop
# (file dialogs, future additions) follows the same choice even if it never
# reads $GTK_THEME. Harmless for ghb, which the env var already pins.
for ver in 3.0 4.0; do
    cat > "${CONFIG_HOME}/gtk-${ver}/settings.ini" <<EOF
[Settings]
gtk-theme-name=Adwaita
gtk-icon-theme-name=Adwaita
gtk-application-prefer-dark-theme=${PREFER_DARK}
gtk-font-name=DejaVu Sans 10
EOF
done

# The Selkies desktop session does NOT inherit /run/s6/container_environment,
# so the value is additionally written as a profile snippet that
# /defaults/autostart sources right before launching ghb.
cat > "${PROFILE_D}/handbrake-theme.sh" <<EOF
# Written by handbrake-theme.sh — do not edit, it is rewritten on every start.
export GTK_THEME="${GTK_THEME_VALUE}"
export HANDBRAKE_THEME="${THEME}"
EOF
chmod 0644 "${PROFILE_D}/handbrake-theme.sh"

# Primary layer: the s6 container environment, inherited by every s6 service
# (the watch daemon, the READY service) and asserted by the CI smoke gate.
mkdir -p /run/s6/container_environment
printf '%s' "${GTK_THEME_VALUE}" > /run/s6/container_environment/GTK_THEME
printf '%s' "${THEME}"           > /run/s6/container_environment/HANDBRAKE_THEME

chown -R abc:abc "${CONFIG_HOME}/gtk-3.0" "${CONFIG_HOME}/gtk-4.0" "${PROFILE_D}" 2>/dev/null || true

log "theme=${THEME} GTK_THEME=${GTK_THEME_VALUE} (native GTK4 Adwaita)"
