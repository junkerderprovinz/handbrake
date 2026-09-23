# syntax=docker/dockerfile:1.27@sha256:bde3983e9c939224420ddaf6b784cc30e09b035a4dea01f581230c50809f372e
#
# HandBrake for Unraid, community edition, on the LinuxServer Selkies base:
# HandBrake's GTK4 GUI on a web desktop, HandBrakeCLI with a watch-folder
# daemon, and HandBrake's native dark mode on by default.
#
# Repository:  https://github.com/junkerderprovinz/handbrake
# License:     AGPL-3.0-only (this wrapper), HandBrake upstream is GPL-2.0
#
# The flavor is pinned because the Selkies base makes breaking changes between
# flavors; ubunturesolute (Ubuntu 26.04 LTS) matches krusader and jdownloader.
# Its universe component carries HandBrake 1.11, fresher than the official
# handbrake-releases PPA, which has published nothing past focal.
ARG BASE_TAG=ubunturesolute@sha256:6cfa54196b6e0dade64f5e51517fd12c4275ceda7519c0e18ad168cb4508c050

FROM ghcr.io/linuxserver/baseimage-selkies:${BASE_TAG}

LABEL maintainer="junkerderprovinz"
LABEL org.opencontainers.image.title="handbrake"
LABEL org.opencontainers.image.description="HandBrake for Unraid: the full video transcoder in your browser via Selkies, dark by default, with an automated watch-folder converter"
LABEL org.opencontainers.image.source="https://github.com/junkerderprovinz/handbrake"
LABEL org.opencontainers.image.licenses="AGPL-3.0-only"
LABEL org.opencontainers.image.vendor="junkerderprovinz"

# TITLE feeds the PWA manifest and SELKIES_UI_TITLE the tab and sidebar title;
# this base needs both.
#
# Selkies turns basic auth on by default and will not start without a password,
# so SELKIES_ENABLE_BASIC_AUTH=false keeps a container without one free of a
# login; a real CUSTOM_USER/PASSWORD still enables nginx basic auth.
#
# RESTART_APP stays off, unlike the sibling Selkies images: rootfs/defaults/
# autostart supervises the GUI itself with a fast-exit counter and a capped
# backoff, and two supervisors would race for the same process. If that loop is
# ever removed, set RESTART_APP=true here and launch ghb without `exec`.
ENV TITLE="HandBrake" \
    SELKIES_UI_TITLE="HandBrake" \
    SELKIES_ENABLE_BASIC_AUTH="false"

# handbrake installs /usr/bin/ghb and handbrake-cli /usr/bin/HandBrakeCLI, both
# from Ubuntu's universe component, which is added only when it is missing.
RUN set -eux; \
    if ! grep -qE '^Components:.*\buniverse\b' /etc/apt/sources.list.d/ubuntu.sources; then \
        sed -i '/^Components:/ s/$/ universe/' /etc/apt/sources.list.d/ubuntu.sources; \
    fi; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        handbrake \
        handbrake-cli \
        # Adwaita dark is built into libgtk-4-1. adwaita-icon-theme supplies the
        # symbolic icons of ghb's header bar, which render as empty boxes
        # without it.
        libgtk-4-1 \
        adwaita-icon-theme \
        hicolor-icon-theme \
        # ghb probes the desktop portal over the session bus.
        dbus-x11 \
        # xsetroot paints the desktop background. The Selkies base starts Xvfb
        # with no keymap, and without one the web client's paste path never
        # binds Shift, so pasted capitals arrive in lowercase
        # (junkerderprovinz/krusader#27).
        x11-xserver-utils \
        x11-xkb-utils \
        xkb-data \
        # Without a built fontconfig cache GTK draws blank strips on first start.
        fontconfig \
        fonts-dejavu-core \
        fonts-liberation2 \
        fonts-noto-core \
        fonts-noto-color-emoji \
        locales \
        coreutils \
        findutils \
        # procps supplies pgrep, which svc-handbrake-ready and the CI smoke gate
        # use to prove that ghb is alive.
        procps \
        # openbox-xdg-autostart needs PyXDG.
        python3-xdg; \
    fc-cache -f >/dev/null 2>&1 || true; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Generate the default locale so ghb's gettext catalogue resolves.
