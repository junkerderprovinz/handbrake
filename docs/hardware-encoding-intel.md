# Intel Quick Sync Video (QSV) hardware encoding in this image

Everything below was **measured**, not assumed, on a real Intel iGPU (UHD
Graphics 770, Raptor Lake). Regenerate the recorded sections with the commands
shown after every base-image or HandBrake version bump.

Image built from commit `7c3b030` on `2026-08-16`.

## 1. QSV is compiled in on amd64, and detection works correctly

Ubuntu builds `handbrake-cli` with `--enable-qsv` on amd64 and links it
against the system oneVPL dispatcher (`libvpl2`), so the package already
depends on it:

```sh
docker run --rm --entrypoint sh handbrake:pre-gpu -c \
  'dpkg -s handbrake-cli | grep -i "^Depends" | tr "," "\n" | grep -iE "vpl|va-?drm|libva"'
```

```text
libva-drm2 (>= 1.1.0)
libva2 (>= 1.6.0~pre1)
libvpl2 (>= 1:2.16.0)
```

Confirmed in the binary itself, with no Intel hardware required (the encoder
identifiers are string literals compiled in regardless of the hardware probe):

```sh
docker run --rm --entrypoint sh handbrake:pre-gpu -c \
  'objdump -p /usr/bin/HandBrakeCLI 2>/dev/null | grep NEEDED | grep -i vpl'
```

```text
NEEDED               libvpl.so.2
```

With a real Intel GPU passed through (`--device /dev/dri`), `handbrake-gpu.sh`
detects it correctly and picks `qsv_h264`:

```text
[handbrake-gpu] Intel QSV enabled: --encoder qsv_h264 (render node /dev/dri/renderD128)
[handbrake-gpu] diagnostics: /config/handbrake-gpu.log
[init-handbrake] gpu-args: '--encoder qsv_h264' (vendor intel)
```

The live encoder list on that hardware includes the full QSV set (this build's
GPU generation supports H.264/H.265 but not AV1 — see section 2):

```text
qsv_av1
qsv_av1_10bit
qsv_h264
qsv_h265
qsv_h265_10bit
```

`vainfo` confirms the iHD VA-API driver loads and lists `VAEntrypointEncSlice`
for H.264, and `vpl-inspect` confirms the oneVPL GPU runtime finds an
implementation. Both are captured automatically in `/config/handbrake-gpu.log`.

## 2. This machine's real encoder support

```sh
docker exec handbrake grep -A2 -- '- H.264 encoder:' /config/handbrake-watch.log
```

```text
[06:30:12]  - H.264 encoder: yes
[06:30:12]  - H.265 encoder: yes (8bit: yes, 10bit: yes)
[06:30:12]  - AV1 encoder: no
```

HandBrake logs this per-machine capability summary at the start of every job.
Which of these are `yes` depends on the specific Intel GPU generation; a
Gen12/Xe iGPU like this one has no AV1 hardware encoder block, so `qsv_av1`
is *listed* (compiled in) but will not actually encode on this machine — the
same "compiled in but not usable here" distinction the whole live-probe
architecture exists to catch for the id HandBrake picks (`qsv_h264`).

## 3. A real, confirmed bug in Ubuntu's packaged build (fixed by this image)

**The stock apt-installed `HandBrakeCLI` detects QSV correctly, but every real
conversion with it fails.** Measured directly, on this exact hardware:

```text
[mp4 @ 0x14afdc0c8f00] Application provided invalid, non monotonically increasing dts to muxer in stream 0: 15945000 >= 15942000
...(repeats)...
ERROR: avformatMux: track 0, av_interleaved_write_frame failed with error 'Invalid argument'
[...] libhb: work result = 4
Encode failed (error 4).
```

The encode itself completes at full speed (452 fps average on a 1080p30
clip in one run) — the failure is entirely in the muxing step, and reproduces
identically for both `av_mp4` and `av_mkv` output, with the stock
`General/Very Fast 1080p30` preset, with HandBrake's own `H.265 QSV 1080p`
hardware preset, and with `bframes=0` forced via `--encopts`. It is not a
container-format issue, a preset issue, or a B-frame issue in this container's
configuration — it reproduces with a bare `HandBrakeCLI` invocation.

