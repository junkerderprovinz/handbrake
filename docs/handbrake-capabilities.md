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

**Hardware encoders listed in this dump:** none — **and that is expected, not
a defect.** See below.

**Corrected finding (superseding an earlier, wrong note in this file):** an
initial reading of this dump concluded the Ubuntu package was compiled
without NVENC/QSV/VCE support at all, and that Plans 2 and 3 would need a
source-build re-scope. That conclusion was wrong. Verified against the real
Ubuntu build:

- The actual Launchpad build log for `handbrake 1.11.0~us1-0ubuntu1`
  (`resolute`, amd64) prints `Enable NVENC: True` and `Enable QSV: True`
  (`Enable VCE: False`) — both NVENC and QSV genuinely ARE compiled in.
  `libffmpeg-nvenc-dev` and `libvpl-dev` are real build-dependencies in
  `debian/control`; only `libamfrt64` (AMD's proprietary AMF runtime) is
  absent, which is why VCE alone is truly not compiled in.
- `libhb/common.c`'s `hb_video_encoder_is_enabled()` gates every hardware
  encoder behind a **live availability probe**
  (`hb_nvenc_h264_available()`, `hb_qsv_video_encoder_is_available()`, …),
  not just a compile-time flag. This dump was captured during `docker build`
  on a builder with no GPU attached, so the probe correctly returns
  unavailable and `libhb` filters every `nvenc_*`/`qsv_*` id out of the
  `--encoder` list before it is ever printed — **even though the binary has
  them compiled in.** A build-time capture can never show a hardware
  encoder, on any machine, regardless of what that machine's real hardware
  will be at runtime.

**Impact on Plans 2 and 3 (NVIDIA NVENC / Intel QSV + AMD VCN): none — no
re-scope needed.** Both plans already designed around exactly this behavior
before this dump was even recorded: `handbrake-gpu.sh` asks a **live**
`HandBrakeCLI --help` call inside the running container (as the runtime user,
with the real GPU attached) for the encoder id, and explicitly documents that
this build-time dump is expected to list nothing. Plan 3 additionally
confirms QSV needs only two runtime packages (`libmfx-gen1.2`,
`intel-media-va-driver-non-free`) since the oneVPL dispatcher (`libvpl2`) is
already a dependency of the apt-installed package — no rebuild. AMD VCE is
the one real exception: the shipped binary has no VCE code path at all, and
Plan 3's separate `Dockerfile.vce` (source build with `--enable-vce` plus
AMD's proprietary AMF runtime) is the already-designed, correct answer for
that case.

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

## Hardware encoder support in this packaging

Recorded on `2026-08-16` from `handbrake:pre-gpu`, built at commit
`b8f9ea4`. Regenerate after every base-image or HandBrake version bump.

### Why the encoder list above contains no hardware encoders

`libhb` only lists a hardware encoder when it is **compiled in AND usable on the
machine right now** (`libhb/common.c`, `hb_video_encoder_is_enabled()` calls
`hb_qsv_video_encoder_is_available()` / `hb_vce_h264_available()` /
`hb_nvenc_h264_available()`). The dump in
`/usr/local/share/handbrake-cli-help.txt` is recorded during `docker build` on a
machine with no GPU, so it can never contain one.

**Do not use that dump to decide whether a hardware encoder exists.** Ask the
live binary inside a running container instead — which is exactly what
`rootfs/usr/local/bin/handbrake-gpu.sh` does.

Live encoder list on a GPU-less machine:

```text
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

### Intel QSV: compiled in on amd64

Ubuntu builds `handbrake-cli` with `--enable-qsv` on amd64 and links it against
the system oneVPL dispatcher, so the package already depends on it:

```text
libva-drm2 (>= 1.1.0)
libva2 (>= 1.6.0~pre1)
libvpl2 (>= 1:2.16.0)
```

Proof in the binary itself (needs no Intel hardware):

```text
NEEDED               libvpl.so.2
```

(`grep -c -a -F "libvpl.so.2" /usr/bin/HandBrakeCLI` also returns `1`, the
fallback used when `objdump` is unavailable.)

Missing from a stock image, and added by this repo's Dockerfile on amd64:
`libmfx-gen1.2` (oneVPL GPU runtime) and `intel-media-va-driver-non-free` (iHD
VA-API driver). Neither is a package dependency because both are hardware
specific.

### AMD VCE: not compiled in

```text
0
```

`0` occurrences of the AMF runtime name means the binary contains no AMD VCE
code path at all. Debian/Ubuntu do not pass `--enable-vce` (confirmed against
the real `debian/rules`: it passes `enable-nvenc`, `enable-qsv` and
`enable-x265`, never `enable-vce`); upstream's own default enables it only for
Windows hosts. HandBrake 1.11 also has no VA-API encoder fallback (the 1.11.x
encoder table has `qsv_*`, `vce_*` and `nvenc_*` and no `vaapi_*`; VA-API
exists only on `master` so far).

Getting AMD hardware encoding therefore needs **both** a source rebuild with
`--enable-vce` **and** AMD's proprietary `libamfrt64.so.1` runtime at run time.
See `Dockerfile.vce` and the README's Hardware Encoding section.