RUN set -eux; \
    sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen; \
    locale-gen en_US.UTF-8

# Intel Quick Sync runtime, amd64 only. Ubuntu builds handbrake-cli with
# --enable-qsv on amd64, and the package already pulls in the oneVPL dispatcher
# (libvpl2) and libva. What it cannot depend on, because both are hardware
# specific, is the implementation and the VA-API driver:
#
#   libmfx-gen1.2                   oneVPL GPU runtime (Gen12+, Xe, Arc)
#   intel-media-va-driver-non-free  iHD driver. Decoding works with the free
#                                   build, encoding needs this one (Debian wiki,
#                                   HardwareVideoAcceleration). It lives in
#                                   multiverse. Listed in NOTICE.
#   vainfo, libvpl-tools            diagnostics for /config/handbrake-gpu.log,
#                                   the only evidence an Intel user can send,
#                                   since the maintainer cannot test this path.
#
# arm64 has no Quick Sync and none of these packages, so there the layer only
# logs a line.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    if [ "${arch}" != "amd64" ]; then \
        echo "handbrake: Intel QSV runtime skipped on ${arch} (Quick Sync is x86-64 only)"; \
        exit 0; \
    fi; \
    if ! grep -qE '^Components:.*\bmultiverse\b' /etc/apt/sources.list.d/ubuntu.sources; then \
        sed -i '/^Components:/ s/$/ multiverse/' /etc/apt/sources.list.d/ubuntu.sources; \
    fi; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        libmfx-gen1.2 \
        intel-media-va-driver-non-free \
        vainfo \
        libvpl-tools; \
    [ -e /usr/lib/x86_64-linux-gnu/dri/iHD_drv_video.so ] \
        || { echo "ERROR: iHD_drv_video.so missing after installing intel-media-va-driver-non-free"; exit 1; }; \
    command -v vainfo >/dev/null || { echo "ERROR: vainfo missing"; exit 1; }; \
    command -v vpl-inspect >/dev/null || { echo "ERROR: vpl-inspect missing (libvpl-tools layout changed)"; exit 1; }; \
    echo "handbrake: QSV runtime installed ->"; \
    dpkg-query -W -f '${Package} ${Version}\n' libmfx-gen1.2 intel-media-va-driver-non-free libvpl2; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Fail if the package layout moves, and record what this build can do.
# docs/handbrake-capabilities.md is based on these dumps, and encoder ids are
# read from /usr/local/share/handbrake-cli-help.txt rather than guessed.
RUN set -eux; \
    [ -x /usr/bin/ghb ] || { echo "ERROR: /usr/bin/ghb missing, the 'handbrake' package layout changed"; exit 1; }; \
    [ -x /usr/bin/HandBrakeCLI ] || { echo "ERROR: /usr/bin/HandBrakeCLI missing, the 'handbrake-cli' package layout changed"; exit 1; }; \
    HandBrakeCLI --version > /usr/local/share/handbrake-version.txt 2>&1; \
    HandBrakeCLI --help > /usr/local/share/handbrake-cli-help.txt 2>&1; \
    HandBrakeCLI --preset-list > /usr/local/share/handbrake-preset-list.txt 2>&1; \
    grep -q 'Very Fast 1080p30' /usr/local/share/handbrake-preset-list.txt \
        || { echo "ERROR: preset 'Very Fast 1080p30' not in --preset-list, the default AUTOMATED_CONVERSION_PRESET would fail"; exit 1; }; \
    echo "handbrake: $(head -n 1 /usr/local/share/handbrake-version.txt)"; \
    echo "handbrake: encoders ->"; \
    sed -n '/--encoder/,/^$/p' /usr/local/share/handbrake-cli-help.txt

