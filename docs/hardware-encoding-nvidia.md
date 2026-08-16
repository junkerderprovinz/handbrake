# NVIDIA NVENC hardware encoding in this image

Everything below was **measured**, not assumed. Regenerate the recorded sections
with the commands shown after every base-image or HandBrake version bump.

Image built from commit `185534d` on `2026-08-16`,
HandBrake version:

```text
[04:09:18] Compile-time hardening features are enabled
Cannot load libnvidia-encode.so.1
[04:09:18] qsv: not available on this system
[04:09:18] hb_init: starting libhb thread
[04:09:18] thread 1501d2b1c6c0 started ("libhb")
HandBrake has exited.
HandBrake 1.11.0
```

## 1. NVENC encoders in this build

`libhb` lists a hardware encoder in `--help` only when it is **compiled in AND
usable on the hardware present right now**: `hb_video_encoder_is_enabled()` calls
`hb_nvenc_h264_available()` before the encoder ever reaches the list that
`--help` prints (`libhb/common.c`). Two things follow, and both were measured.

**The build-time dump can never list one.** It is written during `docker build`,
on a machine with no NVIDIA runtime:

```sh
docker run --rm --entrypoint sh handbrake:dev -c \
  'sed -n "/-e, --encoder/,/^[[:space:]]*-[a-zA-Z-]/p" /usr/local/share/handbrake-cli-help.txt \
     | tr " ,\t" "\n\n\n" | grep -E "^nvenc" | sort -u'
```

```text
(empty)
```

**A live `--help` on a GPU-less machine says the same thing**, which is why the
absence above is a property of the hardware, not of the build:

```sh
docker run --rm --entrypoint sh handbrake:dev -c \
  "HandBrakeCLI --help 2>/dev/null | awk '/^[[:space:]]*-e, --encoder[[:space:]]/{f=1;next} f&&/^[[:space:]]*-/{f=0} f' \
     | sed 's/^[[:space:]]*//;s/[[:space:]]*\$//' | grep -v '^\$'"
```

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

**The binary was nevertheless built with NVENC** — the identifiers are string
literals inside it regardless of the hardware probe:

```sh
docker run --rm --entrypoint sh handbrake:dev -c \
  'grep -a -o -E "nvenc_(h264|h265|av1)" "$(command -v HandBrakeCLI)" | sort -u'
```

```text
nvenc_av1
nvenc_h264
nvenc_h265
```

So `handbrake-gpu.sh` asks the **running** `HandBrakeCLI` at container start and
picks the first identifier from its preference list that the binary offers *on
that machine*. It never hardcodes an identifier and never reads the dump for
this. One `--help` call is the identifier lookup and the hardware probe at the
same time. The list as it appears on real NVIDIA hardware is in section 7.

## 2. Valid `--encoder-preset` values for NVENC

```sh
docker run --rm --entrypoint sh handbrake:dev -c 'HandBrakeCLI --encoder-preset-list nvenc_h264'
```

```text
Available --encoder-preset values for 'nvenc_h264' encoder:
    fastest
    faster
    fast
    medium
    slow
    slower
    slowest
```

Unlike the `--encoder` list itself, `--encoder-preset-list` resolves its
argument by name against the static encoder table and does not require a
working GPU to answer — it printed correctly even on this GPU-less build
machine.

The x264/x265 speed names (`veryfast`, `medium`, …) that HandBrake's software
presets carry are **not** in this list (`veryfast` in particular has no NVENC
equivalent). HandBrake maps an unknown name onto its own default rather than
failing the job, so a software preset plus `--encoder nvenc_*` still runs; a
user who wants explicit control appends `--encoder-preset <name from this
list>` through `AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS`.

## 3. Hardware decoding (NVDEC)

```sh
docker run --rm --entrypoint sh handbrake:dev -c \
  'grep -A3 -- "--enable-hw-decoding" /usr/local/share/handbrake-cli-help.txt'
```

```text
   --enable-hw-decoding <string>
                           Use 'nvdec' to enable NVDec
                           Use 'qsv' to enable QSV decoding
   --disable-hw-decoding   Disable hardware decoding of the video track,
```

