# syntax=docker/dockerfile:1.26
#
# HandBrake for Unraid – community edition (Selkies)
# --------------------------------------------------
# Built on the LinuxServer Selkies base image: X11 + openbox, streamed to the
# browser through a hybrid VNC/H.264 pipeline with a modern web client.
#
# Features added on top of the base image:
#   * HandBrake's own GTK4 GUI (ghb) on a web desktop
#   * HandBrakeCLI + an automated watch-folder conversion daemon
#   * HandBrake's NATIVE dark mode (stock GTK4 Adwaita dark), on by default
#
# Repository:  https://github.com/junkerderprovinz/handbrake
# License:     AGPL-3.0-only (this wrapper) – HandBrake upstream is GPL-2.0
#
# Flavor-PINNED on purpose: the Selkies base makes deliberate breaking changes
# between flavors; ubunturesolute = Ubuntu 26.04 LTS, the same flavor as
# krusader and jdownloader. Ubuntu 26.04 universe carries HandBrake 1.11, which
# is why no third-party PPA is used: the official handbrake-releases PPA
# (ppa:stebbins/handbrake-releases) has published nothing newer than focal, so
# the distro package is BOTH the fresher and the better-maintained channel here.
ARG BASE_TAG=ubunturesolute

FROM ghcr.io/linuxserver/baseimage-selkies:${BASE_TAG}

LABEL maintainer="junkerderprovinz"
LABEL org.opencontainers.image.title="handbrake"
LABEL org.opencontainers.image.description="HandBrake for Unraid — the full video transcoder in your browser via Selkies, dark by default, with an automated watch-folder converter"
LABEL org.opencontainers.image.source="https://github.com/junkerderprovinz/handbrake"
LABEL org.opencontainers.image.licenses="AGPL-3.0-only"
LABEL org.opencontainers.image.vendor="junkerderprovinz"

# TITLE feeds the PWA manifest; SELKIES_UI_TITLE is the visible tab/sidebar
# title of the Selkies web client — both must be set on this base.
#
# SELKIES_ENABLE_BASIC_AUTH=false: Selkies' server enables basic auth by DEFAULT
# with the well-known default credentials (ubuntu / mypasswd), which would pop a
# login on a container that never set a password — worse, an insecure default
# one. No login by default; the init-nologin oneshot additionally drops an empty
# PASSWORD/CUSTOM_USER before nginx starts, so Unraid's blank template fields
# cannot turn into a login prompt. A real CUSTOM_USER/PASSWORD still enables
# nginx basic auth on the single reachable entry point.
ENV TITLE="HandBrake" \
    SELKIES_UI_TITLE="HandBrake" \
    SELKIES_ENABLE_BASIC_AUTH="false"

# ---------------------------------------------------------------------------
# HandBrake + GTK4 runtime + fonts
# ---------------------------------------------------------------------------
# handbrake       -> /usr/bin/ghb              (the official GTK4 GUI)
# handbrake-cli   -> /usr/bin/HandBrakeCLI     (used by the watch-folder daemon)
# Both live in Ubuntu's "universe" component, which is enabled here defensively
# (idempotent: only appended when it is not already listed).
RUN set -eux; \
    if ! grep -qE '^Components:.*\buniverse\b' /etc/apt/sources.list.d/ubuntu.sources; then \
        sed -i '/^Components:/ s/$/ universe/' /etc/apt/sources.list.d/ubuntu.sources; \
    fi; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        # HandBrake itself: GTK4 GUI + CLI
        handbrake \
        handbrake-cli \
        # GTK4 runtime bits the GUI needs on a bare openbox desktop. The stock
        # Adwaita dark theme is built INTO libgtk-4-1 (no theme package needed);
        # adwaita-icon-theme supplies the symbolic icons ghb draws in its header
        # bar, without which the toolbar renders as empty boxes.
        libgtk-4-1 \
        adwaita-icon-theme \
        hicolor-icon-theme \
        # Session bus for GTK/GIO (ghb probes the desktop portal over D-Bus).
        dbus-x11 \
        # xsetroot (desktop background) + setxkbmap/xkb-data. The Selkies base
        # starts Xvfb with NO keymap; without a full keymap the web client's
        # keystroke re-type paste path never binds Shift, so pasted UPPERCASE
        # text collapses to lowercase in HandBrake's text fields (the same bug
        # that hit krusader as issue #27).
        x11-xserver-utils \
        x11-xkb-utils \
        xkb-data \
        # Fonts: GTK renders text through fontconfig; without a built cache the
        # UI draws blank strips on the very first start.
        fontconfig \
        fonts-dejavu-core \
        fonts-liberation2 \
        fonts-noto-core \
        fonts-noto-color-emoji \
        # Locale + shell tooling used by the init scripts and the watch daemon.
        # procps supplies pgrep, which svc-handbrake-ready and the CI smoke gate
        # use to prove the ghb process is alive — never drop it.
        locales \
        coreutils \
        findutils \
        procps \
        # openbox-xdg-autostart needs PyXDG
        python3-xdg; \
    fc-cache -f >/dev/null 2>&1 || true; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Generate the default locale so ghb's gettext catalogue resolves.
