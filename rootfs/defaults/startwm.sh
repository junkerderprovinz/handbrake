#!/usr/bin/env bash
# Overrides the Selkies base image's /defaults/startwm.sh, which sends the whole
# desktop session to /dev/null and would swallow the ghb launch loop and its
# crash diagnostics. ghb's own noisy output already goes to
# /config/handbrake-gui.log, so only a handful of status lines per container
# lifetime reach this stdio.

exec dbus-launch --exit-with-session /usr/bin/openbox-session