NVDEC is **not** enabled by default by `handbrake-gpu.sh`, on purpose. HandBrake's
own documentation states that hardware decoding "is usually only beneficial for
directly feeding an adjacent hardware encoder" and that HandBrake "will
automatically disable hardware decoding [and] fall back to software decoding
whenever it [is] necessary for the decoded video to make a roundtrip to the CPU
and back; essentially, whenever a video filter is enabled, including the
crop/scale filter"
(<https://handbrake.fr/docs/en/latest/technical/video-nvenc.html>). Every stock
preset enables crop/scale, so switching it on by default would buy nothing while
adding a decode path to the blast radius. It stays a one-line opt-in.

## 4. HandBrake's own NVENC presets in this build

```sh
docker run --rm --entrypoint sh handbrake:dev -c \
  'grep -i -B2 "nvenc" /usr/local/share/handbrake-preset-list.txt | head -n 40'
```

```text
H.265 NVENC 2160p 4K
        Nvidia NVENC hardware accelerated H.265 video (up to 2160p)
        and AAC stereo audio, in an MP4 container.
    H.265 NVENC 1080p
        Nvidia NVENC hardware accelerated H.265 video (up to 1080p)
```

HandBrake ships its own NVENC-named presets out of the box (alongside AMD
VCN-named ones, e.g. "AMD VCN hardware accelerated AV1"). `handbrake-gpu.sh`
never overrides a preset that already names an encoder — see Task 4.

## 5. What the host has to provide

| Requirement | Value | Why |
|---|---|---|
| Unraid plugin | Nvidia-Driver (ich777) | installs the NVIDIA kernel driver and the NVIDIA container runtime |
| Container runtime | `--runtime=nvidia` in Extra Parameters | without it the container gets no `/dev/nvidia*` node and no driver libraries |
| `NVIDIA_VISIBLE_DEVICES` | a GPU UUID from `nvidia-smi -L`, or `all` | selects which GPU is passed in |
| `NVIDIA_DRIVER_CAPABILITIES` | `compute,video,utility` | `video` injects `libnvidia-encode.so.1` (NVENC/NVDEC), `compute` the CUDA runtime, `utility` `nvidia-smi`. `all` also works |
| NVIDIA driver | `570.0` or newer | HandBrake's documented NVENC requirement |

Source for the capability meanings:
<https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/docker-specialized.html>
— `compute` "required for CUDA and OpenCL applications", `utility` "required for
using nvidia-smi and NVML", `video` "required for using the Video Codec SDK".
With the variable unset the runtime defaults to `utility,compute`, i.e. **no
`video`**, which is why NVENC needs it set explicitly.

Source for the driver requirement:
<https://handbrake.fr/docs/en/latest/technical/video-nvenc.html> — "NVIDIA
Graphics Driver 570.0 or later".

## 6. What the container checks at start

`handbrake-gpu.sh` refuses to claim hardware encoding it cannot deliver. With
`GPU_VENDOR=nvidia` it checks, in this order:

1. an NVIDIA device node exists (`/dev/nvidiactl`, `/dev/nvidia0`, …) — proves the
   container was started through the NVIDIA container runtime;
2. `libnvidia-encode.so.1` is present — proves `NVIDIA_DRIVER_CAPABILITIES`
   includes `video`;
3. the **running** `HandBrakeCLI` lists an NVENC encoder in a live `--help` call
   — HandBrake only lists a hardware encoder it can actually use right now, so
   this single check covers "the build has NVENC" and "the driver/GPU can serve
   it" at once. The build-time help dump is deliberately not used here: it is
   recorded without a GPU and never lists a hardware encoder.

Each failing check logs its own error block naming the exact fix, then falls back
to software encoding for that container start. The effective state is visible at
any time:

```sh
docker exec handbrake cat /run/handbrake/gpu-args   # empty means software encoding
docker logs handbrake 2>&1 | grep '\[handbrake-gpu\]'
```