RUN set -eux; \
    sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen; \
    locale-gen en_US.UTF-8

# ---------------------------------------------------------------------------
# Intel Quick Sync Video (QSV) runtime — amd64 only
# ---------------------------------------------------------------------------
# Ubuntu builds handbrake-cli with --enable-qsv on amd64 only, and the .deb
# already depends on libvpl2 (the oneVPL DISPATCHER) plus libva2/libva-drm2, so
# those arrive with the handbrake-cli install above. What a dispatcher still
# needs at run time is an implementation and a VA-API driver, and neither can be
# a package dependency because both are hardware specific:
#
#   libmfx-gen1.2                   oneVPL GPU runtime (Intel Gen12+ / Xe / Arc)
#   intel-media-va-driver-non-free  iHD VA-API driver. The free variant is
#                                   sufficient for DECODING; ENCODING needs the
#                                   non-free build (Debian wiki,
#                                   HardwareVideoAcceleration). It lives in
#                                   multiverse, which is why the component is
#                                   enabled below. Listed in NOTICE.
#   vainfo, libvpl-tools            diagnostics. handbrake-gpu.sh writes their
#                                   output to /config/handbrake-gpu.log, which is
#                                   the only evidence a user with Intel hardware
#                                   can send us — this path cannot be verified by
#                                   the maintainer.
#
# arm64 has no Quick Sync and none of these packages exist there, so the whole
# layer is a no-op with a log line on that architecture.
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

# ---------------------------------------------------------------------------
# Fail loudly if the HandBrake packaging layout ever moves, and RECORD what this
# build can actually do. The three dumps below are the ground truth used by
# docs/handbrake-capabilities.md and by the GPU plans — never guess an encoder
# identifier, read it from /usr/local/share/handbrake-cli-help.txt.
# ---------------------------------------------------------------------------
RUN set -eux; \
    [ -x /usr/bin/ghb ] || { echo "ERROR: /usr/bin/ghb missing — the 'handbrake' package layout changed"; exit 1; }; \
    [ -x /usr/bin/HandBrakeCLI ] || { echo "ERROR: /usr/bin/HandBrakeCLI missing — the 'handbrake-cli' package layout changed"; exit 1; }; \
    HandBrakeCLI --version > /usr/local/share/handbrake-version.txt 2>&1; \
    HandBrakeCLI --help > /usr/local/share/handbrake-cli-help.txt 2>&1; \
    HandBrakeCLI --preset-list > /usr/local/share/handbrake-preset-list.txt 2>&1; \
    grep -q 'Very Fast 1080p30' /usr/local/share/handbrake-preset-list.txt \
        || { echo "ERROR: preset 'Very Fast 1080p30' not in --preset-list — the default AUTOMATED_CONVERSION_PRESET would fail"; exit 1; }; \
    echo "handbrake: $(head -n 1 /usr/local/share/handbrake-version.txt)"; \
    echo "handbrake: encoders ->"; \
    sed -n '/--encoder/,/^$/p' /usr/local/share/handbrake-cli-help.txt

# ---------------------------------------------------------------------------
# Mount points. Created in the image so a bind mount is optional and so
# docker cp / the CI smoke gate can drop a file into /watch on a bare run.
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p /storage /watch /watch2 /watch3 /watch4 /watch5 /output; \
    chmod 0777 /watch /watch2 /watch3 /watch4 /watch5 /output

# ---------------------------------------------------------------------------
# Skeleton configs + s6-overlay init scripts
# ---------------------------------------------------------------------------
COPY rootfs/ /

# Init-log banner: single source at .github/assets/banner-raw.txt. Strip
# Windows CR (tr is byte-safe) so the block characters render cleanly no matter
# which editor last touched the file.
COPY .github/assets/banner-raw.txt /usr/local/share/banner-raw.txt
RUN tr -d '\r' < /usr/local/share/banner-raw.txt > /usr/local/share/banner.txt

# Suppress the LSIO base-image branding so OUR ASCII banner (print-banner.sh) is
# the only branding in the init log. Two sources: the "linuxserver.io" ASCII logo
# comes from the init-adduser `branding` file (emptied), and the "To support LSIO
# projects visit / donate" solicitation is echoed SEPARATELY inside
# init-adduser/run — strip those two lines from it. The GID/UID block stays
# intact (it confirms the applied PUID/PGID).
RUN set -eux; \
    : > /etc/s6-overlay/s6-rc.d/init-adduser/branding 2>/dev/null || true; \
    run=/etc/s6-overlay/s6-rc.d/init-adduser/run; \
    if [ -f "$run" ]; then \
        sed -i -e '/To support LSIO projects visit:/d' -e '\#linuxserver\.io/donate#d' "$run"; \
    fi

