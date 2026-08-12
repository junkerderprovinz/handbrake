# HandBrake — NVIDIA NVENC GPU Support Implementation Plan (Plan 2 of 4)

> **For agentic workers:** Requires Plan 1 (core port) already implemented and merged. Steps use checkbox (`- [ ]`) syntax for tracking. Execute task-by-task, committing after each passing task.

**Goal:** Ship `junkerderprovinz/handbrake` v1.1.0 — `GPU_VENDOR=nvidia` makes every watch-folder job encode on the GPU with HandBrake's NVENC encoder, verified end-to-end on real NVIDIA hardware, and says so loudly instead of silently degrading when the GPU is not actually reachable.

**Architecture:** Plan 1 left exactly one seam for this: `rootfs/usr/local/bin/handbrake-gpu.sh` turns `GPU_VENDOR` into extra `HandBrakeCLI` arguments, `init-handbrake` captures them into `/run/handbrake/gpu-args`, and `handbrake-watch.sh` splices that file into every `HandBrakeCLI` invocation. This plan adds the `nvidia` branch to `gpu_args_for_vendor()` in that one script: it probes for a real, usable GPU (NVIDIA device node plus the `libnvidia-encode.so.1` the container runtime injects), picks an NVENC encoder identifier that the running `HandBrakeCLI` actually offers on this machine (read from a **live** `HandBrakeCLI --help` call at container start — never from the build-time dump, and never guessed), and emits `--encoder <id>`. No Dockerfile change is needed: the NVIDIA userspace libraries are injected at run time by the NVIDIA container runtime, which is precisely why an Ubuntu/glibc base works here where jlesage's Alpine image cannot.

**Tech Stack:** POSIX-ish bash (shellcheck `-S warning`), HandBrake 1.11 `HandBrakeCLI` (Ubuntu `handbrake-cli`, built with `--enable-nvenc`), NVIDIA container toolkit (`--runtime=nvidia`), Unraid Nvidia-Driver plugin, Docker, GitHub Actions (unchanged by this plan).

## Global Constraints

- Repo: `d:\nextcloud\it\github\handbrake`, remote `https://github.com/junkerderprovinz/handbrake`, branch `main`.
- **This plan touches exactly four files.** `rootfs/usr/local/bin/handbrake-gpu.sh`, `README.md`, `docs/hardware-encoding-nvidia.md` (new) and `.github/release-notes/v1.1.0.md` (new). Nothing else — not the Dockerfile, not the s6 services, not `handbrake-watch.sh`, not the workflows. If a task appears to need another file, stop and report instead of widening the scope.
- Versioning: 3-digit SemVer, tags `vX.Y.Z`. Plan 1 shipped `v1.0.0`; a new user-facing feature makes this **`v1.1.0`** (minor bump, no breaking change: `GPU_VENDOR` still defaults to `none`).
- **Everything inside the repo is English** — code, comments, commit messages, README, release notes, log strings.
- **No AI attribution anywhere.** No `Co-Authored-By`, no "Generated with", no assistant references in commits, code or docs.
- **No real IPs, hostnames or user data in any repo file.** The real-hardware verification runs against jdp's Unraid box; write `<unraid-host>` in every committed file and keep the real address out of the repo.
- LF line endings for everything under `rootfs/` — enforced by `.gitattributes`. CRLF breaks the shebang inside the image.
- **Fail loudly on misconfiguration.** `GPU_VENDOR=nvidia` without a usable GPU must print a clear, actionable error block and fall back to software encoding. It must never produce a job that dies on every file, and never silently pretend the GPU is in use.
- **Never guess an encoder identifier — and never read a hardware encoder id from the build-time dump.** Every *hardware* encoder id is looked up in a live `HandBrakeCLI --help` call made inside the running container. `libhb` filters the encoder list by a live availability probe, so `/usr/local/share/handbrake-cli-help.txt` (recorded during `docker build`, on a GPU-less builder) never lists one. That dump stays the source of truth only for **statically printed** help text such as the `--enable-hw-decoding` entry. See "Why the encoder check asks the live binary" below.
- CI has no GPU. The workflows stay untouched: the smoke gate keeps proving the `GPU_VENDOR=none` default, the GPU path is proven by Tasks 5, 6 and 9.
- **Never tag or publish a release without explicit approval from jdp.** Pushing to `main` and letting `:latest` rebuild is fine; cutting `v1.1.0` is gated (Task 12, Step 4).
- Never `git add -A`. Always stage explicit paths.

---

## Task Overview

| # | Task | Ships |
|---|---|---|
| 1 | Preflight: the Plan 1 seam is present and intact | (no files) |
| 2 | Record the bundled build's real NVENC capabilities | `docs/hardware-encoding-nvidia.md` |
| 3 | Confirm and record the host-side NVIDIA requirements | `docs/hardware-encoding-nvidia.md` |
| 4 | Implement the `nvidia` branch of `gpu_args_for_vendor()` | `rootfs/usr/local/bin/handbrake-gpu.sh` |
| 5 | Prove the fail-loud path (no GPU present) | (no files) |
| 6 | Prove the selection logic with a faked NVIDIA environment | (no files) |
| 7 | README: hardware-encoding documentation | `README.md` |
| 8 | Push to `main`, publish `:latest` through CI | (no files) |
| 9 | Real-hardware verification on the NVIDIA box | (no files) |
| 10 | Record the hardware evidence | `docs/hardware-encoding-nvidia.md` |
| 11 | Unraid CA template handoff | `docs/hardware-encoding-nvidia.md` |
| 12 | Release notes v1.1.0 and the gated tag | `.github/release-notes/v1.1.0.md` |
| 13 | Follow-ups outside this repo | (no files) |

---

## What Plan 1 already built (read before Task 1)

Do not redefine any of this. Names are exact.

- `rootfs/usr/local/bin/handbrake-gpu.sh <vendor>` — prints extra `HandBrakeCLI` arguments on **stdout**, a decision line on **stderr**, writes `/run/handbrake/gpu-vendor`. Contains `gpu_args_for_vendor()` with a `none` branch and a catch-all branch. **The only file this plan changes inside the image.**
- `rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/run` — calls `/usr/local/bin/handbrake-gpu.sh "${GPU_VENDOR:-none}" > /run/handbrake/gpu-args`, then logs `gpu-args: '<content>' (vendor <vendor>)`.
- `rootfs/usr/local/bin/handbrake-watch.sh` — `read -r -a HB_GPU_ARGS <<< "$(cat /run/handbrake/gpu-args …)"` and, in `hb_run()`, appends `HB_GPU_ARGS` **before** `HB_EXTRA_ARGS` (`AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS`). Later occurrences of an option win in `HandBrakeCLI`, so the user's custom args can always override what the vendor branch chose.
- Dockerfile: `ENV GPU_VENDOR=none` plus the build-time dumps `/usr/local/share/handbrake-version.txt`, `/usr/local/share/handbrake-cli-help.txt`, `/usr/local/share/handbrake-preset-list.txt`.
- `docs/handbrake-capabilities.md` — the recorded encoder/preset/toolkit capabilities of the build.
- Log prefix for this script: `[handbrake-gpu]`. Do not invent a second prefix.

Because `/run/handbrake/gpu-args` is only read by the watch daemon, **`GPU_VENDOR` affects automated watch-folder conversion only.** In the GUI the user picks the encoder themselves; NVENC simply appears in HandBrake's encoder dropdown once the driver libraries are present. Task 7 documents that distinction.

---

## Why the encoder check asks the live binary (read before Task 2)

**This corrects an instruction inherited from Plan 1**, and it is the reason the
encoder lookup in Task 4 is not a `grep` over the recorded help dump.

`libhb` does not list every encoder it was compiled with. `hb_common_global_init()`
gates each entry on `hb_video_encoder_is_enabled()`, which for hardware encoders
calls the vendor's **live** availability probe before the encoder is ever added to
the list that `hb_video_encoder_get_next()` walks — and that list is exactly what
`HandBrakeCLI --help` prints under `-e, --encoder`
(HandBrake 1.11.x, `libhb/common.c`):

```c
#if HB_PROJECT_FEATURE_NVENC
            case HB_VCODEC_FFMPEG_NVENC_H264:
                return hb_nvenc_h264_available();
            case HB_VCODEC_FFMPEG_NVENC_H265:
            case HB_VCODEC_FFMPEG_NVENC_H265_10BIT:
                return hb_nvenc_h265_available();
#endif
```

So an encoder appears in `--help` only when it is **compiled in AND usable on the
hardware present right now**. Two consequences drive this plan:

1. **`/usr/local/share/handbrake-cli-help.txt` can never contain `nvenc_h264`.**
   It is recorded during `docker build`, where no NVIDIA runtime is injected, so
   `hb_nvenc_h264_available()` returns false and every `nvenc_*` id is filtered
   out before the text is written. A dump-based lookup would therefore fail on
   **every** machine, including one with a working RTX 4070 Ti SUPER, and the
   `nvidia` branch would always fall through to software encoding — the exact
   opposite of this plan's purpose.
2. **Asking the live binary is simultaneously the identifier lookup and the
   hardware probe.** It satisfies "never guess an encoder identifier" more
   strictly than the dump ever did, because a listed id is proof that HandBrake
   itself can currently use it.

**The `--enable-hw-decoding` help text is a different case and is NOT affected.**
It is a static literal in `test/test.c`'s `ShowHelp()`, guarded only by a
compile-time preprocessor conditional, with no runtime probe anywhere near it:

```c
"   --enable-hw-decoding <string>                                        \n"
#if defined( __APPLE_CC__ )
"                           Use 'videotoolbox' to enable VideoToolbox    \n"
#else
"                           Use 'nvdec' to enable NVDec                  \n"
"                           Use 'qsv' to enable QSV decoding             \n"
#endif
```

The dump and the live binary are the same binary, so for compile-time-gated text
they print identical output. `hb_help_lists_nvdec()` therefore **keeps** reading
the dump: it is correct there, it costs nothing, and it is only ever used to
decide whether to print an informational line. Do not "consistency-fix" it onto
the live probe.

Plan 3 (`docs/superpowers/plans/2026-08-12-handbrake-intel-amd-gpu.md`) reached
the same conclusion independently while designing the QSV/VCE branches and
records it as finding 1 of its research section. Task 4 below uses Plan 3's
helper names (`hb_load_encoders`, `hb_has_encoder`, `hb_pick_encoder`) with
identical semantics, so that when the two branches meet in one file there is one
probe, not two.

---

### Task 1: Preflight — the Plan 1 seam is present and intact

**Files:**
- Modify: none. Verification only.

**Interfaces:**
- Consumes: everything Plan 1 shipped.
- Produces: certainty that the seam this plan extends still looks the way Plan 1 described it, plus a locally built `handbrake:dev` image for Tasks 2 and 5.

- [ ] **Step 1: Confirm the four seam anchors exist verbatim**

```bash
cd /d/nextcloud/it/github/handbrake
git fetch origin && git status --short --branch
grep -n 'gpu_args_for_vendor()' rootfs/usr/local/bin/handbrake-gpu.sh
grep -n 'handbrake-gpu.sh' rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/run
grep -n 'HB_GPU_ARGS' rootfs/usr/local/bin/handbrake-watch.sh
grep -n 'GPU_VENDOR=none' Dockerfile
```
Expected: a clean working tree on `main`, and one hit for each grep (`HB_GPU_ARGS` has three: the `read -r -a`, the `[ "${#HB_GPU_ARGS[@]}" -gt 0 ]` guard and the `args+=` line). If any grep is empty, Plan 1 is not implemented or was changed — stop and report, do not improvise a different seam.

- [ ] **Step 2: Build the image the rest of this plan measures against**

```bash
cd /d/nextcloud/it/github/handbrake
docker build -t handbrake:dev .
```
Expected: the build succeeds and prints the `handbrake: HandBrake 1.11…` capability line from Plan 1's assertion layer.

- [ ] **Step 3: Confirm the software default is untouched before any change**

`init-handbrake` normally creates `/run/handbrake` before calling the script; a bare `--entrypoint sh` run has to do it itself, otherwise the shell prints a redirection warning for `/run/handbrake/gpu-vendor` on top of the real output.

Run:
```bash
docker run --rm --entrypoint sh handbrake:dev -c \
  'mkdir -p /run/handbrake; /usr/local/bin/handbrake-gpu.sh none; echo "[exit $?]"'
```
Expected: stderr line `[handbrake-gpu] GPU acceleration: none — software encoding (x264/x265)`, no stdout content before `[exit 0]`.

---

### Task 2: Record the bundled build's real NVENC capabilities

Every string this plan later relies on is read from the built image here. Do not paste values from memory, from the HandBrake website, or from this plan — paste what the commands print.

