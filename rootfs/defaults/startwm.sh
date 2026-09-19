#!/usr/bin/env bash
# Overrides the Selkies base image's /defaults/startwm.sh, which sends the whole
# desktop session to /dev/null and would swallow the ghb launch loop and its
# crash diagnostics. Otherwise it matches the base script, Nvidia/zink block
# included. ghb's own noisy output already goes to /config/handbrake-gui.log, so
# only a handful of status lines per container lifetime reach this stdio.

if which nvidia-smi > /dev/null 2>&1 && ls -A /dev/dri 2>/dev/null && [ "${DISABLE_ZINK}" == "false" ]; then
  export LIBGL_KOPPER_DRI2=1
  export MESA_LOADER_DRIVER_OVERRIDE=zink
  export GALLIUM_DRIVER=zink
fi

exec dbus-launch --exit-with-session /usr/bin/openbox-session