# Created in the image so a bind mount is optional, and so docker cp or the CI
# smoke gate can drop a file into /watch on a bare run.
RUN set -eux; \
    mkdir -p /storage /watch /watch2 /watch3 /watch4 /watch5 /output /staging; \
    chmod 0777 /watch /watch2 /watch3 /watch4 /watch5 /output /staging

COPY rootfs/ /

# rootfs/ ships svc-xorg/dependencies.d/init-dpi so the oneshot settles the DPI
# before Xvfb starts. If a base update renamed svc-xorg, the COPY above
# would create a service directory with no `type` file, s6-rc-compile would
# abort and every container would exit at boot while the build stays green.
# Checking for the base's own `type` file turns that into a build error.
RUN set -eux; \
    t=/etc/s6-overlay/s6-rc.d/svc-xorg/type; \
    [ -f "$t" ] || { echo "ERROR: $t missing, the selkies base renamed or dropped svc-xorg; re-point rootfs/etc/s6-overlay/s6-rc.d/svc-xorg/dependencies.d/init-dpi at the new service"; exit 1; }; \
    echo "handbrake: dpi oneshot ordered before svc-xorg"

# Init-log banner. tr drops Windows CR bytes so the block characters render
# whichever editor saved the file.
COPY .github/assets/banner-raw.txt /usr/local/share/banner-raw.txt
RUN tr -d '\r' < /usr/local/share/banner-raw.txt > /usr/local/share/banner.txt

# Leaves print-banner.sh as the only branding in the init log. The
# linuxserver.io logo comes from init-adduser's `branding` file, which is
# emptied; the donation lines are echoed by init-adduser/run itself and are
# deleted there. Its GID/UID block stays because it confirms the applied
# PUID/PGID.
RUN set -eux; \
    : > /etc/s6-overlay/s6-rc.d/init-adduser/branding 2>/dev/null || true; \
    run=/etc/s6-overlay/s6-rc.d/init-adduser/run; \
    if [ -f "$run" ]; then \
        sed -i -e '/To support LSIO projects visit:/d' -e '\#linuxserver\.io/donate#d' "$run"; \
    fi

# init-nginx copies /usr/share/selkies/www/icon.png to favicon.ico and icon.png
# in the web root on every start, so replacing that one PNG brands the whole
# web UI. The check fails the build if the base moves it.
COPY .github/assets/icon.png /usr/local/share/handbrake-icon.png
RUN set -eux; \
    dst=/usr/share/selkies/www/icon.png; \
    [ -f "$dst" ] || { echo "ERROR: $dst missing; the selkies base layout changed, update the branding override"; exit 1; }; \
    cp /usr/local/share/handbrake-icon.png "$dst"; \
    echo "handbrake: branded selkies icon at $dst"

# A Windows checkout carries no mode bits. The hook .example files are left
# out: hooks run as `/bin/sh <file>`, and a template that is not executable is
# a second reminder that it is not a live hook.
RUN chmod +x \
    /usr/local/bin/print-banner.sh \
    /etc/s6-overlay/s6-rc.d/init-dpi/run \
    /usr/local/bin/handbrake-theme.sh \
    /usr/local/bin/handbrake-gpu.sh \
    /usr/local/bin/handbrake-watch.sh \
    /usr/local/bin/handbrake-web.sh \
    /usr/local/bin/handbrake-terminal.sh \
    /usr/local/bin/handbrake-notify.sh \
    /usr/local/bin/handbrake-gui-hook.sh \
    /etc/s6-overlay/s6-rc.d/init-handbrake/run \
    /etc/s6-overlay/s6-rc.d/init-handbrake-libdvdcss/run \
    /etc/s6-overlay/s6-rc.d/init-handbrake-web/run \
    /etc/s6-overlay/s6-rc.d/init-handbrake-web-post/run \
    /etc/s6-overlay/s6-rc.d/svc-handbrake-watch/run \
    /etc/s6-overlay/s6-rc.d/svc-handbrake-ready/run \
    /defaults/autostart \
    /defaults/startwm.sh

