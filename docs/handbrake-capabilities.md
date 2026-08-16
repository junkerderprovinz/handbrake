# HandBrake capabilities in this image

Recorded from the image built at commit `9adae33` on
`2026-08-16`. Regenerate with the commands below after every base-image or
HandBrake version bump — never edit this file by hand.

The same three dumps ship inside the image:

```sh
docker exec handbrake cat /usr/local/share/handbrake-version.txt
docker exec handbrake cat /usr/local/share/handbrake-cli-help.txt
docker exec handbrake cat /usr/local/share/handbrake-preset-list.txt
```

## Version

```text
[04:09:18] Compile-time hardening features are enabled
Cannot load libnvidia-encode.so.1
[04:09:18] qsv: not available on this system
[04:09:18] hb_init: starting libhb thread
[04:09:18] thread 1501d2b1c6c0 started ("libhb")
HandBrake has exited.
HandBrake 1.11.0
```

The "Cannot load libnvidia-encode.so.1" / "qsv: not available on this system"
lines are HandBrakeCLI's own runtime hardware probes, printed on every
invocation regardless of `--version`; they are expected on a build host with
no GPU passed through and are not evidence either way about what the binary
was compiled with (see the encoder list below for that).

## Video encoders (`HandBrakeCLI --help`, `-e/--encoder`)

```text
   -e, --encoder <string>  Select video encoder:
                               svt_av1
                               svt_av1_10bit
                               ffv1
                               x264
                               x264_10bit
                               x265
                               x265_10bit
                               x265_12bit
                               mpeg4
                               mpeg2
                               VP8
                               VP9
                               VP9_10bit
                               dnxhr
                               dnxhr_10bit
                               ff_prores
                               theora
```

**Hardware encoders present in this build:** none

**Hardware encoders absent:** `nvenc_h264`, `nvenc_h265`, `nvenc_h265_10bit`,
`nvenc_av1`, `qsv_h264`, `qsv_h265`, `qsv_av1`, `vce_h264`, `vce_h265`

**This contradicts the spec's stated expectation.** The design spec assumed
Ubuntu's `handbrake-cli` package is built with `--enable-nvenc` and
`--enable-qsv` (based on Ubuntu's documented default configure flags for the
HandBrake source package). The actual `--encoder` list from Ubuntu 26.04's
`universe` build of `handbrake-cli` 1.11.0 shows **no hardware encoder ids at
all** — this is a statically compiled-in list (HandBrakeCLI prints every
encoder the binary was linked against, independent of what hardware is
present at runtime), so their absence here means the Ubuntu package itself was
not built with NVENC/QSV/VCE support, not merely that this build host lacks a
GPU.

**Impact on Plans 2 and 3 (NVIDIA NVENC / Intel QSV + AMD VCN):** both plans
were written assuming only runtime libraries and `handbrake-gpu.sh` argument
selection were needed on top of the distro package. That assumption does not
hold. Delivering real hardware encoding will require either (a) compiling
HandBrake from source with `--enable-nvenc --enable-qsv` in this Dockerfile
instead of installing the distro package, or (b) sourcing a differently built
package/PPA that includes them, and re-verifying against a host with the
relevant GPU actually attached to confirm the encoder appears **and** that a
real hardware-accelerated conversion succeeds. Flagged here rather than
silently adjusted in either GPU plan — those plans need a joint re-scope
before implementation starts.

## Container formats (`-f/--format`)

```text
   -f, --format <string>   Select container format:
                               av_mp4
                               av_mov
                               av_mkv
                               av_webm
```

All three spellings used in `handbrake-watch.sh`'s `case "${FORMAT}"` block
(`av_mp4`, `av_mkv`, `av_webm`) match exactly; no change needed.

## Preset catalogue (first 60 lines)

```text
General/
    Very Fast 2160p60 4K AV1
        AV1 video (up to 2160p60) and AAC stereo audio, in an MP4
        container.
    Very Fast 2160p60 4K HEVC
        H.265 video (up to 2160p60) and AAC stereo audio, in an MP4
        container.
    Very Fast 1080p30
        Small H.264 video (up to 1080p30) and AAC stereo audio, in
        an MP4 container.
    Very Fast 720p30
        Small H.264 video (up to 720p30) and AAC stereo audio, in an
        MP4 container.
    Very Fast 576p25
        Small H.264 video (up to 576p25) and AAC stereo audio, in an
        MP4 container.
    Very Fast 480p30
        Small H.264 video (up to 480p30) and AAC stereo audio, in an
        MP4 container.
    Fast 2160p60 4K AV1
        AV1 video (up to 2160p60) and AAC stereo audio, in an MP4
        container.
    Fast 2160p60 4K HEVC
        H.265 video (up to 2160p60) and AAC stereo audio, in an MP4
        container.
    Fast 1080p30
        H.264 video (up to 1080p30) and AAC stereo audio, in an MP4
        container.
    Fast 720p30
        H.264 video (up to 720p30) and AAC stereo audio, in an MP4
        container.
    Fast 576p25
        H.264 video (up to 576p25) and AAC stereo audio, in an MP4
        container.
    Fast 480p30
        H.264 video (up to 480p30) and AAC stereo audio, in an MP4
        container.
    HQ 2160p60 4K AV1 Surround
        High quality AV1 video (up to 2160p60), AAC stereo audio,
        and Dolby Digital (AC-3) surround audio, in an MP4
        container.
    HQ 2160p60 4K HEVC Surround
        High quality H.265 video (up to 2160p60), AAC stereo audio,
        and Dolby Digital (AC-3) surround audio, in an MP4
        container.
    HQ 1080p30 Surround
        High quality H.264 video (up to 1080p30), AAC stereo audio,
        and Dolby Digital (AC-3) surround audio, in an MP4
        container.
    HQ 720p30 Surround
        High quality H.264 video (up to 720p30), AAC stereo audio,
        and Dolby Digital (AC-3) surround audio, in an MP4
        container.
    HQ 576p25 Surround
        High quality H.264 video (up to 576p25), AAC stereo audio,
        and Dolby Digital (AC-3) surround audio, in an MP4
        container.
    HQ 480p30 Surround
        High quality H.264 video (up to 480p30), AAC stereo audio,
        and Dolby Digital (AC-3) surround audio, in an MP4
        container.
```

The default `AUTOMATED_CONVERSION_PRESET` is `General/Very Fast 1080p30`; the
Dockerfile fails the build if that preset disappears from the catalogue.
`grep -c 'Very Fast 1080p30' handbrake-preset-list.txt` returned `1`.

## GUI toolkit

```text
	libgtk-4.so.1 => /usr/lib/x86_64-linux-gnu/libgtk-4.so.1 (0x00001523a8ff6000)
```

`libadwaita` does not appear in `ldd /usr/bin/ghb` output. HandBrake's GUI is
GTK4 without libadwaita, so the dark theme is applied through
`GTK_THEME=Adwaita:dark` (see `rootfs/usr/local/bin/handbrake-theme.sh`).