**Files:**
- Create: `d:\nextcloud\it\github\handbrake\docs\hardware-encoding-nvidia.md`

**Interfaces:**
- Consumes: `handbrake:dev` (Task 1), the in-image dump `/usr/local/share/handbrake-cli-help.txt` (Plan 1, Task 3) for the **statically printed** help text only, and the live `HandBrakeCLI` binary for anything hardware-filtered.
- Produces: the recorded proof that hardware encoders are absent from both lists on a GPU-less machine, the confirmed `--enable-hw-decoding` spelling, and the confirmed hardware-preset names that Tasks 4 and 7 use.

- [ ] **Step 1: Record what the encoder lists actually say on this GPU-less machine**

Read "Why the encoder check asks the live binary" above first. The expected result of this step is **no `nvenc_*` identifiers anywhere**, and that is a pass, not a failure — it is the measurement that justifies the live probe in Task 4. Run all three commands and record all three outputs.

**1a — the build-time dump** (this is the extraction the *old* dump-based lookup performed, kept here only to document that it cannot work):

```bash
docker run --rm --entrypoint sh handbrake:dev -c \
  'sed -n "/-e, --encoder/,/^[[:space:]]*-[a-zA-Z-]/p" /usr/local/share/handbrake-cli-help.txt \
     | tr " ,\t" "\n\n\n" | grep -E "^nvenc" | sort -u'
```
Expected: **empty.** The dump was written during `docker build` on a GPU-less builder, where `hb_nvenc_h264_available()` returns false, so `libhb` filtered every `nvenc_*` id out before printing. If this is *not* empty, the builder had an NVIDIA runtime attached — record that fact and report it, because it would change nothing in the script (the live probe is still correct) but it would mean this image is not reproducible.

**1b — the live encoder list, extracted exactly as `hb_load_encoders()` will at run time** (section-scoped, one id per line, whitespace-trimmed), so its output also tests the matcher:

```bash
docker run --rm --entrypoint sh handbrake:dev -c \
  "HandBrakeCLI --help 2>/dev/null | awk '/^[[:space:]]*-e, --encoder[[:space:]]/{f=1;next} f&&/^[[:space:]]*-/{f=0} f' \
     | sed 's/^[[:space:]]*//;s/[[:space:]]*\$//' | grep -v '^\$'"
```
Expected: the software encoders (`x264`, `x265`, `svt_av1`, …) and **no** `nvenc_*`, for the same reason — this dev box has no NVIDIA runtime either. The decisive check is that the list is **non-empty and parses into one id per line**: that proves the extraction works, which is the part Task 4 depends on. An empty list means the awk section anchor does not match this build's help layout — stop and report that, because the probe would then be blind.

**1c — evidence that the binary really was compiled with NVENC**, which is GPU-independent (the identifiers are string literals inside the binary whether or not the hardware probe passes):

```bash
docker run --rm --entrypoint sh handbrake:dev -c \
  'grep -a -o -E "nvenc_(h264|h265|av1)" "$(command -v HandBrakeCLI)" | sort -u'
```
Expected: `nvenc_h264`, `nvenc_h265` and possibly `nvenc_av1` — Ubuntu passes `--enable-nvenc` on amd64. If this is empty **and** 1b is empty, the build genuinely has no NVENC support and Task 9 cannot pass; stop and report before spending time on the hardware box. (Absence here is weaker evidence than presence: `libhb` may be linked as a shared object rather than statically. If it is empty, confirm against `docs/handbrake-capabilities.md` from Plan 1 rather than concluding anything.)

Record all three outputs; they go into Step 6. **The authoritative `nvenc_*` identifier list for this build is recorded on real hardware in Task 9, Step 6** — that is the first machine where `libhb` will admit to having them.

- [ ] **Step 2: Record the valid `--encoder-preset` names for the first NVENC encoder**

```bash
docker run --rm --entrypoint sh handbrake:dev -c \
  'HandBrakeCLI --encoder-preset-list nvenc_h264 2>&1'
```
Expected on this GPU-less box: **most likely an "unrecognized encoder" style error or empty output**, for exactly the reason Step 1 recorded — `--encoder-preset-list` resolves its argument through the same hardware-filtered encoder table, so an encoder that `--help` will not list cannot be looked up by name either. That is not a failure of this step.

- If it prints preset names, record them now.
- If it errors or prints nothing, **record that verbatim and move on.** Task 9, Step 6 re-runs this one command on the real GPU box, where the encoder resolves, and Task 10 fills the recorded output in. Do not try to work around it here, and do not fall back to naming presets from memory.

This matters because the default preset `General/Very Fast 1080p30` carries the x264 speed name `veryfast`, which is **not** in this list. Task 7 documents how a user picks a valid one.

- [ ] **Step 3: Record the hardware-decoding option spelling**

```bash
docker run --rm --entrypoint sh handbrake:dev -c \
  'grep -A3 -- "--enable-hw-decoding" /usr/local/share/handbrake-cli-help.txt'
```
Expected: the help entry for `--enable-hw-decoding`, whose text names `nvdec`. Record it verbatim.

**The dump is the right source here, unlike Step 1.** This help entry is a static literal in `ShowHelp()` gated only by a compile-time `#if`, not by a hardware probe, so the dump and a live `--help` print it identically. This is the one place `handbrake-gpu.sh` still reads the dump, and Task 4 keeps it that way on purpose.

- [ ] **Step 4: Record HandBrake's own NVENC presets, if this build ships any**

```bash
docker run --rm --entrypoint sh handbrake:dev -c \
  'grep -i -B2 "nvenc" /usr/local/share/handbrake-preset-list.txt | head -n 40'
```
Expected: either preset names containing `NVENC` (with the category line above them) or no output. Both are valid results — record which one you got, because Task 4's "do not override a preset that already selects NVENC" rule and Task 7's README wording both refer to it.

- [ ] **Step 5: Record the HandBrake version the above belongs to**

```bash
docker run --rm --entrypoint sh handbrake:dev -c 'cat /usr/local/share/handbrake-version.txt'
cd /d/nextcloud/it/github/handbrake && git rev-parse --short HEAD && date -I
```

- [ ] **Step 6: Write the document with the recorded output**

Create `d:\nextcloud\it\github\handbrake\docs\hardware-encoding-nvidia.md`. Replace every `<paste …>` with the literal text the commands printed — nothing else:

````markdown
# NVIDIA NVENC hardware encoding in this image

Everything below was **measured**, not assumed. Regenerate the recorded sections
with the commands shown after every base-image or HandBrake version bump.

Image built from commit `<paste: git rev-parse --short HEAD>` on `<paste: date -I>`,
HandBrake version:

```text
<paste the output of Step 5>
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
<paste the output of Step 1a — expected to be empty>
```

**A live `--help` on a GPU-less machine says the same thing**, which is why the
absence above is a property of the hardware, not of the build:

```sh
docker run --rm --entrypoint sh handbrake:dev -c \
  "HandBrakeCLI --help 2>/dev/null | awk '/^[[:space:]]*-e, --encoder[[:space:]]/{f=1;next} f&&/^[[:space:]]*-/{f=0} f' \
     | sed 's/^[[:space:]]*//;s/[[:space:]]*\$//' | grep -v '^\$'"
```

```text
<paste the output of Step 1b>
```

**The binary was nevertheless built with NVENC** — the identifiers are string
literals inside it regardless of the hardware probe:

```sh
docker run --rm --entrypoint sh handbrake:dev -c \
  'grep -a -o -E "nvenc_(h264|h265|av1)" "$(command -v HandBrakeCLI)" | sort -u'
```

```text
<paste the output of Step 1c>
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
<paste the output of Step 2>
```

The x264/x265 speed names (`veryfast`, `medium`, …) that HandBrake's software
presets carry are **not** in this list. HandBrake maps an unknown name onto its
own default rather than failing the job, so a software preset plus
`--encoder nvenc_*` still runs; a user who wants explicit control appends
`--encoder-preset <name from this list>` through
`AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS`.

## 3. Hardware decoding (NVDEC)

```sh
docker run --rm --entrypoint sh handbrake:dev -c \
  'grep -A3 -- "--enable-hw-decoding" /usr/local/share/handbrake-cli-help.txt'
```

```text
<paste the output of Step 3>
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
<paste the output of Step 4, or the line "no NVENC presets in this build">
```
````

- [ ] **Step 7: Verify no placeholder survived**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
grep -n '<paste' docs/hardware-encoding-nvidia.md && echo "PLACEHOLDERS LEFT — fix them" || echo "no placeholders"
```
Expected: `no placeholders`.

- [ ] **Step 8: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add docs/hardware-encoding-nvidia.md
git commit -m "docs: record the NVENC encoders, presets and decode options of this build"
```

---

### Task 3: Confirm and record the host-side NVIDIA requirements

**Files:**
- Modify: `d:\nextcloud\it\github\handbrake\docs\hardware-encoding-nvidia.md` (append sections 5 and 6)

**Interfaces:**
- Consumes: nothing from the image.
- Produces: the confirmed `NVIDIA_DRIVER_CAPABILITIES` value and minimum driver version that Task 7's README section and Task 9's `docker run` command both use.

- [ ] **Step 1: Read the capability table out of NVIDIA's own documentation**

```bash
curl -fsSL https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/docker-specialized.html \
  | sed -e 's/<[^>]*>/ /g' -e 's/  */ /g' \
  | grep -iE 'compute|compat32|graphics|utility|video|display' \
  | grep -iE 'required|capabilit' | head -n 20
```
Expected: the capability descriptions, including `compute` (CUDA and OpenCL), `utility` (`nvidia-smi` and NVML) and `video` (the Video Codec SDK, which is what NVENC and NVDEC are). Note also that the documented default when the variable is unset is `utility,compute` — which is exactly why NVENC fails without an explicit value: `video` is missing.

Record the three lines you need. If the page has moved, fetch
`https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/` and follow its "Specialized Configurations" link rather than guessing the value.

- [ ] **Step 2: Read HandBrake's minimum NVIDIA driver version**

```bash
curl -fsSL https://handbrake.fr/docs/en/latest/technical/video-nvenc.html \
  | sed -e 's/<[^>]*>/ /g' -e 's/  */ /g' | grep -iE 'driver' | head -n 10
```
Expected: a line naming the minimum NVIDIA graphics driver version HandBrake requires for NVENC. Record the exact version string — Task 9, Step 2 compares the box's driver against it.

- [ ] **Step 3: Append sections 5 and 6 to the document**

Append to `d:\nextcloud\it\github\handbrake\docs\hardware-encoding-nvidia.md`, filling in the values recorded in Steps 1 and 2:

````markdown

## 5. What the host has to provide

| Requirement | Value | Why |
|---|---|---|
| Unraid plugin | Nvidia-Driver (ich777) | installs the NVIDIA kernel driver and the NVIDIA container runtime |
| Container runtime | `--runtime=nvidia` in Extra Parameters | without it the container gets no `/dev/nvidia*` node and no driver libraries |
| `NVIDIA_VISIBLE_DEVICES` | a GPU UUID from `nvidia-smi -L`, or `all` | selects which GPU is passed in |
| `NVIDIA_DRIVER_CAPABILITIES` | `compute,video,utility` | `video` injects `libnvidia-encode.so.1` (NVENC/NVDEC), `compute` the CUDA runtime, `utility` `nvidia-smi`. `all` also works |
| NVIDIA driver | `<paste the minimum version recorded in Step 2>` or newer | HandBrake's documented NVENC requirement |

Source for the capability meanings:
<https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/docker-specialized.html>
— `compute` "required for CUDA and OpenCL applications", `utility` "required for
using nvidia-smi and NVML", `video` "required for using the Video Codec SDK".
With the variable unset the runtime defaults to `utility,compute`, i.e. **no
`video`**, which is why NVENC needs it set explicitly.

Source for the driver requirement:
<https://handbrake.fr/docs/en/latest/technical/video-nvenc.html>

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
````

- [ ] **Step 4: Verify**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
grep -n '<paste' docs/hardware-encoding-nvidia.md && echo "PLACEHOLDERS LEFT — fix them" || echo "no placeholders"
grep -c '^## ' docs/hardware-encoding-nvidia.md
```
Expected: `no placeholders` and `6`.

- [ ] **Step 5: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add docs/hardware-encoding-nvidia.md
git commit -m "docs: record the host-side NVIDIA runtime requirements for NVENC"
```

---

### Task 4: Implement the `nvidia` branch of `gpu_args_for_vendor()`

**Files:**
- Modify: `d:\nextcloud\it\github\handbrake\rootfs\usr\local\bin\handbrake-gpu.sh` — the whole file is rewritten below. (Line numbers are not quoted on purpose: this file is created by Plan 1, Task 6, Step 1, and its final line numbers depend on that commit. The anchors are the `log()` helper block above `VENDOR_RAW=` and the `gpu_args_for_vendor()` function.) Nothing outside this file changes.