# The watch daemon traps SIGTERM to cancel a running transcode and remove its
# partial output; s6's default of 3 s would SIGKILL through that cleanup.
ENV S6_KILL_GRACETIME=15000 \
    S6_SERVICES_GRACETIME=15000

# HANDBRAKE_THEME  dark (default) or light, turned into GTK_THEME by
#                  handbrake-theme.sh. Dark is HandBrake's native GTK dark mode.
# GPU_VENDOR       none (default), nvidia, intel or amd, resolved by
#                  handbrake-gpu.sh into /run/handbrake/gpu-args.
#                  nvidia needs the NVIDIA container runtime (--runtime=nvidia)
#                  plus NVIDIA_DRIVER_CAPABILITIES=compute,video,utility.
#                  intel needs /dev/dri passed through (amd64 only).
#                  amd needs a HandBrakeCLI built with --enable-vce and AMD's
#                  proprietary AMF runtime, neither of which this image can
#                  ship; see Dockerfile.gpu. A vendor that cannot be honoured
#                  logs why and falls back to software encoding.
# APP_NICENESS     nice level for ghb and every HandBrakeCLI run, 0 to 19
#                  (negative values need privileges and are clamped to 0).
# KEYBOARD_LAYOUT  X keyboard layout loaded at session start.
ENV HANDBRAKE_THEME=dark \
    GPU_VENDOR=none \
    APP_NICENESS=0 \
    KEYBOARD_LAYOUT=us

# The names match jlesage/docker-handbrake so migrating users keep their
# template values. AUTOMATED_CONVERSION_WATCH_DIR=AUTO scans /watch and /watch2
# up to /watchN (AUTOMATED_CONVERSION_MAX_WATCH_FOLDERS); any other value is
# the single watch folder.
ENV AUTOMATED_CONVERSION=1 \
    AUTOMATED_CONVERSION_PRESET="General/Very Fast 1080p30" \
    AUTOMATED_CONVERSION_FORMAT=mp4 \
    AUTOMATED_CONVERSION_KEEP_SOURCE=1 \
    AUTOMATED_CONVERSION_VIDEO_FILE_EXTENSIONS= \
    AUTOMATED_CONVERSION_WATCH_DIR=AUTO \
    AUTOMATED_CONVERSION_MAX_WATCH_FOLDERS=5 \
    AUTOMATED_CONVERSION_OUTPUT_DIR=/output \
    AUTOMATED_CONVERSION_OUTPUT_SUBDIR= \
    AUTOMATED_CONVERSION_OVERWRITE_OUTPUT=0 \
    AUTOMATED_CONVERSION_SOURCE_STABLE_TIME=5 \
    AUTOMATED_CONVERSION_CHECK_INTERVAL=5 \
    AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS=

# Empty means <output>/.handbrake-staging, as in jlesage's image. Pointing it
# at /staging on a cache pool keeps the array out of the write path while a
# transcode runs.
ENV AUTOMATED_CONVERSION_STAGING_DIR=

# Space-separated directory names pruned anywhere in a watch-folder scan, such
# as sync-client metadata folders.
ENV AUTOMATED_CONVERSION_IGNORE_DIRECTORIES=

# A daily window as HH-HH on a 24 h clock, e.g. 22-06 for overnight only.
# Empty means always active.
ENV AUTOMATED_CONVERSION_ACTIVE_HOURS=