**This is a known, independently confirmed bug in Ubuntu's specific packaged
build, not in HandBrake itself.**
[HandBrake/HandBrake#7962](https://github.com/HandBrake/HandBrake/issues/7962)
documents another user hitting the **identical** failure on the **identical**
environment — Ubuntu 26.04 "resolute", `handbrake-cli` 1.11.0 from the Ubuntu
universe package — and confirms the fix:

> Can confirm this reproduces on my system with the distro-packaged build, but
> building from source fixed it.
>
> Packaged build - fails: handbrake-cli 1.11.0 (Ubuntu universe/PPA package).
> QSV encoders detected fine, but every encode fails.
>
> Self-built - works: Compiled the same 1.11.2 source tag with
> `./configure --launch --disable-gtk --enable-qsv`. Same files, same
> settings - encodes complete cleanly with no DTS errors, and QSV is
> confirmed active (CPU usage drops from ~100% to ~30%, ~3x faster than CPU
> x265).

The maintainer's response to the issue: users are running "an unsupported
third party version of HandBrake" and should "compile from source to rule
out any issues caused by bad packaging" — i.e. this is Ubuntu's packaging
defect, not something HandBrake's own team is going to chase down.

## 4. The fix: `handbrake:gpu-full` (optional variant, `Dockerfile.gpu`)

Building `HandBrakeCLI` from source with `--enable-qsv` (same mechanism as
the reporter above used) fixes it completely. Measured on this image, same
hardware, same 180 s / 1920x1080 / 30 fps clip used for the NVENC comparison
(see `docs/hardware-encoding-nvidia.md`):

```text
=== 2026-08-16T06:30:12+00:00 HandBrakeCLI --preset General/Very Fast 1080p30 --input /watch/qsv-fixed-run.mkv --output /output/.qsv-fixed-run.mp4.partial --format av_mp4 --encoder qsv_h264
[06:30:12] qsv: is available on this system
[06:30:12]    + encoder: H.264 (Intel QSV)
[handbrake-watch] done 'qsv-fixed-run.mkv' in 12s -> /output/qsv-fixed-run.mp4
```

No DTS errors, no mux failure. The output decodes cleanly (`ffmpeg -i ... -f
null -`) and reports `codec_name=h264, width=1920, height=1080,
nb_frames=5400` — exactly 180 s × 30 fps.

| Build | Encoder | Wall clock | Output size |
|---|---|---|---|
| Ubuntu package (`handbrake:gpu`) | `qsv_h264` | fails at mux | — |
| Source build (`handbrake:gpu-full`) | `qsv_h264` | `12` s | `3.6 MB` |
| Software (`handbrake:gpu`, `GPU_VENDOR=none`) | x264 | `27` s | `3.2 MB` |

QSV via the source-built binary is comparable in speed to NVENC (`11` s on
the same clip on this machine's RTX 4070 Ti SUPER — see
`docs/hardware-encoding-nvidia.md`) and roughly 2.25x faster than software on
this CPU.

**This is why `Dockerfile.gpu` exists and enables `--enable-qsv` even though
Ubuntu's own package already claims to build it.** Ubuntu's flag is honest
about what got compiled in; it says nothing about whether the resulting
binary actually works. See `Dockerfile.gpu` for the build (30-60 minutes on
8 cores; measured `2m51s` on this 32-core machine, `docker build --no-cache`;
not published, not CI-gated, `just build-gpu-full`).

## 5. What still cannot be verified here

AMD VCE (the other reason `Dockerfile.gpu` exists) has no hardware to test on
in this environment — see `docs/handbrake-capabilities.md`'s "Optional
full-GPU build variant" section for what was verified without AMD hardware
(the AMF code path is compiled in) and what was not (whether it actually
encodes). Other Intel GPU generations (older Gen9-11, or newer Arc
discrete cards) may behave differently than the Gen12/Xe iGPU measured here;
community reports close that loop (see the README's Hardware Encoding
section).