**Interfaces:**
- Consumes: `GPU_VENDOR` (argument `$1`, normalised by the existing `case` block), `AUTOMATED_CONVERSION_PRESET` from the container environment, a live `HandBrakeCLI --help` call for the encoder list, `/usr/local/share/handbrake-cli-help.txt` for the static `--enable-hw-decoding` text only, and the driver libraries the NVIDIA container runtime injects.
- Produces: on stdout, either an empty string (software) or `--encoder <nvenc id>`; on stderr, the `[handbrake-gpu]` decision block. `init-handbrake` and `handbrake-watch.sh` need no change whatsoever.

- [ ] **Step 1: Replace `rootfs/usr/local/bin/handbrake-gpu.sh` with this exact content**

```bash
#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# handbrake-gpu.sh <vendor>
# ---------------------------------------------------------------------------
# Resolves GPU_VENDOR into the extra HandBrakeCLI arguments used for hardware
# encoding. Prints the argument string on STDOUT (empty = software encoding) and
# a human-readable decision block on STDERR.
#
# Implemented vendors:
#   none    software encoding (x264/x265) — the default
#   nvidia  NVENC hardware encoding, when the container really has a usable
#           NVIDIA GPU. When it does not, this script says so loudly, names the
#           exact fix and falls back to software encoding — it never emits
#           arguments that would make every single job fail.
#
# The arguments only affect the AUTOMATED WATCH-FOLDER daemon, which is the only
# reader of /run/handbrake/gpu-args. In the GUI the user picks the encoder
# themselves; NVENC shows up in HandBrake's own encoder list as soon as the
# driver libraries are present.
#
# HOW AN ENCODER IS FOUND: BY ASKING THE RUNNING HANDBRAKE
#   libhb lists a hardware encoder in --help only when it is BOTH compiled in
#   AND usable on the hardware present right now (libhb/common.c:
#   hb_video_encoder_is_enabled() -> hb_nvenc_h264_available()). One --help call
#   is therefore the identifier lookup and the hardware probe at the same time,
#   and no encoder id is ever hardcoded into an argument.
#
#   Do NOT use the build-time dump /usr/local/share/handbrake-cli-help.txt for
#   this. It is recorded during `docker build` on a machine with no GPU, so it
#   never contains a single hardware encoder and the lookup would fail even on a
#   working GPU. See docs/hardware-encoding-nvidia.md section 1.
#
# EXTENSION POINT — this is the ONLY place a GPU plan needs to touch:
#   * add the vendor's branch to gpu_args_for_vendor()
#   * give it a candidate list and resolve it with hb_pick_encoder (never a
#     guessed name, never the build-time dump)
# The watch daemon and the init oneshot need no changes at all.
# ---------------------------------------------------------------------------
set -eu

log() { echo "[handbrake-gpu] $*" >&2; }

# Build-time dump of `HandBrakeCLI --help` (written by the Dockerfile). Valid
# ONLY for help text that libhb prints unconditionally, such as the
# --enable-hw-decoding entry. It is NOT valid for the encoder list — see the
# header comment above and hb_load_encoders() below.
HB_CLI_HELP="/usr/local/share/handbrake-cli-help.txt"

# NVENC encoder preference order. H.264 comes FIRST on purpose: the default
# preset (General/Very Fast 1080p30) is an x264 preset, so nvenc_h264 keeps the
# delivered codec identical and swaps only the encoder implementation — the
# whole promise of "hardware acceleration", with no surprise HEVC files that an
# older TV refuses to play. Anyone who wants HEVC appends
# "--encoder nvenc_h265" to AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS, which
# the watch daemon splices in AFTER these arguments, so the later value wins.
NVENC_CANDIDATES=(nvenc_h264 nvenc_h265)

# --- capability probes ------------------------------------------------------

# Cache of the encoder ids the running HandBrakeCLI offers on THIS machine.
# HB_ENCODERS_LOADED is a separate flag on purpose: "the list is empty" is a
# legitimate answer (a build with no hardware encoders), so emptiness must not
# be used as "not loaded yet". Overloading it would re-run HandBrakeCLI --help
# once per candidate and print the warning below once per candidate too.
HB_ENCODERS=""
HB_ENCODERS_LOADED=0

# hb_load_encoders — ask the real binary, once, what it can encode here.
#
# This is the live hardware probe, not a lookup in a recorded file: libhb only
# lists nvenc_* after hb_nvenc_h264_available() has said yes, so an id appearing
# here is proof that HandBrake can use it right now. The build-time dump is
# recorded without a GPU and would always answer "no".
#
# Call this from the PARENT shell before using hb_pick_encoder. hb_pick_encoder
# is used inside a command substitution, which runs in a subshell, so a cache
# filled there would be thrown away and every candidate would cost another
# HandBrakeCLI --help call. Filling it here means exactly one call per start.
hb_load_encoders() {
    if [ "${HB_ENCODERS_LOADED}" = "1" ]; then
        return 0
    fi
    HB_ENCODERS_LOADED=1
    local raw=""
    raw="$(HandBrakeCLI --help 2>/dev/null || true)"
    HB_ENCODERS="$(printf '%s\n' "${raw}" | awk '
        /^[[:space:]]*-e, --encoder[[:space:]]/ { inlist = 1; next }
        inlist && /^[[:space:]]*-/              { inlist = 0 }
        inlist {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            if ($0 != "") print
        }
    ')"
    if [ -z "${HB_ENCODERS}" ]; then
        log "WARNING: 'HandBrakeCLI --help' produced no encoder list — hardware detection cannot run."
    fi
}

hb_has_encoder() {
    # True when the running HandBrakeCLI offers encoder id $1 on this machine.
    hb_load_encoders
    printf '%s\n' "${HB_ENCODERS}" | grep -qxF -- "$1"
}

# hb_pick_encoder <id> [id...] — print the first id the binary offers here and
# return 0; return 1 when it offers none of them.
# Callers MUST append '|| true': under 'set -e' a command substitution that
# returns non-zero would otherwise kill the script before the error block runs.
hb_pick_encoder() {
    local id
    for id in "$@"; do
        if hb_has_encoder "${id}"; then
            printf '%s' "${id}"
            return 0
        fi
    done
    return 1
}

hb_help_lists_nvdec() {
    # True when this build advertises --enable-hw-decoding with nvdec.
    #
    # This one reads the build-time dump ON PURPOSE, and that is correct here:
    # the --enable-hw-decoding help text is a static literal in ShowHelp(),
    # guarded only by a compile-time #if and never by a hardware probe, so the
    # dump and a live --help print it identically. Decode capability and the
    # hardware ENCODER list are different things in HandBrake's help output.
    # Do not "consistency-fix" this onto hb_has_encoder.
    [ -r "${HB_CLI_HELP}" ] || return 1
    grep -A3 -- '--enable-hw-decoding' "${HB_CLI_HELP}" 2>/dev/null \
        | grep -qi 'nvdec'
}

nvidia_device_present() {
    # The NVIDIA container runtime creates these nodes. Without --runtime=nvidia
    # (Unraid: Extra Parameters) none of them exist.
    local d
    for d in /dev/nvidiactl /dev/nvidia[0-9]* /dev/nvidia-uvm; do
        if [ -e "${d}" ]; then
            return 0
        fi
    done
    return 1
}

nvidia_lib_path() {
    # Prints the path of an injected NVIDIA driver library, or returns 1.
    # The runtime drops the libraries into the distro multiarch directory and
    # runs ldconfig, so both lookups are legitimate.
    local name="$1" p
    for p in /usr/lib/*/"${name}" /usr/lib64/"${name}" /usr/local/nvidia/lib64/"${name}"; do
        if [ -e "${p}" ]; then
            printf '%s' "${p}"
            return 0
        fi
    done
    p="$(ldconfig -p 2>/dev/null | awk -v n="${name}" '$1 == n { print $NF; exit }')" || p=""
    if [ -n "${p}" ] && [ -e "${p}" ]; then
        printf '%s' "${p}"
        return 0
    fi
    return 1
}

nvidia_smi_summary() {
    # Optional detail line. nvidia-smi is only injected with the "utility"
    # capability, so its absence is a missing nicety, never an error.
    command -v nvidia-smi >/dev/null 2>&1 || return 1
    nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | head -n 1
}

# --- vendor normalisation ---------------------------------------------------

VENDOR_RAW="${1:-none}"
VENDOR="$(printf '%s' "${VENDOR_RAW}" | tr '[:upper:]' '[:lower:]')"

case "${VENDOR}" in
    ""|none|off|disabled) VENDOR="none" ;;
    nvidia|nvenc)         VENDOR="nvidia" ;;
    intel|qsv)            VENDOR="intel" ;;
    amd|vce|vcn)          VENDOR="amd" ;;
    *)
        log "unrecognised GPU_VENDOR='${VENDOR_RAW}' — use none, nvidia, intel or amd"
        VENDOR="none"
        ;;
esac

gpu_args_for_vendor() {
    local encoder="" lib_encode="" lib_decode="" detail="" args=""
    case "$1" in
        none)
            printf ''
            log "GPU acceleration: none — software encoding (x264/x265)"
            ;;
        nvidia)
            # -- 1) Is an NVIDIA GPU passed into this container at all? --------
            if ! nvidia_device_present; then
                printf ''
                log "ERROR: GPU_VENDOR=nvidia, but this container has no /dev/nvidia* device node,"
                log "       so it was not started through the NVIDIA container runtime."
                log "       Fix (Unraid): install the Nvidia-Driver plugin, put '--runtime=nvidia' into the"
                log "       container's Extra Parameters, and set NVIDIA_VISIBLE_DEVICES to a GPU UUID"
                log "       from 'nvidia-smi -L' on the host (or to 'all')."
                log "FALLING BACK TO SOFTWARE ENCODING for this container start."
                return 0
            fi

            # -- 2) Is the NVENC runtime library there? ------------------------
            # libnvidia-encode.so.1 is injected only when
            # NVIDIA_DRIVER_CAPABILITIES contains "video". Without it every
            # NVENC job would abort inside HandBrake with an opaque error.
            if ! lib_encode="$(nvidia_lib_path libnvidia-encode.so.1)"; then
                printf ''
                log "ERROR: GPU_VENDOR=nvidia and an NVIDIA device is present, but libnvidia-encode.so.1"
                log "       is missing — NVENC cannot run without it."
                log "       Fix: set NVIDIA_DRIVER_CAPABILITIES=compute,video,utility on the container."
                log "       The 'video' capability is the one that injects the encoder library ('all' works too)."
                log "FALLING BACK TO SOFTWARE ENCODING for this container start."
                return 0
            fi

            # -- 3) Does the RUNNING HandBrakeCLI offer an NVENC encoder here? -
            # Asking the live binary is both the identifier lookup and the final
            # hardware check: libhb hides nvenc_* until its own availability
            # probe passes. hb_load_encoders runs in THIS shell (not inside the
            # command substitution below) so the --help call happens once.
            hb_load_encoders
            encoder="$(hb_pick_encoder "${NVENC_CANDIDATES[@]}" || true)"
            if [ -z "${encoder}" ]; then
                printf ''
                log "ERROR: GPU_VENDOR=nvidia, the NVIDIA device node and libnvidia-encode.so.1 are both"
                log "       present, but HandBrakeCLI offers none of '${NVENC_CANDIDATES[*]}' on this machine."
                log "       HandBrake lists a hardware encoder only when it is compiled in AND currently"
                log "       usable, so one of these holds:"
                log "         * the NVIDIA driver is older than HandBrake's documented NVENC minimum"
                log "         * this GPU has no usable NVENC block (too old, or it is a model without one)"
                log "         * this build was not built with --enable-nvenc for this architecture"
                log "       Encoders HandBrakeCLI offers here: $(printf '%s' "${HB_ENCODERS}" | tr '\n' ' ')"
                log "FALLING BACK TO SOFTWARE ENCODING for this container start."
                return 0
            fi

            # -- 4) Do not fight a preset that already picked NVENC ------------
            # HandBrake ships its own hardware presets. If the user selected
            # one, they chose that codec deliberately — leave the preset alone
            # and let it drive the encoder.
            case "$(printf '%s' "${AUTOMATED_CONVERSION_PRESET:-}" | tr '[:upper:]' '[:lower:]')" in
                *nvenc*)
                    args=""
                    ;;
                *)
                    args="--encoder ${encoder}"
                    ;;
            esac

            printf '%s' "${args}"

            # -- 5) Say exactly what is in effect ------------------------------
            if detail="$(nvidia_smi_summary)"; then
                log "GPU acceleration: NVIDIA NVENC — ${detail}"
            else
                log "GPU acceleration: NVIDIA NVENC (no nvidia-smi in this container; add the 'utility'"
                log "                  capability to NVIDIA_DRIVER_CAPABILITIES to see the GPU name here)"
            fi
            log "encoder library: ${lib_encode}"
            if [ -z "${args}" ]; then
                log "preset '${AUTOMATED_CONVERSION_PRESET:-}' already selects an NVENC encoder — not overriding it"
            else
                log "HandBrakeCLI arguments: ${args}"
                log "NOTE: every watch-folder job now encodes with '${encoder}' and overrides the video"
                log "      encoder of AUTOMATED_CONVERSION_PRESET. Put '--encoder <id>' into"
                log "      AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS to pick a different one."
            fi
            if lib_decode="$(nvidia_lib_path libnvcuvid.so.1)" && hb_help_lists_nvdec; then
                log "NVDEC is available (${lib_decode}) but stays OFF: HandBrake disables hardware decoding"
                log "      as soon as any filter runs, which every stock preset does. Add"
                log "      '--enable-hw-decoding nvdec' to AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS to force it."
            fi
            ;;
        *)
            printf ''
            log "GPU_VENDOR='$1' requested, but this image build ships no GPU acceleration for that vendor yet."
            log "Falling back to software encoding. Hardware encoding for that vendor arrives in a later release."
            ;;
    esac
}

printf '%s' "${VENDOR}" > /run/handbrake/gpu-vendor 2>/dev/null || true
gpu_args_for_vendor "${VENDOR}"
```