# The WEB_* variables of jlesage/docker-handbrake, mapped by handbrake-web.sh
# onto what the Selkies base already provides.
#
# WEB_FILE_MANAGER               1 (default) publishes the data mounts at
#                                https://<host>:3001/files/ for browsing,
#                                download and upload; 0 removes the endpoint
#                                and the sidebar panel. On by default (jlesage:
#                                off) because anyone who reaches the WebUI
#                                already has a desktop with the same files.
# WEB_FILE_MANAGER_ALLOWED_PATHS AUTO means the watch folders, the output
#                                folder and /storage, whichever exist; otherwise
#                                a comma-separated list of absolute paths.
#                                /config is refused because it holds the
#                                WebUI's TLS private key.
# WEB_FILE_MANAGER_DENIED_PATHS  Comma-separated paths inside the allowed ones
#                                that answer 403.
# WEB_TERMINAL                   0 (default) makes the base chmod every terminal
#                                binary to 0000; 1 enables Ctrl+Alt+T on the
#                                web desktop. The keybind is needed because the
#                                maximised HandBrake window hides the openbox
#                                root menu.
# WEB_TERMINAL_SHELL_PATH        Shell for that terminal. bash rather than
#                                jlesage's /bin/sh, which is dash here, with no
#                                history and no line editing.
# WEB_NOTIFICATION               1 shows conversion results on the web desktop
#                                through dunst, inside the streamed session; the
#                                Selkies client has no bridge for browser
#                                notifications.
ENV WEB_FILE_MANAGER=1 \
    WEB_FILE_MANAGER_ALLOWED_PATHS=AUTO \
    WEB_FILE_MANAGER_DENIED_PATHS= \
    WEB_TERMINAL=0 \
    WEB_TERMINAL_SHELL_PATH=/bin/bash \
    WEB_NOTIFICATION=0

# Audio output stays on for HandBrake's preview player, which is why jlesage's
# WEB_AUDIO has no counterpart here. A microphone has no use in a transcoder.
ENV SELKIES_MICROPHONE_ENABLED=false

# GTK scales only its text by the DPI Selkies hands a HiDPI browser, so a
# laptop streaming in physical pixels shows half-size icons next to full-size
# text, and widgets grown at that DPI stay grown when a 100 % display connects
# next. Streaming every browser at its CSS size with the DPI fixed at 96 keeps
# one consistent size on any display. HiDPI can still be switched on per
# browser in the Selkies sidebar.
ENV SELKIES_USE_CSS_SCALING="true" \
    SELKIES_SCALING_DPI="96"

# The base's init-device-perms adds the container user to the owning group of
# every device listed here and makes the node group-writable; the base ships no
# default. /dev/sg* is left out: on a NAS the generic-SCSI group owns every raw
# disk, so joining it would expose the whole array, and libdvdread and
# libdvdnav only need /dev/srX.
ENV ATTACHED_DEVICES_PERMS="/dev/sr*"

# Opt-in CSS decryption for retail DVDs. libdvdcss is not shipped and is not in
# the Ubuntu archive; with INSTALL_LIBDVDCSS=true the init-handbrake-libdvdcss
# oneshot fetches the release tarball from VideoLAN, checks it against a pinned
# checksum, compiles it on this machine and caches the result under /config
# (about 15 seconds on the first start). Whether that is lawful depends on where
# you are, which is why the operator flips the switch. See README section 12.
ENV INSTALL_LIBDVDCSS=false

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Any HTTP status from the WebUI counts as up; only "000" (no answer) fails.
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD ["/bin/sh", "-c", "c=$(curl -ks -o /dev/null -w '%{http_code}' --max-time 5 https://127.0.0.1:${CUSTOM_HTTPS_PORT:-3001}/); [ \"$c\" != \"000\" ] || exit 1"]

# Build provenance, readable with `docker exec handbrake cat /etc/handbrake-build`.
# The last layer, because BUILD_SHA changes on every commit and would bust the
# cache for every layer after it.
ARG BUILD_SHA=dev
ARG BUILD_DATE=unknown
RUN echo "sha=${BUILD_SHA}"   >  /etc/handbrake-build && \
    echo "date=${BUILD_DATE}" >> /etc/handbrake-build

# Ports are exposed by the base image (3000/HTTP, 3001/HTTPS).
