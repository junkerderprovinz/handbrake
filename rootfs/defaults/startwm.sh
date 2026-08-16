#!/usr/bin/env bash
# Overrides the Selkies base image's /defaults/startwm.sh for ONE reason: the
# base redirects the whole desktop session to /dev/null (`> /dev/null 2>&1`),
# which would swallow every line our autostart writes — the ghb launch loop and
# its crash diagnostics would never reach the container log. Identical to the
# base script otherwise, including the Nvidia/zink block.
#
# ghb's own noisy output is NOT the reason to redirect here: the autostart
# already sends it to /config/handbrake-gui.log, so what remains on this stdio
# is a handful of status lines per container lifetime.

# Enable Nvidia GPU support if detected
if which nvidia-smi > /dev/null 2>&1 && ls -A /dev/dri 2>/dev/null && [ "${DISABLE_ZINK}" == "false" ]; then
  export LIBGL_KOPPER_DRI2=1
  export MESA_LOADER_DRIVER_OVERRIDE=zink
  export GALLIUM_DRIVER=zink
fi

# Start the desktop. Output stays on the service's stdio so it lands in the
# docker log.
exec dbus-launch --exit-with-session /usr/bin/openbox-session