Note the deliberate refactors inside this same file: the `log()` helper replaces the repeated `echo "[handbrake-gpu] …" >&2` lines (DRY, identical output), and the vendor-normalisation `case` now logs through it. The `none` branch, the catch-all branch, the stdout/stderr contract and the `/run/handbrake/gpu-vendor` write are byte-for-byte the behaviour Plan 1 defined.

**All three probes now answer the same kind of question the same way — "what is true in this container right now".** The device check reads `/dev`, the library check reads the filesystem and `ldconfig`, and the encoder check asks the binary. None of them consults a value recorded at build time. That symmetry is the point: a build-time answer to a run-time question is what made the original dump-based lookup wrong (see "Why the encoder check asks the live binary"). `hb_help_lists_nvdec()` is the single, documented exception, because the text it reads is compile-time, not hardware-filtered.

Three shell traps in this file, each of which breaks the container silently:

1. **`encoder="$(hb_pick_encoder … || true)"` must keep its `|| true`.** Without it, `set -e` kills the script on "no encoder found", `init-handbrake` writes an empty `gpu-args` and logs a generic warning, and the user never sees the specific error block that names the fix.
2. **`hb_load_encoders` must be called from `gpu_args_for_vendor()` itself**, not left to `hb_has_encoder`. The `$( … )` around `hb_pick_encoder` is a subshell; a cache filled in there dies with it, and each candidate would spawn another `HandBrakeCLI --help`.
3. **Nothing new may reach stdout.** stdout is a command line, not a log. `HandBrakeCLI --help` is captured into a variable and its stderr is discarded precisely so it cannot leak into `/run/handbrake/gpu-args`.

Also note what the branch deliberately does **not** do: it does not run the probe as `abc` via `s6-setuidgid`. Plan 3 adds that refinement for Intel/AMD, where the render node is group-gated and it also adds the `init-video` ordering edge that makes it meaningful; `/dev/nvidia*` is world-accessible and this plan changes no s6 service, so the plain call is the honest one here. On merge, Plan 3's version supersedes it.

Also note what the branch deliberately does **not** emit: no `--encoder-preset` (HandBrake maps an unknown software preset name onto its own NVENC default, and forcing one would silently override the user's speed choice — Task 2, Step 2 recorded the valid names for the README instead), and no `--enable-hw-decoding nvdec` (Task 2, Step 6, section 3 records HandBrake's own reason). Do not "improve" either of them back in.

- [ ] **Step 2: Parse and lint**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
bash -n rootfs/usr/local/bin/handbrake-gpu.sh && echo "gpu parses"
shellcheck -S warning -x -e SC1091 rootfs/usr/local/bin/handbrake-gpu.sh && echo "shellcheck OK"
grep -c $'\r' rootfs/usr/local/bin/handbrake-gpu.sh || echo "LF OK"
```
Expected:
```
gpu parses
shellcheck OK
LF OK
```
(`grep -c` printing `0` and exiting 1 is why the `|| echo` is there; any other number means CRLF slipped in — fix it before committing.)

- [ ] **Step 3: Run the whole lint chain, exactly as CI will**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
just check
```
Expected: ends with `All lint checks passed.`

- [ ] **Step 4: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add rootfs/usr/local/bin/handbrake-gpu.sh
git commit -m "feat: add NVIDIA NVENC hardware encoding to the GPU seam"
```

---

### Task 5: Prove the fail-loud path (no GPU present)

This is the path most users will hit first — someone sets `GPU_VENDOR=nvidia` in the template and forgets `--runtime=nvidia`. It must be impossible to miss in the log, and conversions must keep working.

**Files:**
- Modify: none. Verification only.

**Interfaces:**
- Consumes: the script from Task 4, a GPU-less machine (the dev box or any CI runner).
- Produces: proof that a misconfigured GPU setting degrades loudly and safely.

- [ ] **Step 1: Rebuild the image with the new script**

```bash
cd /d/nextcloud/it/github/handbrake
docker build -t handbrake:dev .
```

- [ ] **Step 2: The `none` default is unchanged**

Run:
```bash
docker run --rm --entrypoint sh handbrake:dev -c \
  'mkdir -p /run/handbrake; /usr/local/bin/handbrake-gpu.sh none > /tmp/args 2>/tmp/logs; echo "exit=$?"; echo "args=[$(cat /tmp/args)]"; cat /tmp/logs'
```
Expected:
```
exit=0
args=[]
[handbrake-gpu] GPU acceleration: none — software encoding (x264/x265)
```

- [ ] **Step 3: `nvidia` on a GPU-less container fails loudly and emits no arguments**

Run:
```bash
docker run --rm --entrypoint sh handbrake:dev -c \
  'mkdir -p /run/handbrake; /usr/local/bin/handbrake-gpu.sh nvidia > /tmp/args 2>/tmp/logs; echo "exit=$?"; echo "args=[$(cat /tmp/args)]"; cat /tmp/logs'
```
Expected: `exit=0`, `args=[]`, and this exact six-line block:
```
[handbrake-gpu] ERROR: GPU_VENDOR=nvidia, but this container has no /dev/nvidia* device node,
[handbrake-gpu]        so it was not started through the NVIDIA container runtime.
[handbrake-gpu]        Fix (Unraid): install the Nvidia-Driver plugin, put '--runtime=nvidia' into the
[handbrake-gpu]        container's Extra Parameters, and set NVIDIA_VISIBLE_DEVICES to a GPU UUID
[handbrake-gpu]        from 'nvidia-smi -L' on the host (or to 'all').
[handbrake-gpu] FALLING BACK TO SOFTWARE ENCODING for this container start.
```

- [ ] **Step 4: A whole container with `GPU_VENDOR=nvidia` still boots and still converts**

```bash
cd /d/nextcloud/it/github/handbrake
docker rm -f hb-nogpu 2>/dev/null || true
docker run -d --name hb-nogpu --cpus=4 --memory=4g -e GPU_VENDOR=nvidia handbrake:dev
sleep 45
docker logs hb-nogpu 2>&1 | grep -E '\[handbrake-gpu\]|\[init-handbrake\] gpu-args'
docker exec hb-nogpu sh -c 'echo "gpu-args=[$(cat /run/handbrake/gpu-args)]"; echo "gpu-vendor=$(cat /run/handbrake/gpu-vendor)"'
```
Expected: the same error block in `docker logs`, then `[init-handbrake] gpu-args: '' (vendor nvidia)`, `gpu-args=[]` and `gpu-vendor=nvidia`.

- [ ] **Step 5: The watch folder still works in software**

```bash
ffmpeg -v error -y -f lavfi -i testsrc=size=320x240:rate=15:duration=2 \
       -c:v libx264 -pix_fmt yuv420p /tmp/hb-nogpu.mkv
docker cp /tmp/hb-nogpu.mkv hb-nogpu:/watch/hb-nogpu.mkv
docker exec hb-nogpu chown abc:abc /watch/hb-nogpu.mkv
for i in $(seq 1 120); do
  if docker exec hb-nogpu test -s /output/hb-nogpu.mp4 2>/dev/null; then echo "converted after ${i}s"; break; fi
  sleep 1
done
docker exec hb-nogpu sh -c 'ls -l /output'
```
Expected: `converted after <n>s` and a non-empty `/output/hb-nogpu.mp4`. A wrong `GPU_VENDOR` must never cost the user their conversions.

- [ ] **Step 6: Clean up**

```bash
docker rm -f hb-nogpu
rm -f /tmp/hb-nogpu.mkv
```

---

### Task 6: Prove the selection logic with a faked NVIDIA environment

The fail-loud path is now proven; this proves the opposite branch — that when all three probes are satisfied the script picks a real encoder and emits the right argument string.

**Each probe is faked at its own input boundary, and there are three, not two.** `/dev` inside a container is a writable tmpfs, so a plain file at `/dev/nvidiactl` satisfies the device probe, and a stub file in the multiarch library directory satisfies the library probe — neither is ever opened by this script. The third probe asks `HandBrakeCLI --help`, so it is faked by shadowing `HandBrakeCLI` on `PATH` with a script that prints a synthetic help block. That is the only way to exercise the success path off real hardware: the whole point of the live probe is that a GPU-less machine's real `HandBrakeCLI` will not list `nvenc_*` (Task 2, Step 1b measured exactly that).

**What this task does and does not prove.** It proves the selection logic, the argument string, the preset guard and the word-splitting round trip — all pure shell behaviour. It proves nothing about NVENC actually working. That is Task 9's job, on the real GPU, and no amount of faking here substitutes for it.

**Files:**
- Modify: none. Verification only.

**Interfaces:**
- Consumes: `handbrake:dev` from Task 5.
- Produces: proof of the encoder pick, of the argument string, of the "preset already selects NVENC" rule, and of the third error block.

- [ ] **Step 1: Fake a fully usable NVIDIA container and read the emitted arguments**

The stub prints just enough of a real `--help` for the `-e, --encoder` section anchor to match. It deliberately lists `x264` alongside the NVENC ids, so the run also proves the matcher selects by exact id rather than picking the first line it sees.

```bash
docker run --rm --entrypoint sh handbrake:dev -c '
  set -e
  mkdir -p /run/handbrake /tmp/hbstub
  : > /dev/nvidiactl
  libdir=$(dirname "$(find /usr/lib -maxdepth 2 -name libc.so.6 | head -n1)")
  echo "faking the driver library in ${libdir}"
  : > "${libdir}/libnvidia-encode.so.1"
  cat > /tmp/hbstub/HandBrakeCLI <<STUB
#!/bin/sh
echo "   -e, --encoder <string>  Select video encoder:"
echo "                               x264"
echo "                               x265"
echo "                               nvenc_h264"
echo "                               nvenc_h265"
echo "   -q, --quality <float>   Set video quality"
STUB
  chmod 0755 /tmp/hbstub/HandBrakeCLI
  export PATH=/tmp/hbstub:$PATH
  /usr/local/bin/handbrake-gpu.sh nvidia > /tmp/args 2>/tmp/logs
  echo "exit=$?"
  echo "args=[$(cat /tmp/args)]"
  cat /tmp/logs