# ---------------------------------------------------------------------------
# Browser-tab favicon / branding
# ---------------------------------------------------------------------------
# On the Selkies base the branding is a single file: init-nginx copies
# /usr/share/selkies/www/icon.png to favicon.ico + icon.png in the served web
# root on every start and writes the PWA manifest around ${TITLE}. Replacing
# that one PNG brands the whole web UI. Fail loudly if the path moves (base
# layout change) so CI / the weekly rebuild surfaces the regression.
COPY .github/assets/icon.png /usr/local/share/handbrake-icon.png
RUN set -eux; \
    dst=/usr/share/selkies/www/icon.png; \
    [ -f "$dst" ] || { echo "ERROR: $dst missing — selkies base layout changed, update the branding override"; exit 1; }; \
    cp /usr/local/share/handbrake-icon.png "$dst"; \
    echo "handbrake: branded selkies icon at $dst"

# Executable bits for everything we ship (a Windows checkout carries no mode).
RUN chmod +x \
    /usr/local/bin/print-banner.sh \
    /usr/local/bin/handbrake-theme.sh \
    /usr/local/bin/handbrake-gpu.sh \
    /usr/local/bin/handbrake-watch.sh \
    /etc/s6-overlay/s6-rc.d/init-nologin/run \
    /etc/s6-overlay/s6-rc.d/init-handbrake/run \
    /etc/s6-overlay/s6-rc.d/svc-handbrake-watch/run \
    /etc/s6-overlay/s6-rc.d/svc-handbrake-ready/run \
    /defaults/autostart \
    /defaults/startwm.sh

# ---------------------------------------------------------------------------
# Shutdown grace: a running transcode must get a chance to be cancelled and its
# partial output removed (the watch daemon traps SIGTERM). s6's default 3 s
# would SIGKILL through that cleanup and leave a stray .partial file behind.
# ---------------------------------------------------------------------------
ENV S6_KILL_GRACETIME=15000 \
    S6_SERVICES_GRACETIME=15000

# ---------------------------------------------------------------------------
# Default ENV (all overridable from the Unraid template)
# ---------------------------------------------------------------------------
# HANDBRAKE_THEME  – dark (default) | light. Drives GTK_THEME; see
#                    handbrake-theme.sh. Dark is HandBrake's own native GTK dark
#                    mode (stock Adwaita dark), not a custom restyle.
# GPU_VENDOR       – none (default) | nvidia | intel | amd. The seam is
#                    /usr/local/bin/handbrake-gpu.sh -> /run/handbrake/gpu-args.
#                    "nvidia" needs the NVIDIA container runtime (--runtime=nvidia)
#                    plus NVIDIA_DRIVER_CAPABILITIES=compute,video,utility.
#                    "intel" needs /dev/dri passed through (amd64 only; the QSV
#                    runtime is installed above). "amd" needs a HandBrakeCLI
#                    built with --enable-vce plus AMD's proprietary AMF runtime,
#                    neither of which this image can ship — see Dockerfile.gpu.
#                    Any vendor that cannot be honoured logs the reason and
#                    falls back to software encoding.
# APP_NICENESS     – nice level applied to ghb and to every HandBrakeCLI run
#                    (0..19; negative values need extra privileges and are
#                    clamped to 0).
# KEYBOARD_LAYOUT  – X keyboard layout loaded at session start.
ENV HANDBRAKE_THEME=dark \
    GPU_VENDOR=none \
    APP_NICENESS=0 \
    KEYBOARD_LAYOUT=us

# Automated watch-folder conversion. Variable names deliberately match
# jlesage/docker-handbrake so migrating users keep their template values.
# AUTOMATED_CONVERSION_WATCH_DIR=AUTO scans /watch plus /watch2../watchN up to
# AUTOMATED_CONVERSION_MAX_WATCH_FOLDERS; any other value is used verbatim as
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

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# ---------------------------------------------------------------------------
# Healthcheck: the Selkies WebUI (nginx) answers on the HTTPS port. Any HTTP
# status counts as up; only "000" (no answer) marks the container unhealthy.
# ---------------------------------------------------------------------------
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD ["/bin/sh", "-c", "c=$(curl -ks -o /dev/null -w '%{http_code}' --max-time 5 https://127.0.0.1:${CUSTOM_HTTPS_PORT:-3001}/); [ \"$c\" != \"000\" ] || exit 1"]

# ---------------------------------------------------------------------------
# Build provenance — passed from CI, written into the image so users can verify
# which commit their running image was built from:
#   docker exec handbrake cat /etc/handbrake-build
# Deliberately the LAST layer: BUILD_SHA changes on every commit, so an earlier
# placement would bust the cache for every layer after it.
# ---------------------------------------------------------------------------
ARG BUILD_SHA=dev
ARG BUILD_DATE=unknown
RUN echo "sha=${BUILD_SHA}"   >  /etc/handbrake-build && \
    echo "date=${BUILD_DATE}" >> /etc/handbrake-build

# Ports are exposed by the base image (3000/HTTP, 3001/HTTPS).