'
```
Expected: the fake library lands in the multiarch directory (`/usr/lib/x86_64-linux-gnu` on amd64, `/usr/lib/aarch64-linux-gnu` on arm64 — if it prints `.` instead, `libc.so.6` was not found and the rest of this step is meaningless), then `exit=0`, `args=[--encoder nvenc_h264]`, and a log block containing:
```
[handbrake-gpu] GPU acceleration: NVIDIA NVENC (no nvidia-smi in this container; add the 'utility'
[handbrake-gpu] encoder library: /usr/lib/<arch>/libnvidia-encode.so.1
[handbrake-gpu] HandBrakeCLI arguments: --encoder nvenc_h264
[handbrake-gpu] NOTE: every watch-folder job now encodes with 'nvenc_h264' and overrides the video
```
`nvenc_h264` and not `x264` is the assertion that matters here: it proves `hb_pick_encoder` walks `NVENC_CANDIDATES` in preference order and matches whole ids.

- [ ] **Step 2: A preset that already selects NVENC is left alone**

```bash
docker run --rm --entrypoint sh -e AUTOMATED_CONVERSION_PRESET='Hardware/H.265 NVENC 1080p' handbrake:dev -c '
  set -e
  mkdir -p /run/handbrake /tmp/hbstub
  : > /dev/nvidiactl
  libdir=$(dirname "$(find /usr/lib -maxdepth 2 -name libc.so.6 | head -n1)")
  : > "${libdir}/libnvidia-encode.so.1"
  cat > /tmp/hbstub/HandBrakeCLI <<STUB
#!/bin/sh
echo "   -e, --encoder <string>  Select video encoder:"
echo "                               nvenc_h264"
echo "   -q, --quality <float>   Set video quality"
STUB
  chmod 0755 /tmp/hbstub/HandBrakeCLI
  export PATH=/tmp/hbstub:$PATH
  /usr/local/bin/handbrake-gpu.sh nvidia > /tmp/args 2>/tmp/logs
  echo "args=[$(cat /tmp/args)]"
  grep "already selects" /tmp/logs
'
```
Expected: `args=[]` and the line
`[handbrake-gpu] preset 'Hardware/H.265 NVENC 1080p' already selects an NVENC encoder — not overriding it`.

- [ ] **Step 3: A device node without the library is reported as a capabilities problem**

No stub needed: the script must fail at probe 2 and never reach the encoder question.

```bash
docker run --rm --entrypoint sh handbrake:dev -c '
  mkdir -p /run/handbrake
  : > /dev/nvidiactl
  /usr/local/bin/handbrake-gpu.sh nvidia > /tmp/args 2>/tmp/logs
  echo "args=[$(cat /tmp/args)]"
  cat /tmp/logs
'
```
Expected: `args=[]` and the error block naming `libnvidia-encode.so.1` and the fix `NVIDIA_DRIVER_CAPABILITIES=compute,video,utility`. This is the second-most-likely user mistake after a missing `--runtime=nvidia`, and it must not be reported as "no GPU". It must also **not** mention the encoder list — reaching probe 3 here would mean the ordering broke.

- [ ] **Step 4: A usable-looking GPU whose HandBrake offers no NVENC hits the third error block**

This is the branch the old dump-based lookup could never distinguish, and on a GPU-less machine it is reachable for real — fake the device and the library but leave the genuine `HandBrakeCLI` in place, and the live probe correctly refuses:

```bash
docker run --rm --entrypoint sh handbrake:dev -c '
  mkdir -p /run/handbrake
  : > /dev/nvidiactl
  libdir=$(dirname "$(find /usr/lib -maxdepth 2 -name libc.so.6 | head -n1)")
  : > "${libdir}/libnvidia-encode.so.1"
  /usr/local/bin/handbrake-gpu.sh nvidia > /tmp/args 2>/tmp/logs
  echo "args=[$(cat /tmp/args)]"
  cat /tmp/logs
'
```
Expected: `args=[]`, and an error block that
- names the encoders that *were* offered (the software list from Task 2, Step 1b) on the `Encoders HandBrakeCLI offers here:` line,
- lists the three possible causes (driver too old, no usable NVENC block, not built with `--enable-nvenc`),
- ends with `FALLING BACK TO SOFTWARE ENCODING for this container start.`

It must **not** claim the device or the library is missing — those probes passed. Seeing a populated software encoder list on that line is also the proof that `hb_load_encoders` really ran the binary and parsed its output.

- [ ] **Step 5: The emitted string survives the watch daemon's word splitting**

`handbrake-watch.sh` reads the file with `read -r -a`, which splits on whitespace. Prove the round trip:

```bash
docker run --rm --entrypoint bash handbrake:dev -c '
  mkdir -p /run/handbrake /tmp/hbstub
  : > /dev/nvidiactl
  libdir=$(dirname "$(find /usr/lib -maxdepth 2 -name libc.so.6 | head -n1)")
  : > "${libdir}/libnvidia-encode.so.1"
  cat > /tmp/hbstub/HandBrakeCLI <<STUB
#!/bin/sh
echo "   -e, --encoder <string>  Select video encoder:"
echo "                               nvenc_h264"
echo "   -q, --quality <float>   Set video quality"
STUB
  chmod 0755 /tmp/hbstub/HandBrakeCLI
  export PATH=/tmp/hbstub:$PATH
  /usr/local/bin/handbrake-gpu.sh nvidia > /run/handbrake/gpu-args 2>/dev/null
  read -r -a HB_GPU_ARGS <<< "$(cat /run/handbrake/gpu-args)"
  echo "count=${#HB_GPU_ARGS[@]}"
  printf "arg: %s\n" "${HB_GPU_ARGS[@]}"
'
```
Expected:
```
count=2
arg: --encoder
arg: nvenc_h264
```

- [ ] **Step 6: The probe runs exactly once per container start**

A regression here is invisible in the output but costs a `HandBrakeCLI --help` per candidate. Count the invocations by making the stub keep a tally:

```bash
docker run --rm --entrypoint sh handbrake:dev -c '
  mkdir -p /run/handbrake /tmp/hbstub
  : > /dev/nvidiactl
  libdir=$(dirname "$(find /usr/lib -maxdepth 2 -name libc.so.6 | head -n1)")
  : > "${libdir}/libnvidia-encode.so.1"
  cat > /tmp/hbstub/HandBrakeCLI <<STUB
#!/bin/sh
echo x >> /tmp/hbstub/calls
echo "   -e, --encoder <string>  Select video encoder:"
echo "                               nvenc_h265"
echo "   -q, --quality <float>   Set video quality"
STUB
  chmod 0755 /tmp/hbstub/HandBrakeCLI
  export PATH=/tmp/hbstub:$PATH
  /usr/local/bin/handbrake-gpu.sh nvidia > /tmp/args 2>/dev/null
  echo "args=[$(cat /tmp/args)]"
  echo "help calls=$(wc -l < /tmp/hbstub/calls)"
'
```
Expected: `args=[--encoder nvenc_h265]` (the second candidate, proving the preference walk continues past a missing first choice) and `help calls=1`. A count of `2` means `hb_load_encoders` was left to be called from inside the `$( … )` subshell and the cache is being discarded.

Re-run the same command with the two `echo "   … nvenc_h265"` lines deleted from the stub, so the encoder list comes back with no NVENC in it. Expected: `args=[]`, still `help calls=1`, and the `WARNING: … produced no encoder list` line **at most once**. A count of `3` there means `HB_ENCODERS_LOADED` was dropped and emptiness is being used as the "not loaded" sentinel again — the degraded path then costs one `--help` per candidate and repeats the warning for each.

---

### Task 7: README — hardware-encoding documentation

**Files:**
- Modify: `d:\nextcloud\it\github\handbrake\README.md` — the comparison table in `## 1. Overview`, the `GPU_VENDOR` row in `## 5. Configuration`, the whole of `## 8. Hardware Encoding`, and three new entries in `## 11. Troubleshooting`.

**Interfaces:**
- Consumes: the values recorded in Tasks 2 and 3.
- Produces: the text `build.yml` mirrors to the Docker Hub description, and the wording Task 12's release notes echo.

- [ ] **Step 1: Add the NVENC row to the comparison table in section 1**

Find this line in `## 1. Overview`:

```markdown
| Dark mode default | ✅ | opt-in via `DARK_MODE=1` |
```

and insert directly **above** it:

```markdown
| NVIDIA NVENC encoding | ✅ | ❌ ([open since 2019](https://github.com/jlesage/docker-handbrake/issues/49)) |
```

- [ ] **Step 2: Update the `GPU_VENDOR` row in section 5**

Replace this row:

```markdown
| `GPU_VENDOR` | `none` | `none` today — see [Hardware Encoding](#8-hardware-encoding) |
```

with:

```markdown
| `GPU_VENDOR` | `none` | `none` or `nvidia`. `nvidia` encodes watch-folder jobs on the GPU — see [Hardware Encoding](#8-hardware-encoding) |
```

- [ ] **Step 3: Replace section 8 in full**

Delete the whole section, from the line `## 8. Hardware Encoding` up to but **not** including `## 9. Migrating from jlesage/handbrake`, and put this in its place (the replacement carries its own heading, so do not keep the old one):

````markdown
## 8. Hardware Encoding

`GPU_VENDOR=nvidia` encodes every watch-folder job on an NVIDIA GPU using
HandBrake's NVENC encoder instead of the CPU. This is the feature the Alpine-based
community image has never been able to ship: NVIDIA's userspace libraries are
glibc binaries that musl cannot load, so its NVENC request has been
[open since 2019](https://github.com/jlesage/docker-handbrake/issues/49). This
image is Ubuntu-based, so the standard NVIDIA container runtime just works.

**Status:** NVENC is developer-verified on real hardware (NVIDIA GeForce RTX 4070
Ti SUPER, Unraid). Intel QSV and AMD VCN are not implemented yet.

### What the host needs

| Requirement | Value |
|---|---|
| Unraid plugin | **Nvidia-Driver** (ich777), from Community Applications |
| Extra Parameters | `--runtime=nvidia` |
| `NVIDIA_VISIBLE_DEVICES` | a GPU UUID from `nvidia-smi -L` on the host, or `all` |
| `NVIDIA_DRIVER_CAPABILITIES` | `compute,video,utility` (or `all`) |
| `GPU_VENDOR` | `nvidia` |

`NVIDIA_DRIVER_CAPABILITIES` matters more than it looks: with the variable unset
the NVIDIA runtime defaults to `utility,compute`, which does **not** include
`video` — and `video` is the capability that injects `libnvidia-encode.so.1`,
the library NVENC actually calls.

Plain Docker:

```sh
docker run -d \
  --name=handbrake \
  --runtime=nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,video,utility \
  -e GPU_VENDOR=nvidia \
  -p 3000:3000 -p 3001:3001 \
  -e PUID=99 -e PGID=100 -e TZ=Europe/Vienna \
  -v /mnt/user/appdata/handbrake:/config \
  -v /mnt/user/media/watch:/watch \
  -v /mnt/user/media/converted:/output \
  --restart unless-stopped \
  ghcr.io/junkerderprovinz/handbrake:latest
```

### What it changes

- **Watch-folder jobs only.** `GPU_VENDOR` adds `--encoder nvenc_h264` to every
  automated conversion. In the GUI you pick the encoder yourself — the NVENC
  entries appear in HandBrake's own encoder list as soon as the GPU is passed in.
- **H.264 by default, on purpose.** The default preset is an x264 preset, so
  `nvenc_h264` keeps the delivered codec identical and only swaps the encoder.
  For HEVC, set
  `AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS=--encoder nvenc_h265` — custom args
  are appended last, so they win.
- **A HandBrake hardware preset is left alone.** If
  `AUTOMATED_CONVERSION_PRESET` already names an NVENC preset, the container does
  not override its encoder.
- **Speed presets.** NVENC does not understand x264 speed names such as
  `veryfast`; HandBrake substitutes its own default. To control the tradeoff
  yourself, add `--encoder-preset <name>` to the custom args — the valid names
  are listed by
  `docker exec handbrake HandBrakeCLI --encoder-preset-list nvenc_h264`.
- **Hardware decoding (NVDEC) stays off.** HandBrake disables hardware decoding
  as soon as any filter runs, and every stock preset crops or scales, so it would
  buy nothing by default. Force it with
  `AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS=--enable-hw-decoding nvdec` if your
  preset has no filters.

### Confirming it is actually on

```sh
docker logs handbrake 2>&1 | grep '\[handbrake-gpu\]'
docker exec handbrake cat /run/handbrake/gpu-args    # empty means software encoding
```

A working GPU logs the encoder, the driver library and the GPU name. Anything
else logs an `ERROR:` block naming the exact fix and falls back to software
encoding — the container keeps converting either way, it just uses the CPU.

The container never guesses an encoder name: at start-up it asks the bundled
`HandBrakeCLI` which encoders it can actually use on your GPU and picks from
that list, so a driver or GPU that cannot do NVENC is detected instead of
assumed.

The measured details for this build, including the NVENC encoders it offers on
a working GPU and the hardware evidence behind the "developer-verified" claim,
are in [`docs/hardware-encoding-nvidia.md`](docs/hardware-encoding-nvidia.md).
````

- [ ] **Step 4: Add three entries to section 11**

Insert before the `**Which image am I actually running?**` entry in `## 11. Troubleshooting`:

````markdown
**`GPU_VENDOR=nvidia` but the log says "no /dev/nvidia* device node".** The
container was not started through the NVIDIA runtime. Add `--runtime=nvidia` to
Extra Parameters and set `NVIDIA_VISIBLE_DEVICES` to a UUID from `nvidia-smi -L`
(Unraid needs the Nvidia-Driver plugin installed first). Conversions keep running
in software until then.

**The log says `libnvidia-encode.so.1` is missing.** The GPU is passed in but the
driver capabilities are too narrow. Set
`NVIDIA_DRIVER_CAPABILITIES=compute,video,utility`; the default of the NVIDIA
runtime leaves `video` out, and `video` is what injects the encoder library.

**The log says HandBrakeCLI "offers none of" the NVENC encoders.** The GPU and
the driver library are both there, but HandBrake itself will not use NVENC on
this machine. HandBrake only lists a hardware encoder it can currently use, so
the usual cause is an NVIDIA driver older than HandBrake's minimum — update the
Nvidia-Driver plugin. The log line `Encoders HandBrakeCLI offers here:` shows
exactly what it did find.

**NVENC is on but the files are still slow.** Check which encoder ran:

```sh
grep -i nvenc /mnt/user/appdata/handbrake/handbrake-watch.log | tail -n 5
```

If the job log names a software encoder, your preset is a hardware preset the
container deliberately did not override, or your custom args set `--encoder`
themselves — custom args are applied last and win.
````

- [ ] **Step 5: Verify the README edits**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
grep -n 'NVIDIA NVENC encoding' README.md
grep -n 'GPU_VENDOR` | `none` | `none` or `nvidia`' README.md
grep -c 'NVIDIA_DRIVER_CAPABILITIES' README.md
grep -n 'This release ships software encoding only' README.md && echo "STALE TEXT LEFT — remove it" || echo "old GPU text gone"
grep -n 'docs/hardware-encoding-nvidia.md' README.md
```
Expected: one hit for the comparison row, one for the config row, `NVIDIA_DRIVER_CAPABILITIES` appearing at least 4 times, `old GPU text gone`, and one link to the new doc.

- [ ] **Step 6: Check the rendered page**

Open the README preview (or `gh repo view --web` after the push in Task 8) and confirm the tables render, the anchor `#8-hardware-encoding` still resolves from both the table of contents and the `GPU_VENDOR` row, and the `docs/hardware-encoding-nvidia.md` link is not broken.

- [ ] **Step 7: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add README.md
git commit -m "docs: document NVIDIA NVENC hardware encoding in the README"
```

---

### Task 8: Push to `main` and publish `:latest` through CI

The real-hardware test needs the image on the Unraid box. Pushing `main` and letting `:latest` rebuild is explicitly allowed; cutting a tag is not (Task 12).

**Files:**
- Modify: none.

**Interfaces:**
- Consumes: the commits from Tasks 2, 3, 4 and 7.
- Produces: a multi-arch `ghcr.io/junkerderprovinz/handbrake:latest` containing the NVENC branch, and its digest for Task 9.

- [ ] **Step 1: Push**

```bash
cd /d/nextcloud/it/github/handbrake
git push origin main
```

- [ ] **Step 2: Watch both workflows**

```bash
cd /d/nextcloud/it/github/handbrake
gh run watch "$(gh run list --workflow=lint.yml  --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
gh run watch "$(gh run list --workflow=build.yml --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
```
Expected: both `success`. The smoke gate still runs with `GPU_VENDOR=none`, so its assertions are unchanged — a failure here means the script change broke the software path, not the GPU path.

- [ ] **Step 3: Record the published digest**

```bash
docker buildx imagetools inspect ghcr.io/junkerderprovinz/handbrake:latest --format '{{println .Manifest.Digest}}{{range .Manifest.Manifests}}{{println .Platform.OS "/" .Platform.Architecture .Digest}}{{end}}'
```
Expected: one manifest-list digest plus `linux/amd64` and `linux/arm64` entries. **Write the manifest-list digest down** — Task 9, Step 3 proves the box is running exactly this image and not a stale cached one.

---

### Task 9: Real-hardware verification on the NVIDIA box

CI has no GPU, so this is where the feature is actually proven. Run every step on jdp's Unraid host over SSH (use the access documented in the vault; never write the real address into a repo file — the plan and every committed file say `<unraid-host>`).

The pass criteria are fixed in advance. All three must hold:

1. HandBrake's own job log names an **NVEnc** encoder for the job.
2. The host's `nvidia-smi` shows the encoder being used during the run — either a `HandBrakeCLI` row in `nvidia-smi pmon` with a non-zero `enc` column, or at least one non-zero sample of `utilization.encoder`.
3. The NVENC run is **measurably faster** than a software run of the same clip under the same CPU limit.

**Files:**
- Modify: none. Verification only; the evidence is written up in Task 10.

**Interfaces:**
- Consumes: `ghcr.io/junkerderprovinz/handbrake:latest` (Task 8) and the requirements recorded in Task 3.
- Produces: the evidence block Task 10 pastes into the doc and the "developer-verified" claim Task 7's README already makes.

- [ ] **Step 1: Confirm the host side is actually ready**

On the Unraid host:
```bash
nvidia-smi -L
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv
docker info --format '{{json .Runtimes}}'
```
Expected: the GPU listed with a `GPU-…` UUID, a driver version, and a `nvidia` entry in the runtimes map. If `nvidia` is missing from the runtimes, the Nvidia-Driver plugin is not installed or the docker service has not been restarted since — stop and fix that first, everything below depends on it.

Copy the GPU UUID into a shell variable for the rest of this task:
```bash
GPU_UUID=$(nvidia-smi --query-gpu=uuid --format=csv,noheader | head -n1); echo "${GPU_UUID}"
```

- [ ] **Step 2: Compare the driver against HandBrake's requirement**

```bash
nvidia-smi --query-gpu=driver_version --format=csv,noheader
```
Expected: a version greater than or equal to the minimum recorded in Task 3, Step 2. If it is older, update the Nvidia-Driver plugin before continuing — an older driver is a known-bad configuration, not something to work around in the container.

- [ ] **Step 3: Pull the exact image CI built**

```bash
docker pull ghcr.io/junkerderprovinz/handbrake:latest
docker image inspect ghcr.io/junkerderprovinz/handbrake:latest --format '{{index .RepoDigests 0}}'
```
Expected: the digest matches the manifest-list digest recorded in Task 8, Step 3. A mismatch means the host pulled a stale tag — re-pull, and if it still differs, pull by digest (`docker pull ghcr.io/junkerderprovinz/handbrake@sha256:<digest>`) rather than debugging the container.

- [ ] **Step 4: Prepare a scratch area and a real test clip**

The clip is generated into `src/`, **not** into `watch/`: the watch daemon starts converting anything already lying in the watch folder the moment the container boots, which would start the job before the sampler in Step 7 is running.

```bash
mkdir -p /mnt/user/appdata/hb-nvenc-test/{config,watch,output,src}
docker run --rm -v /mnt/user/appdata/hb-nvenc-test/src:/w linuxserver/ffmpeg:latest \
  -v error -y -f lavfi -i testsrc=size=1920x1080:rate=30:duration=180 \
  -c:v libx264 -preset ultrafast -pix_fmt yuv420p /w/nvenc-probe.mkv
chown -R nobody:users /mnt/user/appdata/hb-nvenc-test
ls -lh /mnt/user/appdata/hb-nvenc-test/src/
```
Expected: a multi-hundred-megabyte `nvenc-probe.mkv` owned by `nobody:users`, and an empty `watch/`. 180 s of 1080p30 makes the encode last long enough to be sampled by `nvidia-smi`, and long enough for the software-versus-NVENC difference to be unambiguous.

- [ ] **Step 5: Start the container with the GPU**

```bash
docker rm -f hb-nvenc-test 2>/dev/null || true
docker run -d --name hb-nvenc-test \
  --runtime=nvidia \
  -e NVIDIA_VISIBLE_DEVICES="${GPU_UUID}" \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,video,utility \
  -e GPU_VENDOR=nvidia \
  -e PUID=99 -e PGID=100 -e TZ=Europe/Vienna \
  -p 3080:3000 -p 3081:3001 \
  -v /mnt/user/appdata/hb-nvenc-test/config:/config \
  -v /mnt/user/appdata/hb-nvenc-test/watch:/watch \
  -v /mnt/user/appdata/hb-nvenc-test/output:/output \
  --cpus=4 --memory=4g \
  ghcr.io/junkerderprovinz/handbrake:latest
```
The `--cpus=4 --memory=4g` limit is mandatory for test containers here, and it also makes Step 10's software comparison a fair, repeatable measurement.

- [ ] **Step 6: The container reports a usable GPU**

```bash
sleep 40
docker logs hb-nvenc-test 2>&1 | grep -E '\[handbrake-gpu\]|\[init-handbrake\] gpu-args'
docker exec hb-nvenc-test sh -c 'echo "gpu-args=[$(cat /run/handbrake/gpu-args)]"'
docker exec hb-nvenc-test sh -c 'ls -l /dev/nvidia* ; ls -l /usr/lib/*/libnvidia-encode.so.1'
docker exec hb-nvenc-test nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
```
Expected: `[handbrake-gpu] GPU acceleration: NVIDIA NVENC — NVIDIA GeForce RTX 4070 Ti SUPER, <driver>`, an `encoder library:` line, `HandBrakeCLI arguments: --encoder nvenc_h264`, `[init-handbrake] gpu-args: '--encoder nvenc_h264' (vendor nvidia)`, `gpu-args=[--encoder nvenc_h264]`, the device nodes, the library, and the GPU name from inside the container.

This step also empirically confirms that `compute,video,utility` is sufficient: if `libnvidia-encode.so.1` is listed here, the `video` capability did its job.

- [ ] **Step 6a: Record the live encoder list — the authoritative one**

This is the measurement Task 2 could not take, and the direct proof that the live probe was the right mechanism. It is the same extraction `hb_load_encoders()` performs:

```bash
docker exec hb-nvenc-test sh -c \
  "HandBrakeCLI --help 2>/dev/null | awk '/^[[:space:]]*-e, --encoder[[:space:]]/{f=1;next} f&&/^[[:space:]]*-/{f=0} f' \
     | sed 's/^[[:space:]]*//;s/[[:space:]]*\$//' | grep -v '^\$'"
docker exec hb-nvenc-test sh -c \
  'sed -n "/-e, --encoder/,/^[[:space:]]*-[a-zA-Z-]/p" /usr/local/share/handbrake-cli-help.txt \
     | tr " ,\t" "\n\n\n" | grep -E "^nvenc" | sort -u; echo "[dump exit $?]"'
```
Expected, and this contrast is the whole point of the fix: the **live** list now contains `nvenc_h264` and `nvenc_h265` (and possibly `nvenc_av1`), while the **build-time dump inside the very same container** still contains none of them. Record both outputs — Task 10 pastes them into section 7 as the evidence that a dump-based lookup would have failed on this exact working GPU.

- [ ] **Step 6b: Record the NVENC encoder presets, deferred from Task 2, Step 2**

The encoder now resolves by name, so this command finally works:

```bash
docker exec hb-nvenc-test HandBrakeCLI --encoder-preset-list nvenc_h264 2>&1
```
Expected: the preset names HandBrake accepts for `nvenc_h264`. Record them; Task 10 backfills section 2 of `docs/hardware-encoding-nvidia.md`, and Task 7's README already tells users to run this command themselves.

**If the GPU is not detected here, do not start guessing.** One failed round is the limit: report exactly what the four commands above printed and ask jdp to run `nvidia-smi` plus `docker inspect hb-nvenc-test --format '{{json .HostConfig.Runtime}} {{json .Config.Env}}'` on the box.

- [ ] **Step 7: Start the samplers, then feed the watch folder**

Start both samplers first; `timeout` bounds them, so nothing has to be killed later. Do **not** use `nvidia-smi -c` here: on the top-level command `-c` is `--compute-mode` and would try to change the GPU's state, not the sample count.

```bash
timeout 150 nvidia-smi --query-gpu=utilization.gpu,utilization.encoder,utilization.decoder \
  --format=csv -l 2 > /tmp/nvenc-util.csv 2>&1 &
timeout 150 nvidia-smi pmon -s um -d 2 > /tmp/nvenc-pmon.txt 2>&1 &
```

Then drop the clip in. It is copied to a dot-prefixed name first and renamed, because the daemon skips dotfiles — that way it never sees a half-copied source:

```bash
D=/mnt/user/appdata/hb-nvenc-test
cp "$D/src/nvenc-probe.mkv" "$D/watch/.staging.mkv"
mv "$D/watch/.staging.mkv" "$D/watch/nvenc-run.mkv"
chown nobody:users "$D/watch/nvenc-run.mkv"
for i in $(seq 1 600); do
  if [ -s "$D/output/nvenc-run.mp4" ]; then echo "output appeared after ${i}s"; break; fi
  sleep 1
done
docker logs hb-nvenc-test 2>&1 | grep '\[handbrake-watch\]' | tail -n 5
```
Expected: `output appeared after <n>s`, and a `[handbrake-watch] done 'nvenc-run.mkv' in <N>s -> /output/nvenc-run.mp4` line. **Record that `<N>`** — it is the NVENC time for criterion 3.

- [ ] **Step 8: Criterion 1 — HandBrake itself says it used NVEnc**

```bash
grep -i -nE 'nvenc|nvdec|encoder:' /mnt/user/appdata/hb-nvenc-test/config/handbrake-watch.log | tail -n 20
```
Expected: the job summary names an NVEnc encoder (HandBrake writes the human-readable encoder name into the job log, e.g. `+ encoder: H.264 (NVEnc)`), and the invocation line at the top of the job shows `--encoder nvenc_h264`. Copy both lines out for Task 10.

If instead the log shows an NVENC initialisation error, that is a real failure — capture the surrounding 30 lines and report it rather than falling back to a claim of success.

- [ ] **Step 9: Criterion 2 — the GPU encoder was actually busy**

Both samplers stopped by themselves after 150 s:

```bash
sort -u /tmp/nvenc-util.csv | head -n 20
grep -iE 'handbrake' /tmp/nvenc-pmon.txt | head -n 20
```
Expected: at least one row in `nvenc-util.csv` with a non-zero `utilization.encoder`, and/or `pmon` rows naming `HandBrakeCLI` with a non-zero `enc` column. One of the two is enough; encoder-utilisation sampling can miss a short session, whereas `pmon` names the process directly. If **both** are empty while Step 8 passed, do not declare success: re-run Step 7 with the samplers started first and `timeout 300`.

- [ ] **Step 10: Criterion 3 — the negative control**

Same clip, same CPU limit, software encoding. The NVENC output stays where it is — Step 11 still has to decode it — and the already-converted `nvenc-run.mkv` is not picked up again because its key is in `done.list`:

```bash
D=/mnt/user/appdata/hb-nvenc-test
docker rm -f hb-nvenc-test
docker rm -f hb-soft-test 2>/dev/null || true
docker run -d --name hb-soft-test \
  -e GPU_VENDOR=none \
  -e PUID=99 -e PGID=100 -e TZ=Europe/Vienna \
  -v "$D/config:/config" \
  -v "$D/watch:/watch" \
  -v "$D/output:/output" \
  --cpus=4 --memory=4g \
  ghcr.io/junkerderprovinz/handbrake:latest
sleep 40
cp "$D/src/nvenc-probe.mkv" "$D/watch/.staging.mkv"
mv "$D/watch/.staging.mkv" "$D/watch/soft-run.mkv"
chown nobody:users "$D/watch/soft-run.mkv"
for i in $(seq 1 1800); do
  if [ -s "$D/output/soft-run.mp4" ]; then echo "software output after ${i}s"; break; fi
  sleep 1
done
docker logs hb-soft-test 2>&1 | grep "done 'soft-run.mkv'"
ls -lh "$D/output/"
```
Expected: a `done 'soft-run.mkv' in <M>s` line with `<M>` clearly larger than the `<N>` from Step 7, and both `nvenc-run.mp4` and `soft-run.mp4` present. Record both numbers and both file sizes.

- [ ] **Step 11: The output is a real, playable file**

```bash
docker run --rm -v /mnt/user/appdata/hb-nvenc-test/output:/o linuxserver/ffmpeg:latest \
  -v error -i /o/nvenc-run.mp4 -f null - && echo "nvenc output decodes cleanly"
docker run --rm -v /mnt/user/appdata/hb-nvenc-test/output:/o --entrypoint ffprobe linuxserver/ffmpeg:latest \
  -v error -show_entries stream=codec_name,width,height,nb_frames -of default=noprint_wrappers=1 /o/nvenc-run.mp4
```
Expected: `nvenc output decodes cleanly` with no decoder errors, `codec_name=h264`, `1920x1080`, and a frame count matching a 180 s 30 fps source (about 5400). A file that exists but does not decode is a failure, not a pass.

- [ ] **Step 12: Clean up the box**

```bash
docker rm -f hb-soft-test 2>/dev/null || true
docker rm -f hb-nvenc-test 2>/dev/null || true
rm -rf /mnt/user/appdata/hb-nvenc-test
rm -f /tmp/nvenc-util.csv /tmp/nvenc-pmon.txt
docker ps -a --filter 'name=hb-' --format '{{.Names}}'
```
Expected: no `hb-` containers left and the scratch appdata folder gone. Keep the copied log excerpts and numbers — Task 10 needs them.

---

### Task 10: Record the hardware evidence

**Files:**
- Modify: `d:\nextcloud\it\github\handbrake\docs\hardware-encoding-nvidia.md` (append section 7)

**Interfaces:**
- Consumes: the output collected in Task 9.
- Produces: the evidence behind the README's "developer-verified" claim, and the baseline a future regression is compared against.

- [ ] **Step 1: Append section 7 with the real numbers**

Append to `d:\nextcloud\it\github\handbrake\docs\hardware-encoding-nvidia.md`, replacing every `<paste …>`:

````markdown

## 7. Hardware verification (developer-verified)

| | |
|---|---|
| Date | `<paste: date -I>` |
| Image | `ghcr.io/junkerderprovinz/handbrake@<paste the manifest digest from Task 8>` |
| Host | Unraid, Nvidia-Driver plugin |
| GPU | `<paste the name from nvidia-smi>` |
| Driver | `<paste the driver version>` |
| Container | `--runtime=nvidia`, `NVIDIA_DRIVER_CAPABILITIES=compute,video,utility`, `GPU_VENDOR=nvidia`, `--cpus=4 --memory=4g` |
| Source clip | 1920x1080, 30 fps, 180 s, H.264 |

### The container detected the GPU

```text
<paste the [handbrake-gpu] block from Task 9, Step 6>
```

### Why the check is a live probe, measured on this machine

Same container, same binary, same moment — the live encoder list and the
build-time dump disagree, because `libhb` filters the live list through
`hb_nvenc_h264_available()` and the dump was written on a builder with no GPU:

```text
live HandBrakeCLI --help:
<paste the live encoder list from Task 9, Step 6a>

/usr/local/share/handbrake-cli-help.txt (same container):
<paste the dump output from Task 9, Step 6a — expected to be empty of nvenc_*>
```

A dump-based lookup would have reported "no NVENC in this build" on this exact
working GPU. That is why `handbrake-gpu.sh` asks the running binary.

### HandBrake used the NVENC encoder

```text
<paste the encoder lines from handbrake-watch.log, Task 9, Step 8>
```

### The GPU encoder was busy during the run

```text
<paste the non-zero utilization.encoder rows and/or the pmon rows from Task 9, Step 9>
```

### NVENC versus software, same clip, same CPU limit

| Run | `GPU_VENDOR` | Encoder | Wall clock | Output size |
|---|---|---|---|---|
| Hardware | `nvidia` | `<paste the encoder>` | `<paste N>` s | `<paste size>` |
| Software | `none` | x264 | `<paste M>` s | `<paste size>` |

The NVENC output decodes without errors (`ffmpeg -i … -f null -`) and reports
`<paste the ffprobe line>`.
````

- [ ] **Step 2: Backfill sections 1 and 2 with what only the GPU box could measure**

Two placeholders were deliberately left open earlier because a GPU-less machine cannot fill them. Close them now, from the output recorded in Task 9:

- **Section 1** — add the live encoder list from Task 9, Step 6a as the authoritative `nvenc_*` identifier list for this build. The GPU-less measurements stay where they are; they are the evidence for the mechanism, not a substitute for this.
- **Section 2** — replace the `--encoder-preset` placeholder with the output of Task 9, Step 6b. If Task 2, Step 2 recorded an error instead of preset names, remove that error text now rather than leaving both.

- [ ] **Step 3: Verify**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
grep -n '<paste' docs/hardware-encoding-nvidia.md && echo "PLACEHOLDERS LEFT — fix them" || echo "no placeholders"
grep -nE '192\.168\.|10\.[0-9]+\.[0-9]+\.[0-9]+|GPU-[0-9a-f]{8}' docs/hardware-encoding-nvidia.md \
  && echo "HOST DATA LEAKED — replace with <unraid-host> / a redacted UUID" || echo "no host data"
```
Expected: `no placeholders` and `no host data`. The GPU model and driver version are fine to publish; the host address and the GPU UUID are not.

- [ ] **Step 4: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add docs/hardware-encoding-nvidia.md
git commit -m "docs: record the NVENC hardware verification results"
```

---

### Task 11: Unraid CA template handoff

The Community Applications template is **not** in this repo. Plan 1 (Task 16, Step 12) creates the HandBrake entry in the central feed repo `junkerderprovinz/unraid-apps` at `handbrake/handbrake.xml`. This task does not edit that repo — it writes down exactly what has to be added there, so the handoff cannot get lost between plans.

**Files:**
- Modify: `d:\nextcloud\it\github\handbrake\docs\hardware-encoding-nvidia.md` (append section 8)

**Interfaces:**
- Consumes: the template conventions of the existing entries (`unraid-apps/jdownloader/jdownloader.xml`: a pipe-separated `Default` renders as a dropdown, the element body holds the selected value).
- Produces: a paste-ready block for the feed repo, and the follow-up item Task 13 tracks.

- [ ] **Step 1: Append section 8**

Append to `d:\nextcloud\it\github\handbrake\docs\hardware-encoding-nvidia.md`:

````markdown

## 8. Unraid CA template handoff

The canonical template lives in the feed repo, **not here**:
`junkerderprovinz/unraid-apps` → `handbrake/handbrake.xml`
(<https://github.com/junkerderprovinz/unraid-apps>). Three changes are needed
there for GPU support, following the same conventions as the existing entries
(pipe-separated `Default` renders as a dropdown; the element body is the value
that is actually applied).

**1. `ExtraParams` — the NVIDIA runtime.** Users without a GPU must not be forced
to edit this, so `--runtime=nvidia` is documented in the GPU field's description
rather than baked in:

```xml
<ExtraParams>--restart=unless-stopped</ExtraParams>
```

**2. A GPU vendor dropdown** in the UI-preferences block:

```xml
  <Config Name="GPU Acceleration (GPU_VENDOR)" Target="GPU_VENDOR"
          Default="none|nvidia" Mode=""
          Description="none (default) = CPU encoding. nvidia = encode watch-folder jobs on an NVIDIA GPU with NVENC. For nvidia you also need: the Nvidia-Driver plugin, '--runtime=nvidia' in Extra Parameters, the Nvidia GPU UUID below, and NVIDIA_DRIVER_CAPABILITIES=compute,video,utility. Without those the container logs a clear error and keeps encoding on the CPU."
          Type="Variable" Display="always" Required="false" Mask="false">none</Config>
```

**3. The two NVIDIA runtime variables**, hidden behind the advanced view so a
CPU-only user never sees them:

```xml
  <Config Name="Nvidia GPU UUID (NVIDIA_VISIBLE_DEVICES)" Target="NVIDIA_VISIBLE_DEVICES"
          Default="" Mode=""
          Description="Only needed when GPU Acceleration is set to nvidia. Paste the GPU UUID from the Nvidia-Driver plugin page (starts with GPU-), or use 'all'. Also add '--runtime=nvidia' to Extra Parameters."
          Type="Variable" Display="advanced" Required="false" Mask="false"/>

  <Config Name="Nvidia Driver Capabilities (NVIDIA_DRIVER_CAPABILITIES)" Target="NVIDIA_DRIVER_CAPABILITIES"
          Default="compute,video,utility|all" Mode=""
          Description="Only needed when GPU Acceleration is set to nvidia. 'video' is the capability that injects the NVENC encoder library; the NVIDIA runtime leaves it out by default, which is why this must be set explicitly."
          Type="Variable" Display="advanced" Required="false" Mask="false">compute,video,utility</Config>
```

**4. Overview text** — add one line to the `<Overview>` block:
`• GPU encoding: set GPU Acceleration to nvidia for NVENC hardware transcoding (needs the Nvidia-Driver plugin and --runtime=nvidia).`

After the feed repo is updated, CA needs a re-scan before the new fields show up
in the template editor.
````

- [ ] **Step 2: Verify the XML fragments parse**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
python - <<'PY'
import re, xml.etree.ElementTree as ET
doc = open('docs/hardware-encoding-nvidia.md', encoding='utf-8').read()
blocks = re.findall(r'```xml\n(.*?)```', doc, re.S)
assert blocks, 'no xml blocks found'
for i, b in enumerate(blocks, 1):
    ET.fromstring('<Container>' + b + '</Container>')
    print(f'xml block {i} OK')
PY
```
Expected: one `xml block N OK` line per block (4 blocks), no traceback.

- [ ] **Step 3: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add docs/hardware-encoding-nvidia.md
git commit -m "docs: add the Unraid CA template handoff for the GPU fields"
```

---

### Task 12: Release notes v1.1.0 and the gated tag

**Files:**
- Create: `d:\nextcloud\it\github\handbrake\.github\release-notes\v1.1.0.md`

**Interfaces:**
- Consumes: everything above; `release.yml` (Plan 1, Task 13) turns this file into the GitHub release body.
- Produces: `ghcr.io/junkerderprovinz/handbrake:1.1.0` / `:1.1` / `:1` / `:latest` and the GitHub release `v1.1.0` — **after approval only**.

- [ ] **Step 1: Scaffold and write the notes**

```bash
cd /d/nextcloud/it/github/handbrake
just notes 1.1.0
```

Then replace the scaffolded content of `d:\nextcloud\it\github\handbrake\.github\release-notes\v1.1.0.md` with:

```markdown
NVIDIA GPU encoding. Set one variable and every watch-folder job is transcoded by the GPU instead of the CPU — the feature the Alpine-based community image has never been able to ship.

## ✨ Added

- **NVIDIA NVENC hardware encoding.** `GPU_VENDOR=nvidia` runs every automated watch-folder conversion on an NVIDIA GPU with HandBrake's NVENC encoder. The container needs the NVIDIA runtime (`--runtime=nvidia`), a GPU in `NVIDIA_VISIBLE_DEVICES` and `NVIDIA_DRIVER_CAPABILITIES=compute,video,utility` — the README's Hardware Encoding section has the full Unraid recipe. This closes the gap the Alpine-based `jlesage/handbrake` cannot close at all, because NVIDIA's userspace libraries are glibc binaries that musl cannot load ([jlesage/docker-handbrake#49](https://github.com/jlesage/docker-handbrake/issues/49), open since 2019).
- **H.264 by default, HEVC on request.** The default preset is an x264 preset, so the GPU path keeps the delivered codec identical and only swaps the encoder implementation. `AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS=--encoder nvenc_h265` switches to HEVC, and a HandBrake hardware preset is never overridden.
- **A verification record.** `docs/hardware-encoding-nvidia.md` documents which NVENC encoders this build actually contains, what the host has to provide, and the measured hardware run behind the "developer-verified" claim.

## ⚡ Improved

- **The GPU setting now tells the truth.** `GPU_VENDOR=nvidia` on a container that has no usable GPU prints exactly which piece is missing — the NVIDIA runtime, the `video` driver capability, or an NVENC encoder in the build — names the fix, and keeps converting in software instead of failing every file. Check it any time with `docker exec handbrake cat /run/handbrake/gpu-args`: empty means software.
```

- [ ] **Step 2: Sanity-check against the house rules**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
grep -nE '^#[^#]' .github/release-notes/v1.1.0.md && echo "H1 FOUND — remove it" || echo "no H1 heading (correct)"
grep -nE '^## ' .github/release-notes/v1.1.0.md
grep -nE 'v?1\.1\.0' .github/release-notes/v1.1.0.md && echo "VERSION IN BODY — remove it" || echo "no version heading in the body (correct)"
```
Expected: `no H1 heading (correct)`, exactly the two category headings `## ✨ Added` and `## ⚡ Improved`, and `no version heading in the body (correct)`.

- [ ] **Step 3: Commit and push**

```bash
cd /d/nextcloud/it/github/handbrake
git add .github/release-notes/v1.1.0.md
git commit -m "docs: add the v1.1.0 release notes"
git push origin main
gh run watch "$(gh run list --workflow=build.yml --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
```
Expected: the build goes green again.

- [ ] **Step 4: STOP — ask for approval before tagging**

Do not run Step 5 until jdp has explicitly approved cutting `v1.1.0`. Report that NVENC is verified on the real GPU (with the numbers from Task 9), that both workflows are green, and ask.

- [ ] **Step 5: Tag the release (only after approval)**

```bash
cd /d/nextcloud/it/github/handbrake
git fetch origin && git pull --rebase origin main
git tag v1.1.0
git push origin v1.1.0
gh run watch "$(gh run list --workflow=release.yml --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
gh release view v1.1.0
```
Expected: the release title is exactly `v1.1.0`, the body is the notes file, and the tag build publishes `:1.1.0`, `:1.1`, `:1` and `:latest`.

- [ ] **Step 6: Verify the published manifest**

```bash
docker buildx imagetools inspect ghcr.io/junkerderprovinz/handbrake:1.1.0
```
Expected: a manifest list with `linux/amd64` and `linux/arm64`.

---

### Task 13: Follow-ups outside this repo

House requirements, not optional. None of them touch this repository.

**Files:**
- Modify: none in this repo.

- [ ] **Step 1: Update the CA template in the feed repo**

Apply the four changes from `docs/hardware-encoding-nvidia.md` section 8 to
`junkerderprovinz/unraid-apps` → `handbrake/handbrake.xml`, validate with
`xmllint --noout handbrake/handbrake.xml`, commit and push there, then trigger a
CA re-scan and confirm the new GPU fields appear in the Unraid template editor.

- [ ] **Step 2: Hand jdp the importable template**

Per house convention the template deliverable is handed over as the XML file
itself, named `my-HandBrake.xml` (already git-ignored in this repo), not as an
inline snippet in chat.

- [ ] **Step 3: Mirror the change into the Obsidian vault**

Add a dated changelog entry to the HandBrake repo note (PascalCase, under
`02 Projekte`) covering the NVENC feature, the verification numbers from Task 9
and the v1.1.0 release, and link the repo, the release and
`docs/hardware-encoding-nvidia.md`.

- [ ] **Step 4: Refresh the support thread and the profile README if they mention GPU support**

The Unraid support thread and the profile README both describe the container's
feature set; NVENC changes that description. Update whichever already exists.

---

## Self-review checklist

Run this before declaring the plan finished.

- [ ] No `TBD`, `TODO`, `similar to Task N`, or "add appropriate error handling" anywhere in this document. Every unknown has an explicit confirming command and a named machine to run it on: the `--enable-hw-decoding` spelling, the driver-capability values, the minimum driver version and the hardware presets in Tasks 2 and 3 (GPU-less is fine); the `nvenc_*` identifiers and the `--encoder-preset` names in Task 9, Steps 6a and 6b (real GPU required, because `libhb` will not admit to them anywhere else). Task 10, Step 2 backfills the two placeholders that Task 2 deliberately leaves open.
- [ ] **The encoder lookup is a live probe, not a build-time dump lookup**, and every place that describes it agrees: the Architecture paragraph, the Global Constraints, "Why the encoder check asks the live binary", Task 2 Step 1, Task 3's section 6, the script's header comment, `hb_load_encoders`/`hb_has_encoder`/`hb_pick_encoder`, the `nvidia)` branch, Task 6, Task 9 Step 6a and this handoff. The name `hb_help_lists_encoder` appears nowhere in the script in Task 4; it survives only as a historical reference in this checklist and in the Plan 3 handoff, where naming it is the point.
- [ ] **`hb_help_lists_nvdec()` still reads `HB_CLI_HELP`, and that is deliberate, not an oversight.** The `--enable-hw-decoding` help text is a static literal guarded by a compile-time `#if`; only the encoder list is hardware-filtered. The exception is documented in the function's own comment, in Task 2 Step 3 and in the research section.
- [ ] Names match Plan 1 exactly, re-checked against `docs/superpowers/plans/2026-08-12-handbrake-core-port.md`: `rootfs/usr/local/bin/handbrake-gpu.sh`, `gpu_args_for_vendor()`, `GPU_VENDOR`, `/run/handbrake/gpu-args`, `/run/handbrake/gpu-vendor`, `init-handbrake`, `handbrake-watch.sh`, `HB_GPU_ARGS`, `AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS`, `/usr/local/share/handbrake-cli-help.txt` (now referenced only by `hb_help_lists_nvdec`), the `[handbrake-gpu]` log prefix. The live-probe helper names are Plan 3's, on purpose: `hb_load_encoders`, `hb_has_encoder`, `hb_pick_encoder`.
- [ ] Exactly four files are touched: `rootfs/usr/local/bin/handbrake-gpu.sh`, `README.md`, `docs/hardware-encoding-nvidia.md`, `.github/release-notes/v1.1.0.md`. No Dockerfile change (none is needed — the NVIDIA runtime injects the libraries), no s6 service change, no workflow change.
- [ ] The fail-loud requirement is covered three ways: a distinct error block per failure cause in the script (Task 4), a scripted assertion of the exact text (Task 5, Step 3), and a full-container assertion that conversions keep working (Task 5, Steps 4 and 5). All three failure causes are exercised on a GPU-less machine — no device (Task 5, Step 3), no library (Task 6, Step 3) and no NVENC encoder offered (Task 6, Step 4) — and each produces its own block naming its own fix.
- [ ] The real-hardware verification is concrete: exact `docker run` with `--runtime=nvidia`, the GPU UUID from `nvidia-smi -L`, `NVIDIA_DRIVER_CAPABILITIES=compute,video,utility`, a generated 180 s 1080p clip, three fixed pass criteria (HandBrake's own log, `nvidia-smi` encoder activity, a timed software negative control under the same CPU limit), a decode check on the output, and a cleanup step. Test containers carry `--cpus`/`--memory`.
- [ ] The Unraid template is handled as a handoff to `junkerderprovinz/unraid-apps` (Task 11 writes the exact XML, Task 13 applies it there); this plan never edits the feed repo, and Plan 1 created no local template stub to extend.
- [ ] Versioning follows Plan 1: `v1.0.0` was the first release, this is the minor bump `v1.1.0`, notes at `.github/release-notes/v1.1.0.md`, no version heading in the body, tagging gated on explicit approval.
- [ ] No real IPs, hostnames or GPU UUIDs land in a committed file (Task 10, Step 2 greps for them).
- [ ] Out of scope and deliberately absent: Intel QSV and AMD VCN (Plan 3), watch-daemon hooks and staging directories (Plan 4), any Dockerfile package layer, any change to the CI smoke gate, `--encoder-preset` injection, and NVDEC-on-by-default.

---

## Handoff: what Plan 3 (Intel QSV / AMD VCN) inherits

- The same single seam: add a branch to `gpu_args_for_vendor()` in `rootfs/usr/local/bin/handbrake-gpu.sh`. Do not add a second script and do not touch `handbrake-watch.sh`.
- Reusable helpers this plan added to that file: `log()`, the live-probe trio `hb_load_encoders` / `hb_has_encoder <id>` / `hb_pick_encoder <id>…` (one `HandBrakeCLI --help` call per container start, cached in `HB_ENCODERS`), `hb_help_lists_nvdec()` (the one legitimate reader of the build-time dump), and `nvidia_lib_path <soname>` (rename or generalise for `/dev/dri` and the VAAPI libraries rather than duplicating the loop), plus the three-question probe order that produces one error block per cause.
- **The helper names are already Plan 3's**, so the two plans converge on one probe instead of two. When Plan 3's Task 6 rewrites this file, its own `hb_load_encoders` / `hb_has_encoder` / `hb_pick_encoder` supersede these — do not paste a second copy, and expect its `sed s/hb_help_lists_encoder/hb_has_encoder/` to find nothing, because there is nothing left to fix. Plan 3's version additionally runs the probe as `abc` via `s6-setuidgid` and pairs that with an `init-video` ordering edge; take that version wholesale.
- The house pattern this plan establishes for a GPU branch, which Plan 3 should mirror: probe the device → probe the runtime library → **ask the running `HandBrakeCLI` which encoders it offers here** → emit `--encoder <id>` → log what is in effect. Every failure returns 0, emits no arguments and prints an `ERROR:` block naming the exact fix.
- **Never resolve a hardware encoder id from `/usr/local/share/handbrake-cli-help.txt`.** `libhb` gates the encoder list on a live availability probe (`hb_video_encoder_is_enabled()` → `hb_nvenc_h264_available()` / `hb_qsv_video_encoder_is_available()` / `hb_vce_h264_available()`), and that dump is recorded during `docker build` on a GPU-less machine, so it never contains one. The dump remains correct for statically printed help text only. Plan 3 records the same finding as finding 1 of its research section; the two plans agree, and neither should be "simplified" back onto the dump.
- The `*nvenc*` guard on `AUTOMATED_CONVERSION_PRESET` has QSV and VCN equivalents (HandBrake ships `QSV` presets); reuse the same `case` shape with the right substring.
- Intel and AMD have no local hardware to verify against. Plan 3 cannot copy Task 9; it must ship those vendors as "implemented per HandBrake's documentation, not hardware-verified by us" in the README, exactly as the design spec requires, and keep the developer-verified claim reserved for NVENC.
- Per Plan 1's research, Ubuntu builds `handbrake-cli` with `--enable-qsv` on amd64 but does not pass `--enable-vce`. Confirm both against `docs/handbrake-capabilities.md` and by grepping the binary for the id strings (the technique in Task 2, Step 1c) before designing the AMD half. Note that `hb_has_encoder` **cannot** answer this question on a GPU-less machine: a missing id there means "not compiled in **or** no usable hardware", and the two are indistinguishable without the hardware. A vendor whose encoders are genuinely not in the build can only ever hit the third error block.
