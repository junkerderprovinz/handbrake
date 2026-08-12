# HandBrake — Intel QSV + AMD VCN GPU Support Implementation Plan (Plan 3 of 4)

> **For agentic workers:** Requires Plan 1 (core port) already implemented and merged. Steps use checkbox (`- [ ]`) syntax for tracking. Execute task-by-task, committing after each passing task. NOTE: this plan covers hardware the implementer cannot test directly — read the "Verification Limits" note at the top before starting.

**Goal:** Make `GPU_VENDOR=intel` deliver real Intel Quick Sync hardware encoding in the watch-folder converter, and make `GPU_VENDOR=amd` an honest, loudly-explained code path (plus an optional, self-built VCE image variant), without ever silently pretending that hardware encoding is happening when it is not.

**Architecture:** Both vendors reuse the seam Plan 1 built: `init-handbrake` calls `/usr/local/bin/handbrake-gpu.sh <vendor>`, whose stdout becomes `/run/handbrake/gpu-args`, which `handbrake-watch.sh` splices into every `HandBrakeCLI` call. This plan extends `gpu_args_for_vendor()` with an `intel` and an `amd` branch, adds the Intel oneVPL/iHD runtime to the amd64 image, and ships an optional `Dockerfile.vce` that rebuilds `HandBrakeCLI` with `--enable-vce` for the small set of users who can supply AMD's proprietary AMF runtime. Vendor detection is done by asking `HandBrakeCLI --help` at container start, as the user that will run the conversions, because libhb only lists a hardware encoder when it is both compiled in and usable on the machine right now.

**Tech Stack:** POSIX/bash shell, Docker (BuildKit, multi-stage), Ubuntu 26.04 packages (`libmfx-gen1.2`, `intel-media-va-driver-non-free`, `vainfo`, `libvpl-tools`), Intel oneVPL, VA-API (`iHD`), AMD AMF 1.5.0 headers, HandBrake 1.11 (`HandBrakeCLI`), GitHub Actions.

## Verification Limits

**There is no Intel GPU and no AMD GPU available to the implementer or the maintainer.** The CI runners have no GPU either. This is a stated, deliberate limitation of this release, not something to paper over.

What that means concretely, task by task:

| What | Can it be verified here? | If not, what is verified instead |
|---|---|---|
| The QSV runtime packages install and land in the image | **Yes** | — |
| `handbrake-gpu.sh` selects the right encoder id | **No** (needs an Intel GPU) | The identifier is never typed into an argument: it is looked up in the live `HandBrakeCLI --help` output. What is verified is the *lookup and fallback logic*, exercised with a GPU-less container. |
| QSV actually encodes on the GPU | **No** | HandBrake's own availability probe (`hb_qsv_video_encoder_is_available()`) is the gate. If it says no, we fall back. Community reports close the loop. |
| The AMD source build produces a VCE-capable binary | **Partly** | The build itself is verified, and the AMF code path is proven present in the binary with a wide-string check that needs no AMD hardware. Whether it *encodes* is not verifiable here. |
| `GPU_VENDOR=intel`/`amd` on a machine without that GPU falls back cleanly and says why | **Yes** | This is fully tested, locally and in CI. It is the single most important behaviour in this plan, because it is the one every user without the right hardware will hit. |

Nothing in this plan may claim hardware verification in the README, the release notes, or a commit message. The wording that ships is: implemented per the vendors' and HandBrake's own documentation, not hardware-verified by the maintainer.

## Global Constraints

Plan 1's Global Constraints apply unchanged and are not repeated here. The ones that bite hardest in this plan:

- **Everything inside the repo is English.** No AI attribution anywhere. No em dashes in GitHub issue/PR/forum prose (the issue form added in Task 14 is issue prose: no em dashes there; README and release notes may use them).
- **LF line endings** for everything under `rootfs/`, every `*.sh`, and (added in Task 11) `Dockerfile*`.
- **Fail loudly on permanent misconfiguration.** A `GPU_VENDOR` that cannot work must be reported at startup, in the container log, with the reason and the fix — never by failing every conversion later.
- **3-digit SemVer**, tags `vX.Y.Z`, hand-written emoji-categorised release notes. **Never tag or publish a release without explicit approval from jdp.**
- Never `git add -A`; always stage explicit paths.
- No real user data, no real IPs.

## Coordination with Plan 2 (NVIDIA) — read this before touching a shared file

Plan 2 and Plan 3 both extend the same seam. These files are touched by both plans:

Plan 2 (`docs/superpowers/plans/2026-08-12-handbrake-nvidia-gpu.md`) was written in
parallel with this one and is already committed. Its shape, as of that commit:
it rewrites the whole of `handbrake-gpu.sh` with its own helpers
(`hb_help_lists_encoder`, `hb_help_lists_nvdec`, `nvidia_device_present`,
`nvidia_lib_path`, `nvidia_smi_summary`), replaces README section 8 wholesale,
ships `v1.1.0`, records its findings in a separate `docs/hardware-encoding-nvidia.md`,
and **adds no assertions to `build.yml`**.

| File | Collision | Rule |
|---|---|---|
| `rootfs/usr/local/bin/handbrake-gpu.sh` | Both rewrite the whole file | Task 6 Steps 1 and 3 carry Plan 2's helpers and its `nvidia)` branch across, **and fix the defect described immediately below.** |
| `Dockerfile` | Only this plan adds a package layer | No overlap. Insert where Task 3 says. |
| `Dockerfile` `GPU_VENDOR` ENV comment | Both correct it | Task 3 Step 3; merge, keep Plan 2's NVIDIA sentence. |
| `README.md` section 8 | Both rewrite it | Task 13 Step 1 gives the merge rule. Plan 2 also edits the section 1 comparison table and section 11 troubleshooting; this plan touches neither, so leave both alone. |
| `.github/workflows/build.yml` smoke step | Only this plan adds assertions | Task 10 appends a delimited block. If a GPU block ever appears there from another plan, append inside it rather than adding a second one. |
| `CLAUDE.md` GPU bullet | Only this plan corrects it | Task 15 gives the final text covering all vendors. |
| `init-handbrake/run` GPU-seam comment | Both may correct it | Comment only, no behaviour change. Task 15 Step 3; if Plan 2 already fixed it, leave its wording. |
| `docs/` capability records | Plan 2 uses `docs/hardware-encoding-nvidia.md`; this plan appends to `docs/handbrake-capabilities.md` | Deliberate: Plan 1's handoff names `docs/handbrake-capabilities.md` as the artefact GPU plans read, and this plan's findings correct that same file. Two files will exist; do not merge them, and do not duplicate content between them. |
| `.github/release-notes/*.md` | May be the same file | Plan 2 ships `v1.1.0`. Task 16 has two literal variants; jdp picks. |
| `rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/dependencies.d/init-video` | Both may create it | Empty marker file, identical either way. Creating it twice is a no-op. |

### The defect to fix while merging Plan 2's branch

Plan 2 detects NVENC by grepping the **build-time** dump
`/usr/local/share/handbrake-cli-help.txt` for `nvenc_h264`. That dump cannot
contain it. `libhb` gates the entire hardware-encoder listing on a live
availability probe:

```c
#if HB_PROJECT_FEATURE_NVENC
            case HB_VCODEC_FFMPEG_NVENC_H264:
                return hb_nvenc_h264_available();
```

The dump is recorded during `docker build`, where no NVIDIA runtime is injected,
so `hb_nvenc_h264_available()` returns false and `nvenc_h264` is filtered out
before the help text is printed. Plan 2's `hb_help_lists_encoder nvenc_h264`
therefore returns false **on every machine, including one with a working
4070 Ti Super**, and the NVIDIA branch would always fall back to software.

The fix is one identifier per call site and is spelled out in Task 6 Step 3:
swap `hb_help_lists_encoder` for this plan's `hb_has_encoder` inside the
`nvidia)` branch, which asks the live binary instead. Keep Plan 2's
`hb_help_lists_nvdec` exactly as it is: the `--enable-hw-decoding` help text is
static and is **not** filtered by hardware, so reading it from the dump is
correct there.

Report this to whoever owns Plan 2 as well, so its own Task 2 expectations
("expect `nvenc_h264` in the dump") get corrected rather than debugged on the
hardware.

---

## What the research established (read this before Task 1)

Five findings drive every task below. Each is reproducible with the command given.

### 1. `HandBrakeCLI --help` hides hardware encoders that are not usable *right now*

This is the single most important finding, and it **corrects an instruction in Plan 1**.

`libhb/common.c` builds its encoder list through `hb_video_encoder_is_enabled()`, which for hardware encoders calls the vendor's availability probe:

```c
#if HB_PROJECT_FEATURE_QSV
        if (encoder & HB_VCODEC_QSV_MASK)
        {
            return hb_qsv_video_encoder_is_available(encoder);
        }
#endif
        switch (encoder)
        {
#if HB_PROJECT_FEATURE_VCE
            case HB_VCODEC_FFMPEG_VCE_H264:
               return hb_vce_h264_available();
```

So an encoder appears in `--help` only when it is **compiled in AND the hardware/runtime can serve it**.

Consequences:

- **`/usr/local/share/handbrake-cli-help.txt` (recorded during `docker build`, on a GPU-less builder) never lists a single hardware encoder.** Plan 1's Task 9 Step 3 expects "NVENC and QSV encoders listed" in that dump. That expectation is wrong, and the recorded dump must not be used as the source of truth for hardware encoder availability. Task 2 records the correct picture.
- Conversely, asking the **live** binary at container start is simultaneously the "never guess an identifier" rule *and* the hardware probe. That is exactly what `handbrake-gpu.sh` will do.
- HandBrake's VCE probe (`libhb/vce_common.c`) `hb_dlopen(AMF_DLL_NAMEA)`s the AMF runtime and creates a real AMF component before answering yes, so a listed `vce_h264` means AMF genuinely loaded.

### 2. Intel QSV is a packaging-level story. AMD VCE is not. They are not symmetric.

Debian/Ubuntu `debian/rules` for the `handbrake` source package passes `--enable-qsv` **on amd64 only** (with `-I/usr/include/vpl`) and `--enable-nvenc` on amd64/arm64/i386. It **never** passes `--enable-vce`. Upstream's own default confirms the asymmetry — in `make/configure.py` both `--enable-qsv` and `--enable-vce` default to on only for `x86_64-w64-mingw32*` (Windows), off everywhere else.

The Ubuntu `handbrake-cli` package (resolute, 1.11.0~us1-0ubuntu1) **already depends on `libvpl2`, `libva2` and `libva-drm2` on amd64**, i.e. the oneVPL dispatcher is installed by Plan 1's apt layer already. What is missing is only the runtime implementation and the VA-API driver.

So:

- **Intel:** add two runtime packages + a branch + docs. No rebuild.
- **AMD:** the shipped binary has no VCE code at all. Getting it needs a full HandBrake source build with `--enable-vce` (which makes HandBrake's bundled FFmpeg add `--enable-amf --enable-encoder=h264_amf --enable-encoder=hevc_amf --enable-encoder=av1_amf`), **and** AMD's proprietary AMF runtime at run time.

### 3. The AMD runtime cannot be shipped, and is being wound down

- The runtime is `libamfrt64.so.1`, distributed only in AMD's proprietary `amf-amdgpu-pro` package from `repo.radeon.com` (installed under `/opt/amdgpu-pro/lib/x86_64-linux-gnu/`). It is not in Ubuntu's archive and is not ours to redistribute.
- AMD no longer ships AMF as part of the Linux driver stack, and `amf-amdgpu-pro-25.10` supports **RDNA1 and RDNA2 only**. HandBrake issue [#7906](https://github.com/HandBrake/HandBrake/issues/7906) documents an RX 9060 XT (RDNA4) where the VCE encoders were listed and encoding still ran on the CPU.
- HandBrake 1.11 has **no VA-API encoder fallback** for AMD. Verified against the source: the 1.11.x branch's encoder table contains `qsv_*`, `vce_*` and `nvenc_*` and no `vaapi_*`. `master` does now carry `vaapi_h264` / `vaapi_hevc` / `vaapi_av1` (upstream PR #7467), so the open-source path is coming, but it is not in the version this image ships.

Conclusion, and the design decision this plan takes: **the default image gets an honest `amd` branch that explains precisely why it is falling back, plus an opt-in `Dockerfile.vce` that users build themselves.** No heavy source-compile stage is added to the default `Dockerfile` and none is added to the default CI matrix.

### 4. Overriding `--encoder` is safe with the preset the daemon uses

`test/test.c` removes `VideoPreset`, `VideoTune`, `VideoProfile`, `VideoLevel` and `VideoOptionExtra` from the preset whenever `--encoder` changes the encoder, and falls back to the new encoder's defaults:

```c
        if (old != new)
        {
            // If the user explicitly changes a video encoder, remove the
            // preset VideoPreset, VideoTune, VideoProfile, VideoLevel, and
            // VideoOptionExtra.
```

So emitting only `--encoder qsv_h264` on top of `General/Very Fast 1080p30` cannot produce an "invalid encoder preset" failure. The branches emit nothing else.

### 5. The base image already fixes `/dev/dri` group membership

`linuxserver/baseimage-selkies` ships an `init-video` oneshot that walks `/dev/dri` and `/dev/dvb`, and adds `abc` to each device's group (creating one when the GID is unknown). **Do not reimplement this.** Task 5 only adds an ordering edge so it has run before we probe.

### Encoder identifiers (from HandBrake 1.11.x `libhb/common.c`, for reference only)

`qsv_h264`, `qsv_h265`, `qsv_h265_10bit`, `qsv_av1`, `qsv_av1_10bit`, `vce_h264`, `vce_h265`, `vce_h265_10bit`, `vce_av1`, `vce_av1_10bit`. **Never type one of these into an argument string.** They are listed here so a reader recognises them in log output; the code looks them up.

---

## Task Overview

| # | Task | Ships |
|---|---|---|
| 1 | Preflight: confirm the seam is exactly as Plan 1 left it | (no new files) |
| 2 | Record the real hardware-encoder truth of this packaging | `docs/handbrake-capabilities.md` (new section) |
| 3 | Dockerfile: Intel QSV runtime layer (amd64 only) | `Dockerfile`, `NOTICE` |
| 4 | Build and verify the QSV runtime layer | (no new files) |
| 5 | Ordering edge: `init-handbrake` after `init-video` | `init-handbrake/dependencies.d/init-video` |
| 6 | Rewrite `handbrake-gpu.sh` with the live probe, `intel` and `amd` | `rootfs/usr/local/bin/handbrake-gpu.sh` |
| 7 | Offline verification of the rewritten script | (no new files) |
| 8 | Container verification: `GPU_VENDOR=intel` without an Intel GPU | (no new files) |
| 9 | Container verification: `GPU_VENDOR=amd` without an AMD GPU | (no new files) |
| 10 | CI: assert the seam and the fallback logic | `.github/workflows/build.yml` |
| 11 | Optional AMD VCE variant image | `Dockerfile.vce`, `.gitattributes`, `justfile` |
| 12 | Build the variant and record what it really contains | `docs/handbrake-capabilities.md` (VCE section) |
| 13 | README: Hardware Encoding | `README.md` |
| 14 | README + issue form: Community Verification | `README.md`, `.github/ISSUE_TEMPLATE/*` |
| 15 | Documentation consistency pass | `CLAUDE.md`, `init-handbrake/run` (comment) |
| 16 | Release notes and version entry | `.github/release-notes/vX.Y.Z.md` |

---

### Task 1: Preflight — confirm the seam is exactly as Plan 1 left it

**Files:**
- Modify/Create: none.

**Interfaces:**
- Consumes: everything Plan 1 produced.
- Produces: certainty about whether Plan 2 has already landed, which decides two merge steps later (Task 6 Step 1, Task 13 Step 1).

- [ ] **Step 1: Confirm Plan 1 is merged and the working tree is clean**

```bash
cd /d/nextcloud/it/github/handbrake
git fetch origin
git status --short
git log --oneline -5
ls -1 rootfs/usr/local/bin/
```

Expected: a clean tree, `main` up to date with `origin/main`, and the four scripts `handbrake-gpu.sh`, `handbrake-theme.sh`, `handbrake-watch.sh`, `print-banner.sh`.

If `rootfs/usr/local/bin/handbrake-gpu.sh` does not exist, **stop**: Plan 1 is not implemented and nothing in this plan can be executed.

- [ ] **Step 2: Confirm the seam contract has not drifted**

```bash
cd /d/nextcloud/it/github/handbrake
grep -n 'gpu_args_for_vendor\|gpu-args\|gpu-vendor' \
  rootfs/usr/local/bin/handbrake-gpu.sh \
  rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/run \
  rootfs/usr/local/bin/handbrake-watch.sh
```

Expected, all three of these must be present:

- `handbrake-gpu.sh` defines `gpu_args_for_vendor()` and writes `/run/handbrake/gpu-vendor`.
- `init-handbrake/run` contains `if /usr/local/bin/handbrake-gpu.sh "${GPU_VENDOR:-none}" > /run/handbrake/gpu-args; then`.
- `handbrake-watch.sh` contains `read -r -a HB_GPU_ARGS <<< "$(cat /run/handbrake/gpu-args 2>/dev/null || true)"`.

If any is missing or spelled differently, fix **this plan's** references to match the repo, not the other way round.

- [ ] **Step 3: Determine whether Plan 2 (NVIDIA) has already landed**

```bash
cd /d/nextcloud/it/github/handbrake
grep -n 'nvidia)' rootfs/usr/local/bin/handbrake-gpu.sh || echo "NO nvidia branch yet"
grep -n 'nvenc\|NVIDIA' README.md CLAUDE.md | head -20
ls -1 .github/release-notes/ 2>/dev/null
```

Write the answer down; Tasks 6, 10, 13, 15 and 16 branch on it.

- [ ] **Step 4: Read the capabilities Plan 1 recorded**

```bash
cd /d/nextcloud/it/github/handbrake
cat docs/handbrake-capabilities.md
```

Expected: a version block, an encoder block, container formats, presets and the GTK toolkit line. Note which hardware encoders it claims are present. Task 2 explains why that list is almost certainly empty and records the real picture.

- [ ] **Step 5: Build the current image once, so later tasks have something to compare against**

```bash
cd /d/nextcloud/it/github/handbrake
docker build -t handbrake:pre-gpu .
docker images --format '{{.Repository}}:{{.Tag}}\t{{.Size}}' | grep handbrake
```

Expected: a successful build, and a recorded size for `handbrake:pre-gpu`. **Write the size down** — Task 4 measures the cost of the QSV runtime against it.

No commit for this task; nothing changed.

---

### Task 2: Record the real hardware-encoder truth of this packaging

Plan 1's rule was "read the encoder identifier from `/usr/local/share/handbrake-cli-help.txt`". That dump is recorded on a GPU-less build machine and therefore lists no hardware encoders at all. This task records what is actually true, using checks that need no GPU, and writes it into the file Plans 2-4 read.

**Files:**
- Modify: `d:\nextcloud\it\github\handbrake\docs\handbrake-capabilities.md`

**Interfaces:**
- Consumes: `handbrake:pre-gpu` (Task 1), `/usr/bin/HandBrakeCLI` inside it.
- Produces: the "Hardware encoder support in this packaging" section, which Task 6's design rests on and Task 13's README text quotes.

- [ ] **Step 1: Show that the recorded dump lists no hardware encoders**

```bash
docker run --rm --entrypoint sh handbrake:pre-gpu -c \
  "awk '/^[[:space:]]*-e, --encoder[[:space:]]/{f=1;next} f&&/^[[:space:]]*-/{f=0} f' /usr/local/share/handbrake-cli-help.txt"
```

Expected: a list of software encoders only (`x264`, `x264_10bit`, `x265`, `x265_10bit`, `x265_12bit`, `mpeg4`, `mpeg2`, `VP8`, `VP9`, `svt_av1`, and similar). **No `qsv_*`, no `nvenc_*`, no `vce_*`.** This is the runtime filter at work, not a packaging gap.

- [ ] **Step 2: Prove QSV *is* compiled in, without any Intel hardware**

```bash
docker run --rm --entrypoint sh handbrake:pre-gpu -c \
  'dpkg -s handbrake-cli | grep -i "^Depends" | tr "," "\n" | grep -iE "vpl|va-?drm|libva"'
docker run --rm --entrypoint sh handbrake:pre-gpu -c \
  'objdump -p /usr/bin/HandBrakeCLI 2>/dev/null | grep NEEDED | grep -i vpl || echo "objdump unavailable, see the readelf line below"'
docker run --rm --entrypoint sh handbrake:pre-gpu -c \
  'grep -c -a -F "libvpl.so.2" /usr/bin/HandBrakeCLI'
```

Expected on amd64: the `Depends` filter prints `libvpl2 (>= 1:2.16.0)` (plus `libva2`, `libva-drm2`), and the `grep -c` prints a number `>= 1`. Linking against the oneVPL dispatcher is only possible if the package was built with `--enable-qsv`. That is the hardware-free proof.

(`objdump` is part of binutils and is not installed in the runtime image; the `grep -c -a` line is the fallback and is the one that must pass.)

- [ ] **Step 3: Prove VCE is *not* compiled in, without any AMD hardware**

```bash
docker run --rm --entrypoint sh handbrake:pre-gpu -c \
  'grep -c -a -F "libamfrt64" /usr/bin/HandBrakeCLI || true'
curl -fsSL "https://sources.debian.org/src/handbrake/unstable/debian/rules/" \
  | grep -o 'enable-[a-z]*' | sort -u
```

Expected: the `grep -c` prints `0` (no AMF runtime name anywhere in the binary, so no AMF code path), and the `debian/rules` flag list contains `enable-qsv`, `enable-nvenc` and `enable-x265` but **no `enable-vce`**.

If the `sources.debian.org` call fails (network policy, API change), substitute this equivalent and record its output instead:

```bash
docker run --rm --entrypoint sh handbrake:pre-gpu -c \
  'grep -c -a -F "h264_amf" /usr/bin/HandBrakeCLI || true'
```

Expected: `0`.

- [ ] **Step 4: Record the live encoder list on this GPU-less machine**

```bash
docker run --rm --entrypoint sh handbrake:pre-gpu -c \
  "HandBrakeCLI --help 2>/dev/null | awk '/^[[:space:]]*-e, --encoder[[:space:]]/{f=1;next} f&&/^[[:space:]]*-/{f=0} f'"
```

Expected: identical to Step 1 (software encoders only). Keep the output; it goes into the document.

- [ ] **Step 5: Append the section to `docs/handbrake-capabilities.md`**

Append this to the end of the file, replacing every `<paste ...>` with the literal command output from Steps 1-4:

````markdown
## Hardware encoder support in this packaging

Recorded on `<paste: date -I>` from `handbrake:pre-gpu`, built at commit
`<paste: git rev-parse --short HEAD>`. Regenerate after every base-image or
HandBrake version bump.

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
<paste the output of Step 4>
```

### Intel QSV: compiled in on amd64

Ubuntu builds `handbrake-cli` with `--enable-qsv` on amd64 and links it against
the system oneVPL dispatcher, so the package already depends on it:

```text
<paste the output of Step 2, first command>
```

Proof in the binary itself (needs no Intel hardware):

```text
<paste the output of Step 2, third command>
```

Missing from a stock image, and added by this repo's Dockerfile on amd64:
`libmfx-gen1.2` (oneVPL GPU runtime) and `intel-media-va-driver-non-free` (iHD
VA-API driver). Neither is a package dependency because both are hardware
specific.

### AMD VCE: not compiled in

```text
<paste the output of Step 3>
```

`0` occurrences of the AMF runtime name means the binary contains no AMD VCE
code path at all. Debian/Ubuntu do not pass `--enable-vce`; upstream's own
default enables it only for Windows hosts. HandBrake 1.11 also has no VA-API
encoder fallback (the 1.11.x encoder table has `qsv_*`, `vce_*` and `nvenc_*`
and no `vaapi_*`; VA-API exists only on `master` so far).

Getting AMD hardware encoding therefore needs **both** a source rebuild with
`--enable-vce` **and** AMD's proprietary `libamfrt64.so.1` runtime at run time.
See `Dockerfile.vce` and the README's Hardware Encoding section.
````

- [ ] **Step 6: Verify no placeholder survived**

```bash
cd /d/nextcloud/it/github/handbrake
grep -n '<paste' docs/handbrake-capabilities.md && echo "PLACEHOLDERS LEFT — fix them" || echo "no placeholders"
```

Expected: `no placeholders`.

- [ ] **Step 7: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add docs/handbrake-capabilities.md
git commit -m "docs: record which hardware encoders this HandBrake packaging really contains"
```

---

### Task 3: Dockerfile — Intel QSV runtime layer (amd64 only)

**Files:**
- Modify: `d:\nextcloud\it\github\handbrake\Dockerfile`
- Modify: `d:\nextcloud\it\github\handbrake\NOTICE`

**Interfaces:**
- Consumes: the Selkies/Ubuntu base and the apt layer Plan 1 wrote.
- Produces, for Task 6 and for every amd64 user: `/usr/lib/x86_64-linux-gnu/dri/iHD_drv_video.so`, the oneVPL GPU runtime, `vainfo` and `vpl-inspect` inside the image.

- [ ] **Step 1: Insert the QSV runtime layer**

Insert the block below into `Dockerfile` **between** the `locale-gen en_US.UTF-8` `RUN` and the `# Fail loudly if the HandBrake packaging layout ever moves` comment block. Nothing else in the Dockerfile changes.

```dockerfile
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
```

- [ ] **Step 2: Confirm the non-free driver may actually be redistributed**

The image is public. Before shipping a multiverse package inside it, read its licence out of the built image (Task 4 builds it; run this then and come back if it fails):

```bash
docker run --rm --entrypoint sh handbrake:qsv -c \
  'sed -n "1,40p" /usr/share/doc/intel-media-va-driver-non-free/copyright'
```

Expected: an MIT/Expat-style permissive licence permitting redistribution (the package is "non-free" in the Debian sense because it enables pre-built binary kernels, not because redistribution is forbidden).

**Decision rule, apply it, do not defer it:** if that text does **not** permit redistribution, change `intel-media-va-driver-non-free` to `intel-media-va-driver` in the block above, keep everything else identical, and add this sentence to the README's Intel paragraph in Task 13: "This image ships the free `intel-media-va-driver`; some Intel generations need the non-free variant for encoding, which you can add with a two-line derived Dockerfile."

- [ ] **Step 3: Correct the now-false `GPU_VENDOR` comment in the Dockerfile ENV block**

Plan 1's ENV documentation says the image ships no GPU acceleration. After this
task that is wrong. Replace the four comment lines

```dockerfile
# GPU_VENDOR       – none (default) | nvidia | intel | amd. v1 ships NO GPU
#                    acceleration: any value other than "none" logs a clear
#                    warning and falls back to software encoding. The seam is
#                    /usr/local/bin/handbrake-gpu.sh -> /run/handbrake/gpu-args.
```

with

```dockerfile
# GPU_VENDOR       – none (default) | nvidia | intel | amd. The seam is
#                    /usr/local/bin/handbrake-gpu.sh -> /run/handbrake/gpu-args.
#                    "intel" needs /dev/dri passed through (amd64 only; the QSV
#                    runtime is installed above). "amd" needs a HandBrakeCLI
#                    built with --enable-vce plus AMD's proprietary AMF runtime,
#                    neither of which this image can ship — see Dockerfile.vce.
#                    Any vendor that cannot be honoured logs the reason and
#                    falls back to software encoding.
```

If Plan 2 already rewrote these lines for NVENC, merge instead of replacing:
keep its NVIDIA sentence and add the Intel/AMD ones.

- [ ] **Step 4: Add the two components to `NOTICE`**

In `NOTICE`, in the bundled-component list, directly after the `* LinuxServer.io baseimage-selkies` entry, add:

```text
  * Intel Media Driver (iHD VA-API driver)   MIT (ships pre-built binary kernels,
                                             hence Ubuntu multiverse)
                                             https://github.com/intel/media-driver
  * Intel VPL GPU Runtime (libmfx-gen)       MIT
                                             https://github.com/intel/vpl-gpu-rt
  * Intel oneVPL dispatcher (libvpl)         MIT
                                             https://github.com/intel/libvpl
```

- [ ] **Step 5: Lint**

```bash
cd /d/nextcloud/it/github/handbrake
hadolint Dockerfile --ignore DL3008 --ignore DL3009
grep -n 'ships NO GPU' Dockerfile && echo "STALE COMMENT LEFT — fix Step 3" || echo "ENV comment is current"
```

Expected: hadolint silent with exit code 0, and `ENV comment is current`.

- [ ] **Step 6: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add Dockerfile NOTICE
git commit -m "feat: ship the Intel QSV runtime (oneVPL GPU runtime + iHD driver) on amd64"
```

---

### Task 4: Build and verify the QSV runtime layer

**Files:**
- Modify/Create: none.

**Interfaces:**
- Consumes: the Dockerfile from Task 3.
- Produces: a measured size delta that Task 13's README quotes, and the confirmation Task 6 depends on (`vainfo`/`vpl-inspect` exist).

- [ ] **Step 1: Build**

```bash
cd /d/nextcloud/it/github/handbrake
docker build -t handbrake:qsv .
```

Expected, in the build log:

```
handbrake: QSV runtime installed ->
libmfx-gen1.2 <version>
intel-media-va-driver-non-free <version>
libvpl2 <version>
```

If a package name no longer resolves, the Ubuntu series moved it. Find the replacement with `docker run --rm --entrypoint sh handbrake:pre-gpu -c 'apt-get update >/dev/null && apt-cache search onevpl media-va-driver'`, put the real name in the Dockerfile, and rerun this step. Do not delete the package and move on.

- [ ] **Step 2: Verify the runtime landed and measure the cost**

```bash
docker run --rm --entrypoint sh handbrake:qsv -c \
  'ls -l /usr/lib/x86_64-linux-gnu/dri/iHD_drv_video.so; \
   ls -1 /usr/lib/x86_64-linux-gnu/ | grep -E "libmfx-gen|libvpl"; \
   command -v vainfo vpl-inspect'
docker images --format '{{.Repository}}:{{.Tag}}\t{{.Size}}' | grep -E 'handbrake:(pre-gpu|qsv)'
```

Expected: `iHD_drv_video.so` present, `libmfx-gen.so.1.2*` and `libvpl.so.2*` listed, `/usr/bin/vainfo` and `/usr/bin/vpl-inspect` printed, and two size lines. **Record the delta** (`qsv` minus `pre-gpu`); it belongs in the README.

- [ ] **Step 3: Verify the runtime does not break a GPU-less container**

```bash
docker run --rm --entrypoint sh handbrake:qsv -c \
  'vainfo --display drm --device /dev/dri/renderD128 >/tmp/o 2>&1; echo "vainfo exit=$?"; head -n 3 /tmp/o'
docker run --rm --entrypoint sh handbrake:qsv -c \
  'vpl-inspect >/tmp/o 2>&1; echo "vpl-inspect exit=$?"; head -n 5 /tmp/o'
docker run --rm --entrypoint sh handbrake:qsv -c 'HandBrakeCLI --version'
```

Expected: `vainfo` fails to open the device (there is none) and `vpl-inspect` reports no implementation — both **without hanging** and without killing the shell — and `HandBrakeCLI --version` still prints the version. A hang here would stall every container start, so if either command does not return within a few seconds, stop and investigate before continuing.

- [ ] **Step 4: Verify the arm64 path skips the layer**

```bash
cd /d/nextcloud/it/github/handbrake
docker buildx build --platform linux/arm64 -t handbrake:qsv-arm64 --load . 2>&1 | grep -i "QSV runtime skipped"
```

Expected: `handbrake: Intel QSV runtime skipped on arm64 (Quick Sync is x86-64 only)`.

**If QEMU/binfmt is not set up locally this build will not run.** That is acceptable: the same assertion is covered natively by the arm64 job in CI (Task 10 Step 2). In that case skip this step here and confirm it in the CI log after pushing, before considering the task done.

No commit for this task; nothing changed.

---

### Task 5: Ordering edge — `init-handbrake` runs after `init-video`

`handbrake-gpu.sh` will probe HandBrake **as `abc`**, so that a `/dev/dri` group problem is caught at startup rather than by every failing conversion. That is only meaningful once the base image's `init-video` oneshot has added `abc` to the render node's group.

**Files:**
- Create: `d:\nextcloud\it\github\handbrake\rootfs\etc\s6-overlay\s6-rc.d\init-handbrake\dependencies.d\init-video` (empty)

**Interfaces:**
- Consumes: the base image's `init-video` oneshot.
- Produces: the guarantee Task 6's probe relies on.

- [ ] **Step 1: Confirm `init-video` exists in the pinned base image**

A dependency on a service that does not exist makes the whole s6-rc database fail to compile, which bricks the container. Check first:

```bash
base=$(grep -oP 'ARG BASE_TAG=\K\S+' /d/nextcloud/it/github/handbrake/Dockerfile)
docker run --rm --entrypoint sh "ghcr.io/linuxserver/baseimage-selkies:${base}" -c \
  'ls -d /etc/s6-overlay/s6-rc.d/init-video && head -n 25 /etc/s6-overlay/s6-rc.d/init-video/run'
```

Expected: the directory exists, and the script stats devices under `/dev/dri` / `/dev/dvb` and `groupadd`s / `usermod`s `abc` onto their GIDs.

If it does **not** exist, skip this task entirely and change Task 6 Step 1 to drop the `s6-setuidgid abc` wrapper from `hb_load_encoders` (probe as root instead) and note in the README that the container user must be able to read `/dev/dri`.

- [ ] **Step 2: Create the ordering edge**

```bash
cd /d/nextcloud/it/github/handbrake
mkdir -p rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/dependencies.d
: > rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/dependencies.d/init-video
ls -1 rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/dependencies.d/
```

Expected:

```
init-selkies-config
init-video
```

- [ ] **Step 3: Verify there is no dependency cycle**

`init-video` depends on `init-selkies-config`; `init-handbrake` now depends on both. Nothing in the base depends on `init-handbrake` before `init-config-end`. Prove it after Task 6 with a real boot (Task 8 Step 1): a cycle makes s6-rc refuse to start and the container exits immediately with an `s6-rc: fatal` line.

- [ ] **Step 4: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/dependencies.d/init-video
git commit -m "fix: order init-handbrake after the base init-video device-group setup"
```

---

### Task 6: Rewrite `handbrake-gpu.sh` with the live probe, `intel` and `amd`

**Files:**
- Modify: `d:\nextcloud\it\github\handbrake\rootfs\usr\local\bin\handbrake-gpu.sh` (full replacement)

**Interfaces:**
- Consumes: `HandBrakeCLI` on `PATH`, `s6-setuidgid`, `/dev/dri/renderD*`, `vainfo` and `vpl-inspect` (Task 3), `PUID`/`PGID` from the container environment.
- Produces, for the rest of this plan and for Plan 2:
  - `hb_load_encoders` / `hb_has_encoder` / `hb_pick_encoder` — the live-probe helpers. **Plan 2's `nvidia` branch should use `hb_pick_encoder nvenc_h264` rather than inventing its own detection.**
  - `/config/handbrake-gpu.log` — the diagnostics report the README asks users to attach to a hardware report.
  - stdout `--encoder <id>` or empty, unchanged contract.

- [ ] **Step 1: If Plan 2 has landed, save its branch AND its helpers first**

Plan 2 rewrites this same file, so there are two things to carry across, not one:

```bash
cd /d/nextcloud/it/github/handbrake
cp rootfs/usr/local/bin/handbrake-gpu.sh /tmp/handbrake-gpu.plan2.sh
echo "--- nvidia branch ---"
sed -n '/^        nvidia)/,/^            ;;$/p' /tmp/handbrake-gpu.plan2.sh
echo "--- nvidia helpers ---"
grep -n 'HB_CLI_HELP=\|^hb_help_lists_nvdec()\|^nvidia_device_present()\|^nvidia_lib_path()\|^nvidia_smi_summary()\|^NVENC_CANDIDATES=' /tmp/handbrake-gpu.plan2.sh
```

Keep that copy: Step 3 pastes both pieces back. If the file has no `nvidia)`
branch, Plan 2 has not landed, nothing needs preserving, and `nvidia` will fall
into the `*)` branch with an accurate message until Plan 2 arrives.

- [ ] **Step 2: Replace the file**

`d:\nextcloud\it\github\handbrake\rootfs\usr\local\bin\handbrake-gpu.sh` — complete new content:

```bash
#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# handbrake-gpu.sh <vendor>
# ---------------------------------------------------------------------------
# Resolves GPU_VENDOR into the extra HandBrakeCLI arguments used for hardware
# encoding. Prints the argument string on STDOUT (empty = software encoding) and
# human-readable decision lines on STDERR.
#
# STDOUT IS A COMMAND LINE, NOT A LOG.
#   init-handbrake redirects this script's stdout into /run/handbrake/gpu-args,
#   and handbrake-watch.sh splices that file into every HandBrakeCLI invocation.
#   A single stray echo on stdout becomes a bogus HandBrakeCLI argument and
#   breaks every conversion. Everything human-readable goes through log()/warn(),
#   which write to stderr.
#
# HOW A VENDOR IS DETECTED: BY ASKING HANDBRAKE
#   libhb lists a hardware encoder in --help only when it is BOTH compiled in
#   AND usable on the hardware present right now (libhb/common.c,
#   hb_video_encoder_is_enabled() -> hb_qsv_video_encoder_is_available() /
#   hb_vce_h264_available() / hb_nvenc_h264_available()). One --help call is
#   therefore the identifier lookup and the hardware probe at the same time, and
#   no encoder id is ever hardcoded into an argument.
#
#   Do NOT use the build-time dump /usr/local/share/handbrake-cli-help.txt for
#   this. It is recorded during `docker build` on a machine with no GPU, so it
#   never contains a single hardware encoder. See docs/handbrake-capabilities.md.
#
#   The probe runs as abc, the user that later runs the conversions, so a
#   missing /dev/dri group membership is caught here instead of failing every
#   job later. init-handbrake depends on the base image's init-video oneshot,
#   which is what puts abc into the render node's group.
#
# EXTENSION POINT: add a branch to gpu_args_for_vendor() and give it a candidate
# list for hb_pick_encoder. Nothing else in the container needs to change.
# ---------------------------------------------------------------------------
set -eu

GPU_LOG="/config/handbrake-gpu.log"

log()  { echo "[handbrake-gpu] $*" >&2; }
warn() { echo "[handbrake-gpu] WARNING: $*" >&2; }

VENDOR_RAW="${1:-none}"
VENDOR="$(printf '%s' "${VENDOR_RAW}" | tr '[:upper:]' '[:lower:]')"

case "${VENDOR}" in
    ""|none|off|disabled) VENDOR="none" ;;
    nvidia|nvenc)         VENDOR="nvidia" ;;
    intel|qsv)            VENDOR="intel" ;;
    amd|vce|vcn)          VENDOR="amd" ;;
    *)
        warn "unrecognised GPU_VENDOR='${VENDOR_RAW}' — use none, nvidia, intel or amd"
        VENDOR="none"
        ;;
esac

# --- probes -----------------------------------------------------------------

HB_ENCODERS=""

# hb_load_encoders — ask the real binary once, as the runtime user, and cache
# the newline-separated encoder ids in HB_ENCODERS.
#
# Each vendor branch calls this DIRECTLY before anything else. That is not
# redundant: hb_pick_encoder is used inside a command substitution, which runs
# in a subshell, so a cache filled in there would be thrown away and every
# candidate would re-run HandBrakeCLI --help. Filling it in the parent first
# means exactly one --help call per container start.
hb_load_encoders() {
    if [ -n "${HB_ENCODERS}" ]; then
        return 0
    fi
    local raw=""
    if command -v s6-setuidgid >/dev/null 2>&1 && id abc >/dev/null 2>&1; then
        raw="$(s6-setuidgid abc env HOME=/config XDG_CONFIG_HOME=/config/.config \
                 HandBrakeCLI --help 2>/dev/null || true)"
    else
        raw="$(HandBrakeCLI --help 2>/dev/null || true)"
    fi
    HB_ENCODERS="$(printf '%s\n' "${raw}" | awk '
        /^[[:space:]]*-e, --encoder[[:space:]]/ { inlist = 1; next }
        inlist && /^[[:space:]]*-/              { inlist = 0 }
        inlist {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            if ($0 != "") print
        }
    ')"
    if [ -z "${HB_ENCODERS}" ]; then
        warn "HandBrakeCLI --help produced no encoder list — hardware detection cannot run."
    fi
}

hb_has_encoder() {
    hb_load_encoders
    printf '%s\n' "${HB_ENCODERS}" | grep -qxF -- "$1"
}

# hb_pick_encoder <id> [id...] — echo the first id this build offers on this
# machine; return 1 when it offers none of them.
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

hb_render_nodes() { ls -1 /dev/dri/renderD* 2>/dev/null || true; }

# hb_have_amf_runtime — used only to explain WHY an AMD encoder is missing.
# AMD's AMF runtime is proprietary, is not in Ubuntu, and cannot ship in this
# image; a user has to bind-mount it in, which happens after the image was
# built, so the loader cache is refreshed before it is consulted.
hb_have_amf_runtime() {
    ldconfig >/dev/null 2>&1 || true
    if ldconfig -p 2>/dev/null | grep -q 'libamfrt64\.so'; then
        return 0
    fi
    local cand
    for cand in /usr/lib/x86_64-linux-gnu/libamfrt64.so* \
                /usr/lib/libamfrt64.so* \
                /opt/amdgpu-pro/lib/x86_64-linux-gnu/libamfrt64.so*; do
        if [ -e "${cand}" ]; then
            return 0
        fi
    done
    return 1
}

# hb_write_diag <vendor> — everything a hardware report needs, in one file.
# Writes to ${GPU_LOG} ONLY. Never to stdout.
hb_write_diag() {
    local vendor="$1" node
    node="$(hb_render_nodes | head -n 1)"
    {
        echo "=== handbrake-gpu diagnostics ==="
        echo "date             : $(date -Is)"
        echo "GPU_VENDOR (raw) : ${VENDOR_RAW}"
        echo "vendor (parsed)  : ${vendor}"
        echo "architecture     : $(uname -m)"
        echo
        echo "--- image build ---"
        if [ -f /etc/handbrake-build ]; then
            cat /etc/handbrake-build
        else
            echo "no /etc/handbrake-build"
        fi
        head -n 1 /usr/local/share/handbrake-version.txt 2>/dev/null || echo "no version dump"
        echo
        echo "--- /dev/dri ---"
        ls -l /dev/dri 2>&1 || true
        echo
        echo "--- runtime user (must be in the render node's group) ---"
        id abc 2>&1 || true
        echo
        echo "--- DRM kernel drivers ---"
        for drv in /sys/class/drm/renderD*/device/driver; do
            if [ -e "${drv}" ]; then
                echo "${drv} -> $(basename "$(readlink -f "${drv}")")"
            fi
        done
        echo
        echo "--- encoders HandBrakeCLI offers HERE (compiled in AND hardware usable) ---"
        printf '%s\n' "${HB_ENCODERS}"
        echo
        echo "--- vainfo ---"
        if command -v vainfo >/dev/null 2>&1 && [ -n "${node}" ]; then
            vainfo --display drm --device "${node}" 2>&1 || true
        else
            echo "vainfo not installed, or no render node to query"
        fi
        echo
        echo "--- vpl-inspect (Intel oneVPL) ---"
        if command -v vpl-inspect >/dev/null 2>&1; then
            vpl-inspect 2>&1 || true
        else
            echo "vpl-inspect not installed"
        fi
        echo
        echo "--- AMF runtime (AMD VCE) ---"
        ldconfig -p 2>/dev/null | grep -i 'libamfrt64' || echo "libamfrt64.so* is not in the loader cache"
    } > "${GPU_LOG}" 2>&1 || true
    chown "${PUID:-911}:${PGID:-911}" "${GPU_LOG}" 2>/dev/null || true
    chmod 0644 "${GPU_LOG}" 2>/dev/null || true
}

# --- vendor selection -------------------------------------------------------

gpu_args_for_vendor() {
    local vendor="$1" enc="" node=""

    case "${vendor}" in
        none)
            printf ''
            log "GPU acceleration: none — software encoding (x264/x265)"
            return 0
            ;;

        intel)
            hb_load_encoders
            hb_write_diag "${vendor}"
            node="$(hb_render_nodes | head -n 1)"

            if [ -z "${node}" ]; then
                printf ''
                warn "GPU_VENDOR=intel, but no DRM render node (/dev/dri/renderD*) is visible in this container."
                warn "Pass the iGPU through: Unraid adds '--device=/dev/dri' under Extra Parameters, plain docker run takes '--device /dev/dri'."
                warn "The host also needs the i915 (or xe) kernel driver loaded."
                warn "Falling back to software encoding."
                return 0
            fi

            enc="$(hb_pick_encoder qsv_h264 || true)"
            if [ -z "${enc}" ]; then
                printf ''
                warn "GPU_VENDOR=intel and ${node} exists, but HandBrakeCLI does not offer qsv_h264 on this machine."
                warn "HandBrake lists a hardware encoder only when it is compiled in AND usable, so one of these holds:"
                warn "  * the GPU is not an Intel one, or is older than the oneVPL GPU runtime supports"
                warn "  * the container user cannot use ${node} (check 'runtime user' in ${GPU_LOG})"
                warn "  * this is arm64 — Intel Quick Sync is x86-64 only"
                warn "Full details in ${GPU_LOG}. Falling back to software encoding."
                return 0
            fi

            printf -- '--encoder %s' "${enc}"
            log "Intel QSV enabled: --encoder ${enc} (render node ${node})"
            log "diagnostics: ${GPU_LOG}"
            ;;

        amd)
            hb_load_encoders
            hb_write_diag "${vendor}"
            node="$(hb_render_nodes | head -n 1)"

            if [ -z "${node}" ]; then
                printf ''
                warn "GPU_VENDOR=amd, but no DRM render node (/dev/dri/renderD*) is visible in this container."
                warn "Pass the GPU through: Unraid adds '--device=/dev/dri' under Extra Parameters, plain docker run takes '--device /dev/dri'."
                warn "The host also needs the amdgpu kernel driver loaded."
                warn "Falling back to software encoding."
                return 0
            fi

            # vce_h264   AMD VCE through AMF. Only exists in a HandBrakeCLI built
            #            with --enable-vce (see Dockerfile.vce), and HandBrake only
            #            lists it once AMD's proprietary AMF runtime has actually
            #            loaded and produced encoder caps.
            # vaapi_h264 Not in HandBrake 1.11; upstream added VA-API encoders on
            #            master. Named here so a later base-image bump lights the
            #            path up with no code change, because ids are looked up.
            enc="$(hb_pick_encoder vce_h264 vaapi_h264 || true)"
            if [ -z "${enc}" ]; then
                printf ''
                warn "GPU_VENDOR=amd and ${node} exists, but HandBrakeCLI offers neither vce_h264 nor vaapi_h264 here."
                if hb_have_amf_runtime; then
                    warn "AMD's AMF runtime IS reachable, so this HandBrakeCLI was simply not built with --enable-vce."
                    warn "Ubuntu never builds HandBrake with VCE. Build the optional variant (Dockerfile.vce) to get it."
                else
                    warn "AMD's AMF runtime (libamfrt64.so*) is not reachable in this container, and Ubuntu does not build"
                    warn "HandBrake with --enable-vce either, so this image has no AMD hardware encoder at all."
                    warn "The README's Hardware Encoding section explains what AMD hardware encoding needs."
                fi
                warn "Full details in ${GPU_LOG}. Falling back to software encoding."
                return 0
            fi

            printf -- '--encoder %s' "${enc}"
            log "AMD hardware encoding enabled: --encoder ${enc} (render node ${node})"
            log "diagnostics: ${GPU_LOG}"
            ;;

        *)
            printf ''
            warn "GPU_VENDOR='${vendor}' is not implemented in this image build — falling back to software encoding."
            ;;
    esac
}

printf '%s' "${VENDOR}" > /run/handbrake/gpu-vendor 2>/dev/null || true
gpu_args_for_vendor "${VENDOR}"
```

- [ ] **Step 3: Re-insert Plan 2's helpers and branch, and fix its encoder lookup**

Only if Step 1 found them. Three edits, in this order:

1. **Helpers.** From `/tmp/handbrake-gpu.plan2.sh`, copy `HB_CLI_HELP=`,
   `NVENC_CANDIDATES=`, `hb_help_lists_nvdec()`, `nvidia_device_present()`,
   `nvidia_lib_path()` and `nvidia_smi_summary()` into the `--- probes ---`
   section of the new file, after `hb_have_amf_runtime`. Do **not** copy
   `hb_help_lists_encoder()`: it is the broken one, and `hb_has_encoder` already
   does its job correctly.
2. **Branch.** Paste the whole `nvidia)` branch back **between** the `none)`
   branch's `;;` and the `intel)` line, unchanged apart from edit 3.
3. **The one-word correction.** Inside that branch, replace every
   `hb_help_lists_encoder` with `hb_has_encoder`:

   ```bash
   cd /d/nextcloud/it/github/handbrake
   sed -i 's/hb_help_lists_encoder/hb_has_encoder/g' rootfs/usr/local/bin/handbrake-gpu.sh
   grep -n 'hb_help_lists_encoder\|hb_has_encoder\|hb_help_lists_nvdec' rootfs/usr/local/bin/handbrake-gpu.sh
   ```

   Expected: no `hb_help_lists_encoder` left, `hb_has_encoder` defined once and
   called from the `nvidia`, `intel` and `amd` branches, and
   `hb_help_lists_nvdec` still present and still reading `HB_CLI_HELP` (correct:
   the `--enable-hw-decoding` help text is static and is not filtered by
   hardware).

Why this correction is required rather than optional: `nvenc_h264` is filtered
out of the build-time dump on any machine without an NVIDIA runtime, which is
every build machine, so the dump-based lookup returns false even on a working
GPU. See "The defect to fix while merging Plan 2's branch" near the top of this
plan for the source evidence.

- [ ] **Step 4: Confirm the merged file still has exactly one of everything**

```bash
cd /d/nextcloud/it/github/handbrake
grep -c '^gpu_args_for_vendor()' rootfs/usr/local/bin/handbrake-gpu.sh
grep -n '^        \(none\|nvidia\|intel\|amd\|\*\))' rootfs/usr/local/bin/handbrake-gpu.sh
grep -c '^set -eu' rootfs/usr/local/bin/handbrake-gpu.sh
```

Expected: `1`, then the five branch labels in the order `none`, `nvidia`,
`intel`, `amd`, `*` (with `nvidia` absent if Plan 2 has not landed), then `1`.
Two `set -eu` lines or two `case` blocks mean the paste landed in the wrong
place.

- [ ] **Step 5: Three shell traps to check before moving on**

Read the file once more and confirm all three, because each of them silently breaks the container:

1. **Nothing writes to stdout except the `printf ''` and `printf -- '--encoder %s'` lines.** Grep it: `grep -n '^\s*echo\|printf' rootfs/usr/local/bin/handbrake-gpu.sh` — every `echo` must end in `>&2` or sit inside the `hb_write_diag` block that is redirected to `${GPU_LOG}`.
2. **`set -e` and `[ ... ] && cmd`.** A bare `[ x ] && y` that evaluates false is a failing command and kills the script. The file uses `if ... then ... fi` inside every loop for exactly this reason. Do not "simplify" those back.
3. **`enc="$(hb_pick_encoder ...)"` always ends in `|| true`.** Without it, "no encoder found" aborts the script, `init-handbrake` empties `gpu-args` and logs a generic warning, and the user loses the specific explanation.

- [ ] **Step 6: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add rootfs/usr/local/bin/handbrake-gpu.sh
git commit -m "feat: add Intel QSV and AMD VCE branches with live HandBrake encoder detection"
```

If Step 3 ran, make the correction visible instead of burying it in this commit:

```bash
git commit --amend -m "feat: add Intel QSV and AMD VCE branches with live HandBrake encoder detection

Hardware encoder ids are now read from the running HandBrakeCLI instead of the
build-time --help dump. libhb filters hardware encoders by live availability, so
the dump recorded during docker build never lists one, and the NVENC lookup that
read it could never match."
```

---

### Task 7: Offline verification of the rewritten script

**Files:**
- Modify/Create: none.

**Interfaces:**
- Consumes: the script from Task 6.
- Produces: the guarantee that CI's shellcheck job stays green.

- [ ] **Step 1: Parse and lint**

```bash
cd /d/nextcloud/it/github/handbrake
bash -n rootfs/usr/local/bin/handbrake-gpu.sh && echo "gpu parses"
shellcheck -S warning -x -e SC1091 rootfs/usr/local/bin/handbrake-gpu.sh && echo "shellcheck OK"
```

Expected:

```
gpu parses
shellcheck OK
```

- [ ] **Step 2: The `none` path must still print nothing on stdout**

This is the exact check Plan 1 used, and it must keep working on the dev box (no `/run/handbrake`, no `HandBrakeCLI`):

```bash
cd /d/nextcloud/it/github/handbrake
out=$(bash rootfs/usr/local/bin/handbrake-gpu.sh none 2>/dev/null || true)
echo "gpu args for 'none' = '${out}'"
err=$(bash rootfs/usr/local/bin/handbrake-gpu.sh none 2>&1 >/dev/null || true)
echo "${err}"
```

Expected:

```
gpu args for 'none' = ''
handbrake-gpu.sh: line 282: /run/handbrake/gpu-vendor: No such file or directory
[handbrake-gpu] GPU acceleration: none — software encoding (x264/x265)
```

The middle line only appears **on a dev box**, where `/run/handbrake` does not
exist: bash reports a failed output redirection before the `2>/dev/null` on that
same line takes effect. It is Plan 1's line unchanged, the directory always
exists inside the container, and the `|| true` keeps it harmless. Do not "fix"
it here; it would only add diff noise against Plan 1.

The decisive part of this check is `gpu args for 'none' = ''`. The `none` branch
must **not** call `HandBrakeCLI`, so this stays fast and silent even where
HandBrake is not installed.

- [ ] **Step 3: An unknown vendor must degrade to `none`**

```bash
cd /d/nextcloud/it/github/handbrake
out=$(bash rootfs/usr/local/bin/handbrake-gpu.sh banana 2>/dev/null || true)
echo "args='${out}'"
bash rootfs/usr/local/bin/handbrake-gpu.sh banana 2>&1 >/dev/null | head -n 2
```

Expected: `args=''`, a first line containing `unrecognised GPU_VENDOR='banana'`, and the `none` decision line last (with the same harmless `/run/handbrake/gpu-vendor` redirection message in between on a dev box).

- [ ] **Step 4: Run the full lint chain**

```bash
cd /d/nextcloud/it/github/handbrake
just check
```

Expected: ends with `All lint checks passed.`

No commit for this task; nothing changed.

---

### Task 8: Container verification — `GPU_VENDOR=intel` without an Intel GPU

**This is the task that carries the honesty of the whole plan.** The success path cannot be exercised here. The failure path can, must, and is the one that every user without Intel hardware will meet.

**Files:**
- Modify/Create: none.

**Interfaces:**
- Consumes: an image built from the current tree.
- Produces: the exact log strings Task 10's CI assertions grep for and Task 13's README quotes.

- [ ] **Step 1: Build and boot with `GPU_VENDOR=intel`**

```bash
cd /d/nextcloud/it/github/handbrake
docker build -t handbrake:gpu .
docker rm -f hb-intel 2>/dev/null || true
docker run -d --name hb-intel -e GPU_VENDOR=intel handbrake:gpu
sleep 45
docker ps --filter name=hb-intel --format '{{.Names}} {{.Status}}'
```

Expected: the container is `Up`. If it exited immediately, check `docker logs hb-intel` for `s6-rc: fatal` — that would mean the Task 5 dependency edge created a cycle or named a service that does not exist.

- [ ] **Step 2: The seam produced empty args and said why**

```bash
docker exec hb-intel cat /run/handbrake/gpu-vendor; echo
echo "gpu-args='$(docker exec hb-intel cat /run/handbrake/gpu-args)'"
docker logs hb-intel 2>&1 | grep '\[handbrake-gpu\]'
```

Expected:

```
intel
gpu-args=''
```

and log lines matching:

```
[handbrake-gpu] WARNING: GPU_VENDOR=intel, but no DRM render node (/dev/dri/renderD*) is visible in this container.
[handbrake-gpu] WARNING: Pass the iGPU through: Unraid adds '--device=/dev/dri' under Extra Parameters, plain docker run takes '--device /dev/dri'.
[handbrake-gpu] WARNING: The host also needs the i915 (or xe) kernel driver loaded.
[handbrake-gpu] WARNING: Falling back to software encoding.
```

**Cannot verify the success path without Intel hardware.** What is verified instead: the fallback is silent-failure-free (it names the cause and the fix), and `gpu-args` is empty so `handbrake-watch.sh` builds an unmodified software command line.

- [ ] **Step 3: The diagnostics file exists and is readable by the user**

```bash
docker exec hb-intel ls -l /config/handbrake-gpu.log
docker exec hb-intel head -n 30 /config/handbrake-gpu.log
```

Expected: mode `-rw-r--r--`, owner matching `PUID`/`PGID` (`abc` by default), and a report whose `--- /dev/dri ---` section says the directory does not exist, whose `--- encoders HandBrakeCLI offers HERE ---` section lists software encoders only, and whose `vainfo` section reports that it could not open a device.

- [ ] **Step 4: Conversions still work, in software**

```bash
ffmpeg -v error -y -f lavfi -i testsrc=size=320x240:rate=15:duration=2 \
       -c:v libx264 -pix_fmt yuv420p /tmp/hb-gpu-smoke.mkv
docker cp /tmp/hb-gpu-smoke.mkv hb-intel:/watch/hb-gpu-smoke.mkv
docker exec hb-intel chown abc:abc /watch/hb-gpu-smoke.mkv
for i in $(seq 1 120); do
  docker exec hb-intel test -s /output/hb-gpu-smoke.mp4 2>/dev/null && { echo "converted after ${i}s"; break; }
  sleep 1
done
docker exec hb-intel grep -m1 'HandBrakeCLI' /config/handbrake-watch.log
```

Expected: `converted after <n>s`, and the logged command line contains **no** `--encoder` argument. That proves the empty `gpu-args` really did splice as nothing.

- [ ] **Step 5: Pass a fake render node through and watch the second failure mode**

The "device present but HandBrake still offers no QSV encoder" branch is reachable without Intel hardware by faking a render node:

```bash
docker rm -f hb-intel2 2>/dev/null || true
docker run -d --name hb-intel2 -e GPU_VENDOR=intel handbrake:gpu
sleep 10
docker exec hb-intel2 sh -c 'mkdir -p /dev/dri && : > /dev/dri/renderD128'
docker exec hb-intel2 sh -c '/usr/local/bin/handbrake-gpu.sh intel > /tmp/args 2>/tmp/err; echo "args=[$(cat /tmp/args)]"; cat /tmp/err'
```

Expected: `args=[]`, and the second-mode warnings:

```
[handbrake-gpu] WARNING: GPU_VENDOR=intel and /dev/dri/renderD128 exists, but HandBrakeCLI does not offer qsv_h264 on this machine.
[handbrake-gpu] WARNING:   * the GPU is not an Intel one, or is older than the oneVPL GPU runtime supports
[handbrake-gpu] WARNING:   * the container user cannot use /dev/dri/renderD128 (check 'runtime user' in /config/handbrake-gpu.log)
[handbrake-gpu] WARNING:   * this is arm64 — Intel Quick Sync is x86-64 only
```

(The fake node is a regular file, so libva cannot open it — which is precisely the condition being exercised.)

- [ ] **Step 6: Clean up**

```bash
docker rm -f hb-intel hb-intel2
rm -f /tmp/hb-gpu-smoke.mkv
```

No commit for this task; nothing changed.

---

### Task 9: Container verification — `GPU_VENDOR=amd` without an AMD GPU

**Files:**
- Modify/Create: none.

**Interfaces:**
- Consumes: `handbrake:gpu` from Task 8.
- Produces: the second exact message set Task 10 asserts and Task 13 quotes.

- [ ] **Step 1: Boot with `GPU_VENDOR=amd`**

```bash
cd /d/nextcloud/it/github/handbrake
docker rm -f hb-amd 2>/dev/null || true
docker run -d --name hb-amd -e GPU_VENDOR=amd handbrake:gpu
sleep 45
echo "gpu-vendor=$(docker exec hb-amd cat /run/handbrake/gpu-vendor)"
echo "gpu-args='$(docker exec hb-amd cat /run/handbrake/gpu-args)'"
docker logs hb-amd 2>&1 | grep '\[handbrake-gpu\]'
```

Expected: `gpu-vendor=amd`, `gpu-args=''`, and the no-render-node warning set with the amdgpu wording.

- [ ] **Step 2: Exercise the "device present, no AMD encoder, no AMF runtime" message**

```bash
docker exec hb-amd sh -c 'mkdir -p /dev/dri && : > /dev/dri/renderD128'
docker exec hb-amd sh -c '/usr/local/bin/handbrake-gpu.sh amd > /tmp/args 2>/tmp/err; echo "args=[$(cat /tmp/args)]"; cat /tmp/err'
```

Expected: `args=[]` and

```
[handbrake-gpu] WARNING: GPU_VENDOR=amd and /dev/dri/renderD128 exists, but HandBrakeCLI offers neither vce_h264 nor vaapi_h264 here.
[handbrake-gpu] WARNING: AMD's AMF runtime (libamfrt64.so*) is not reachable in this container, and Ubuntu does not build
[handbrake-gpu] WARNING: HandBrake with --enable-vce either, so this image has no AMD hardware encoder at all.
[handbrake-gpu] WARNING: The README's Hardware Encoding section explains what AMD hardware encoding needs.
```

- [ ] **Step 3: Exercise the other explanation branch by faking the AMF runtime**

```bash
docker exec hb-amd sh -c ': > /usr/lib/x86_64-linux-gnu/libamfrt64.so.1'
docker exec hb-amd sh -c '/usr/local/bin/handbrake-gpu.sh amd 2>&1 >/dev/null | grep AMF'
```

Expected:

```
[handbrake-gpu] WARNING: AMD's AMF runtime IS reachable, so this HandBrakeCLI was simply not built with --enable-vce.
```

This proves the branch tells a user with the runtime installed something different from a user without it, which is the difference between "install the runtime" and "build the variant image".

**Cannot verify the success path without AMD hardware, an RDNA1/RDNA2 GPU, and AMD's proprietary AMF runtime.** What is verified instead: both diagnoses are reachable, correct, and mutually exclusive, and neither ever emits an encoder argument that would make HandBrake silently encode on the CPU while claiming GPU acceleration.

- [ ] **Step 4: Clean up**

```bash
docker rm -f hb-amd
```

No commit for this task; nothing changed.

---

### Task 10: CI — assert the seam and the fallback logic

CI has no GPU, so it cannot prove hardware encoding. It can prove the two things that actually regress: the vendor runtime is in the image, and an impossible `GPU_VENDOR` degrades cleanly instead of poisoning the HandBrake command line.

**Files:**
- Modify: `d:\nextcloud\it\github\handbrake\.github\workflows\build.yml`

**Interfaces:**
- Consumes: the log strings verified in Tasks 8 and 9.
- Produces: a gate that fails if a future change starts emitting arguments on a GPU-less machine.

- [ ] **Step 1: Append the assertion block to the smoke step**

In `.github/workflows/build.yml`, inside the step `Smoke test — ${{ matrix.arch }} must boot, stay up and transcode`, insert this block **immediately after** the `echo "== dark theme =="` assertions and **before** `echo "== HandBrake GUI is up and STAYS up =="`. If Plan 2 already added a GPU block there, append these lines to the end of that block rather than adding a second one.

```bash
          echo "== GPU seam: the default must be software encoding =="
          vend=$(docker exec "$name" cat /run/handbrake/gpu-vendor 2>/dev/null || echo MISSING)
          args=$(docker exec "$name" cat /run/handbrake/gpu-args 2>/dev/null || echo MISSING)
          echo "gpu-vendor='${vend}' gpu-args='${args}'"
          [ "$vend" = "none" ] || fail "gpu-vendor is '${vend}', expected 'none' by default"
          [ -z "$args" ]       || fail "gpu-args is '${args}', expected empty by default"

          if [ "${{ matrix.arch }}" = "amd64" ]; then
            echo "== GPU seam: the Intel QSV runtime must be in the amd64 image =="
            docker run --rm --entrypoint sh "$img" -c \
              'test -e /usr/lib/x86_64-linux-gnu/dri/iHD_drv_video.so' \
              || fail "iHD_drv_video.so is missing from the amd64 image"
            docker run --rm --entrypoint sh "$img" -c \
              'ls /usr/lib/x86_64-linux-gnu/libmfx-gen.so.1.2* >/dev/null 2>&1' \
              || fail "the oneVPL GPU runtime (libmfx-gen) is missing from the amd64 image"
            docker run --rm --entrypoint sh "$img" -c 'command -v vainfo >/dev/null' \
              || fail "vainfo is missing from the amd64 image"
          else
            echo "== GPU seam: QSV runtime is correctly absent on ${{ matrix.arch }} =="
          fi

          # No CI runner has a GPU, so only the fallback path is reachable here.
          # That is the path every user without the matching hardware hits, and a
          # regression in it would splice a bogus argument into every conversion.
          for v in intel amd; do
            echo "== GPU seam: GPU_VENDOR=${v} without a GPU must fall back loudly =="
            docker rm -f "hb-gpu-${v}" >/dev/null 2>&1 || true
            docker run -d --name "hb-gpu-${v}" -e "GPU_VENDOR=${v}" "$img" >/dev/null
            deadline=$((SECONDS + 180))
            seen=0
            while [ "$SECONDS" -lt "$deadline" ]; do
              if docker exec "hb-gpu-${v}" test -f /run/handbrake/gpu-args 2>/dev/null; then seen=1; break; fi
              sleep 2
            done
            if [ "$seen" -ne 1 ]; then
              docker logs "hb-gpu-${v}" 2>&1 | tail -n 60
              docker rm -f "hb-gpu-${v}" >/dev/null 2>&1 || true
              fail "GPU_VENDOR=${v}: /run/handbrake/gpu-args was never written"
            fi
            a=$(docker exec "hb-gpu-${v}" cat /run/handbrake/gpu-args)
            w=$(docker logs "hb-gpu-${v}" 2>&1 | grep -c "\[handbrake-gpu\] WARNING: GPU_VENDOR=${v}" || true)
            d=$(docker exec "hb-gpu-${v}" test -s /config/handbrake-gpu.log && echo yes || echo no)
            echo "GPU_VENDOR=${v}: args='${a}' warnings=${w} diag=${d}"
            docker rm -f "hb-gpu-${v}" >/dev/null 2>&1 || true
            [ -z "$a" ]      || fail "GPU_VENDOR=${v} produced args '${a}' on a GPU-less runner; expected empty"
            [ "$w" -ge 1 ]   || fail "GPU_VENDOR=${v} fell back without explaining why"
            [ "$d" = "yes" ] || fail "GPU_VENDOR=${v} wrote no /config/handbrake-gpu.log diagnostics"
          done
```

- [ ] **Step 2: Verify the workflow still parses**

```bash
cd /d/nextcloud/it/github/handbrake
python -c "import yaml; yaml.safe_load(open('.github/workflows/build.yml')); print('build.yml OK')"
```

Expected: `build.yml OK`.

- [ ] **Step 3: Commit and let CI run it**

```bash
cd /d/nextcloud/it/github/handbrake
git add .github/workflows/build.yml
git commit -m "ci: assert the GPU seam falls back cleanly and the QSV runtime ships on amd64"
git push origin main
gh run watch "$(gh run list --workflow=build.yml --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
```

Expected: both arch jobs green. In the amd64 log:

```
gpu-vendor='none' gpu-args=''
GPU_VENDOR=intel: args='' warnings=1 diag=yes
GPU_VENDOR=amd: args='' warnings=1 diag=yes
```

and in the arm64 log the same, plus `== GPU seam: QSV runtime is correctly absent on arm64 ==`.

(`warnings=1` because only the first line of each fallback repeats the
`GPU_VENDOR=<vendor>` text the grep anchors on; the follow-up lines explaining
the fix do not. The assertion is `>= 1`, so rewording never breaks the gate.)

---

### Task 11: Optional AMD VCE variant image

**Read this before starting.** This task adds a second, *optional* Dockerfile. It is deliberately **not** wired into the default `Dockerfile`, **not** added to the CI build matrix and **not** published to any registry. Reasons, all of them established in the research section:

- It compiles HandBrake and its whole contrib tree from source. Expect **30 to 60 minutes** on 8 cores and several GB of scratch space. Putting that into the per-push CI matrix would roughly triple build time on every commit, for a feature that cannot be tested there.
- AMF is x86-64 only, so it would have to be excluded from the arm64 job anyway, splitting the "one Dockerfile, two arches" model.
- The resulting binary still needs AMD's proprietary `libamfrt64.so.1`, which cannot be shipped and which only covers RDNA1/RDNA2.

What it *does* buy: the only existing way to get `vce_*` encoders, for users who have an RX 5000/6000 series card and can install `amf-amdgpu-pro` on the host. Everything else about the container stays identical, because the GPU seam only ever feeds `HandBrakeCLI`.

**Files:**
- Create: `d:\nextcloud\it\github\handbrake\Dockerfile.vce`
- Modify: `d:\nextcloud\it\github\handbrake\.gitattributes`
- Modify: `d:\nextcloud\it\github\handbrake\justfile`

**Interfaces:**
- Consumes: the published/local base image tag, HandBrake's own documented Ubuntu build dependencies.
- Produces: an image whose `/usr/local/bin/HandBrakeCLI` has the AMF code path, and whose `/usr/local/share/handbrake-*.txt` dumps are re-recorded from that binary so `handbrake-gpu.sh` needs no change at all.

- [ ] **Step 1: Pin `Dockerfile*` to LF**

Multi-line `RUN` blocks with CRLF break inside the image. Add to `.gitattributes`, after the `rootfs/**` line:

```gitattributes
# Dockerfiles carry multi-line RUN blocks; a CRLF checkout breaks the shell
# inside them.
Dockerfile* text eol=lf
```

- [ ] **Step 2: Write `Dockerfile.vce`**

`d:\nextcloud\it\github\handbrake\Dockerfile.vce`:

```dockerfile
# syntax=docker/dockerfile:1.26
#
# OPTIONAL AMD VCE (AMF) VARIANT — build it yourself, it is not published.
# -----------------------------------------------------------------------
# Why this file exists at all:
#   Ubuntu does not build HandBrake with --enable-vce (upstream enables it only
#   for Windows hosts), so the stock image has no AMD hardware encoder. This
#   variant rebuilds ONLY HandBrakeCLI from source with --enable-vce and drops it
#   over the stock binary. The GTK GUI is untouched and stays software-only; the
#   GPU seam only ever feeds HandBrakeCLI, so that is exactly the surface the
#   watch-folder converter uses.
#
# What this variant still does NOT give you:
#   AMD's AMF runtime (libamfrt64.so.1) is proprietary, is not in Ubuntu, and is
#   not ours to redistribute. Install amf-amdgpu-pro on the host and bind-mount
#   the library in, see the README. The last release of that package supports
#   RDNA1 and RDNA2 only. On RDNA3/RDNA4 this variant will not help you.
#
# Cost: a full HandBrake contrib build, 30-60 minutes on 8 cores, amd64 only.
#
#   docker build -f Dockerfile.vce -t handbrake:vce .
#
ARG BASE_IMAGE=ghcr.io/junkerderprovinz/handbrake:latest
ARG HANDBRAKE_TAG=1.11.2

# The builder is the SAME base image as the runtime stage, so glibc and every
# system library the new binary links against are identical by construction.
FROM ${BASE_IMAGE} AS builder
ARG HANDBRAKE_TAG

RUN set -eux; \
    [ "$(dpkg --print-architecture)" = "amd64" ] \
        || { echo "ERROR: the VCE variant is amd64 only (AMF is x86-64 only)"; exit 1; }

# HandBrake's own documented Ubuntu build dependencies.
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        autoconf automake build-essential cmake git libass-dev libbz2-dev \
        libfontconfig-dev libfreetype-dev libfribidi-dev libharfbuzz-dev \
        libjansson-dev liblzma-dev libmp3lame-dev libnuma-dev libogg-dev \
        libopus-dev libsamplerate0-dev libspeex-dev libtheora-dev libtool \
        libtool-bin libturbojpeg0-dev libvorbis-dev libx264-dev libxml2-dev \
        libvpx-dev m4 make meson nasm ninja-build patch pkg-config tar \
        zlib1g-dev curl libssl-dev clang python3

RUN set -eux; \
    git clone --depth 1 --branch "${HANDBRAKE_TAG}" \
        https://github.com/HandBrake/HandBrake.git /src

WORKDIR /src

# --disable-gtk : CLI only. Building the GTK4 GUI here would double the build
#                 time for a binary this variant does not replace.
# --enable-vce  : the point of the file. HandBrake's build system downloads the
#                 MIT-licensed AMF HEADERS (AMF-headers-v1.5.0.tar.gz, sha256
#                 verified by contrib/amf/module.defs) and builds its bundled
#                 FFmpeg with --enable-amf plus the h264_amf/hevc_amf/av1_amf
#                 encoders. No proprietary binary is fetched or shipped.
RUN set -eux; \
    ./configure --launch-jobs="$(nproc)" --launch --disable-gtk --enable-vce; \
    test -x /src/build/HandBrakeCLI

# Prove the AMF code path is compiled in WITHOUT owning an AMD GPU: the AMF
# component id libhb passes to check_component_available() is a wide-char
# literal that only lands in the binary when HB_PROJECT_FEATURE_VCE was on
# (libhb/vce_common.c). wchar_t is 4 bytes on Linux, hence `strings -e L`.
RUN set -eux; \
    strings -e L /src/build/HandBrakeCLI | grep -qx 'AMFVideoEncoderVCE_AVC' \
        || { echo "ERROR: the built HandBrakeCLI contains no AMF/VCE code path"; exit 1; }; \
    echo "handbrake-vce: AMF/VCE code path confirmed in the binary"

# Work out exactly which runtime packages the new binary needs, instead of
# guessing a package list. Builder and runtime share a base, so the mapping is
# valid in the final stage.
RUN set -eux; \
    ldd /src/build/HandBrakeCLI | awk '/=> \//{print $3}' | sort -u \
      | xargs -r dpkg -S 2>/dev/null | cut -d: -f1 | sort -u > /src/runtime-deps.txt; \
    echo "handbrake-vce: runtime packages ->"; cat /src/runtime-deps.txt

# ---------------------------------------------------------------------------
# Runtime stage: the stock image plus one binary. Nothing from the builder's
# 2+ GB of toolchain and sources is carried over.
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE}

COPY --from=builder /src/build/HandBrakeCLI /usr/local/bin/HandBrakeCLI
COPY --from=builder /src/runtime-deps.txt   /tmp/runtime-deps.txt

# mesa-va-drivers is the radeonsi VA-API driver. It is NOT in the stock image
# (which would pay for it on every pull for no gain), but here it is what makes
# the vainfo section of /config/handbrake-gpu.log say anything useful on an AMD
# box, and it is the prerequisite for HandBrake's upcoming VA-API encoders.
#
# xargs -a feeds the computed package list as extra arguments, which keeps the
# unquoted $(...) that shellcheck/hadolint would reject out of the RUN line.
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive xargs -a /tmp/runtime-deps.txt \
        apt-get install -y --no-install-recommends mesa-va-drivers vainfo; \
    rm -f /tmp/runtime-deps.txt; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# /usr/local/bin precedes /usr/bin on PATH, so the watch daemon's bare
# "HandBrakeCLI" resolves to this build. Fail loudly if that ever stops being
# true, and re-record the capability dumps from the NEW binary so every
# consumer of them describes this image and not the stock one.
RUN set -eux; \
    [ "$(command -v HandBrakeCLI)" = "/usr/local/bin/HandBrakeCLI" ] \
        || { echo "ERROR: $(command -v HandBrakeCLI) shadows the VCE build"; exit 1; }; \
    if ldd /usr/local/bin/HandBrakeCLI | grep 'not found'; then \
        echo "ERROR: the VCE build is missing shared libraries (listed above)"; exit 1; \
    fi; \
    HandBrakeCLI --version     > /usr/local/share/handbrake-version.txt 2>&1; \
    HandBrakeCLI --help        > /usr/local/share/handbrake-cli-help.txt 2>&1; \
    HandBrakeCLI --preset-list > /usr/local/share/handbrake-preset-list.txt 2>&1; \
    grep -q 'Very Fast 1080p30' /usr/local/share/handbrake-preset-list.txt \
        || { echo "ERROR: the default AUTOMATED_CONVERSION_PRESET is missing from this build"; exit 1; }; \
    echo "handbrake-vce: $(head -n 1 /usr/local/share/handbrake-version.txt)"

LABEL org.opencontainers.image.title="handbrake-vce"
LABEL org.opencontainers.image.description="HandBrake for Unraid with a HandBrakeCLI built with --enable-vce (AMD VCE via AMF). Needs AMD's proprietary AMF runtime mounted in from the host."
```

- [ ] **Step 3: Add the `justfile` recipe**

Append to `justfile`, after the `smoke` recipe:

```makefile
# Build the OPTIONAL AMD VCE (AMF) variant against the local image.
# Long build (30-60 min), amd64 only, never published. See Dockerfile.vce.
build-vce: build
    docker build -f Dockerfile.vce -t handbrake:vce \
      --build-arg BASE_IMAGE=handbrake:smoke-amd64 .
```

- [ ] **Step 4: Lint**

```bash
cd /d/nextcloud/it/github/handbrake
hadolint Dockerfile.vce --ignore DL3008 --ignore DL3009 --ignore DL3003 --ignore DL3007
just --list | grep build-vce
git check-attr text eol -- Dockerfile.vce
```

Expected: hadolint silent, the recipe listed, and `Dockerfile.vce: eol: lf`.

The two extra ignores are deliberate and specific: `DL3003` objects to changing
directory for a build, which is exactly what a source build does; `DL3007`
objects to the `:latest` in the default `BASE_IMAGE`, which is correct here
because the caller pins the base with `--build-arg BASE_IMAGE=...`.

- [ ] **Step 5: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add Dockerfile.vce .gitattributes justfile
git commit -m "feat: add an optional AMD VCE (AMF) build variant, not published and not CI-gated"
```

---

### Task 12: Build the variant and record what it really contains

**Files:**
- Modify: `d:\nextcloud\it\github\handbrake\docs\handbrake-capabilities.md`

**Interfaces:**
- Consumes: `Dockerfile.vce` from Task 11.
- Produces: the recorded evidence Task 13's README links to, and proof that the variant does not bloat the runtime image.

- [ ] **Step 1: Build it (long)**

```bash
cd /d/nextcloud/it/github/handbrake
time docker build -f Dockerfile.vce -t handbrake:vce --build-arg BASE_IMAGE=handbrake:gpu .
```

Expected, in the log:

```
handbrake-vce: AMF/VCE code path confirmed in the binary
handbrake-vce: runtime packages ->
(one Debian package name per line, computed from ldd)
handbrake-vce: HandBrake 1.11.x
```

Record the wall-clock time from `time`; it goes into the README so nobody is surprised.

If `./configure` fails on a contrib download, it is HandBrake's own sha256-verified fetch: re-run the build, and if it keeps failing check whether the tag in `HANDBRAKE_TAG` still exists (`gh api repos/HandBrake/HandBrake/tags --jq '.[].name' | head`). Do not disable the verification.

- [ ] **Step 2: Prove the difference between the two binaries, with no AMD hardware**

```bash
echo -n "stock  libamfrt64 hits: "; docker run --rm --entrypoint sh handbrake:gpu -c \
  'grep -c -a -F "libamfrt64" /usr/bin/HandBrakeCLI || true'
echo -n "variant libamfrt64 hits: "; docker run --rm --entrypoint sh handbrake:vce -c \
  'grep -c -a -F "libamfrt64" /usr/local/bin/HandBrakeCLI || true'
docker run --rm --entrypoint sh handbrake:vce -c 'command -v HandBrakeCLI'
```

Expected: stock `0`, variant `1` or more, and `/usr/local/bin/HandBrakeCLI`.

**Cannot verify that the variant encodes on a GPU.** The authoritative compile-time gate already ran inside the build (`strings -e L ... AMFVideoEncoderVCE_AVC`), which fails the build if the AMF path is absent. This step is the same fact re-checked from outside, plus proof that the override is the binary the watch daemon will call.

- [ ] **Step 3: Record the variant's live encoder list, and explain why `vce_*` is not in it**

```bash
docker run --rm --entrypoint sh handbrake:vce -c \
  "HandBrakeCLI --help 2>/dev/null | awk '/^[[:space:]]*-e, --encoder[[:space:]]/{f=1;next} f&&/^[[:space:]]*-/{f=0} f'"
```

Expected: software encoders only. That is **not** a build failure. libhb hides `vce_*` until `hb_dlopen("libamfrt64.so.1")` succeeds and an AMF component reports caps, neither of which can happen on a machine with no AMD GPU and no AMF runtime.

- [ ] **Step 4: Measure the size cost**

```bash
docker images --format '{{.Repository}}:{{.Tag}}\t{{.Size}}' | grep -E 'handbrake:(pre-gpu|gpu|vce)'
```

Expected: three lines. `vce` is larger than `gpu` by roughly the size of the static `HandBrakeCLI` plus `mesa-va-drivers`, and **not** by the size of the toolchain — if the delta is measured in gigabytes, the multi-stage split is broken and the builder stage is leaking into the final image. Record the real numbers.

- [ ] **Step 5: Append the VCE section to `docs/handbrake-capabilities.md`**

Append, replacing every `<paste ...>`:

````markdown
### Optional VCE build variant (`Dockerfile.vce`)

Recorded on `<paste: date -I>` from `handbrake:vce`, built with
`docker build -f Dockerfile.vce`. Build time on this machine:
`<paste the wall-clock time from Step 1>`. Not published; users build it
themselves.

AMF code path present in the two binaries (`grep -c -a -F libamfrt64`):

```text
stock   /usr/bin/HandBrakeCLI       : <paste>
variant /usr/local/bin/HandBrakeCLI : <paste>
```

Live encoder list inside the variant, on a machine with no AMD GPU:

```text
<paste the output of Step 3>
```

`vce_h264` and friends are absent here **by design**: libhb only lists them once
AMD's proprietary AMF runtime has loaded and an AMF encoder component has
reported its capabilities. On a host with an RDNA1/RDNA2 card and
`amf-amdgpu-pro` installed and mounted in, they appear, and
`rootfs/usr/local/bin/handbrake-gpu.sh` then picks `vce_h264` up without any
code change, because it looks the id up instead of hardcoding it.

Image size:

```text
<paste the output of Step 4>
```
````

- [ ] **Step 6: Verify and commit**

```bash
cd /d/nextcloud/it/github/handbrake
grep -n '<paste' docs/handbrake-capabilities.md && echo "PLACEHOLDERS LEFT — fix them" || echo "no placeholders"
git add docs/handbrake-capabilities.md
git commit -m "docs: record what the optional AMD VCE build variant actually contains"
```

---

### Task 13: README — Hardware Encoding

**Files:**
- Modify: `d:\nextcloud\it\github\handbrake\README.md`

**Interfaces:**
- Consumes: the measured numbers from Tasks 4 and 12, and the exact log lines from Tasks 8 and 9.
- Produces: the user-facing contract. Docker Hub mirrors this text.

- [ ] **Step 1: Establish the NVIDIA merge rule before editing**

```bash
cd /d/nextcloud/it/github/handbrake
sed -n '/^## 8\. Hardware Encoding/,/^## 9\./p' README.md
```

- If that section already documents NVENC (Plan 2 landed), **keep every NVIDIA sentence verbatim**, keep its heading numbering, and merge only the Intel and AMD material below into it: add the two table rows, add `### 8.1`/`### 8.2` after Plan 2's NVIDIA subsection, and renumber Plan 2's subsections so the sequence stays gapless. Plan 2 also rewrote the comparison table in section 1 and added troubleshooting entries to section 11; this plan changes neither, so leave both untouched.
- If it still says "This release ships software encoding only", replace the whole section with Step 2's text and add this literal NVIDIA row to the table, directly under the `none` row: `| \`nvidia\` | not in this release yet | ❌ | — |`.

- [ ] **Step 2: Replace section 8**

````markdown
## 8. Hardware Encoding

Set `GPU_VENDOR` and pass the device through; the watch-folder converter then
adds `--encoder <hardware encoder>` to every job. The GUI is unaffected and
keeps its own encoder dropdown.

| `GPU_VENDOR` | What you need on the host | Works out of the box | Verified by the maintainer |
|---|---|---|---|
| `none` (default) | nothing | ✅ software x264/x265 | ✅ |
| `intel` | `/dev/dri` passthrough, `i915` or `xe` kernel driver | ✅ on amd64 | ❌ no Intel GPU here |
| `amd` | `/dev/dri` passthrough, `amdgpu` kernel driver, a custom image, AMD's AMF runtime | ❌ see below | ❌ no AMD GPU here |

The container never pretends. If the encoder you asked for is not usable it
falls back to software and writes the reason into the container log, plus a full
report to `/config/handbrake-gpu.log`.

### 8.1 Intel Quick Sync (`GPU_VENDOR=intel`)

Requirements on the host:

- The iGPU or Arc card passed into the container. Unraid: add `--device=/dev/dri`
  to *Extra Parameters*. Plain Docker: `--device /dev/dri`.
- The **open-source** `i915` (or `xe`) kernel driver, which every current Linux
  kernel ships. No proprietary driver, no vendor container toolkit, nothing to
  install on the host.

Nothing has to be installed inside the container: the amd64 image already ships
the Intel oneVPL GPU runtime and the iHD VA-API driver.

```sh
docker run -d \
  --name=handbrake \
  --device /dev/dri \
  -e GPU_VENDOR=intel \
  ... \
  ghcr.io/junkerderprovinz/handbrake:latest
```

On the next start the log says which encoder was chosen:

```
[handbrake-gpu] Intel QSV enabled: --encoder qsv_h264 (render node /dev/dri/renderD128)
```

Notes worth knowing:

- The chosen encoder is `qsv_h264`, so the output codec matches what the default
  preset produces and stays as compatible as before. For HEVC, set
  `AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS=--encoder qsv_h265`; custom
  arguments are appended after the automatic ones and always win.
- Hardware *decoding* is not enabled automatically. Add
  `--enable-hw-decoding qsv` to `AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS` if
  you want it.
- Quality is preset-driven and the RF scale is not identical between x264 and
  QSV, so expect a different file size at the same nominal quality.
- Quick Sync is x86-64 only. On arm64 the variable is accepted and ignored, with
  a log line saying so.
- This image ships the runtime that Intel's current oneVPL GPU runtime supports,
  which in practice means Tiger Lake / Xe / Arc and newer. The legacy Media SDK
  runtime that older generations need is no longer in Ubuntu, so a pre-Gen12
  iGPU may report no QSV encoder. The log and `/config/handbrake-gpu.log` say so
  explicitly rather than failing silently.

### 8.2 AMD VCN (`GPU_VENDOR=amd`)

**Honest summary: the stock image cannot do AMD hardware encoding, and this is
not something we can fix from inside the container.** Setting `GPU_VENDOR=amd`
is still worth doing, because it prints the exact reason and keeps converting in
software:

```
[handbrake-gpu] WARNING: GPU_VENDOR=amd and /dev/dri/renderD128 exists, but HandBrakeCLI offers neither vce_h264 nor vaapi_h264 here.
```

Why:

- HandBrake's AMD path on Linux is **VCE through AMD's AMF framework**. Ubuntu
  does not build HandBrake with `--enable-vce`, and upstream enables it by
  default only for Windows builds, so the packaged `HandBrakeCLI` contains no
  AMD encoder at all.
- Even a rebuilt binary needs AMD's proprietary AMF runtime
  (`libamfrt64.so.1`, from the `amf-amdgpu-pro` package on `repo.radeon.com`).
  That library is not redistributable here, and AMD no longer ships AMF as part
  of the Linux driver stack. The last release covers **RDNA1 and RDNA2 only**
  (RX 5000 and RX 6000 series).
- HandBrake 1.11 has no VA-API fallback for AMD. VA-API encoders exist in
  upstream's development branch, so this is expected to change; when a base
  image update brings them, this container picks them up automatically, because
  it asks HandBrake which encoders exist instead of hardcoding names.

If you have an RX 5000/6000 series card and want to try anyway:

1. Install `amf-amdgpu-pro` on the host per AMD's instructions, and find the
   library: `dpkg -L amf-amdgpu-pro | grep amfrt`.
2. Build the variant image (amd64 only, expect 30 to 60 minutes):
   ```sh
   docker build -f Dockerfile.vce -t handbrake:vce .
   ```
3. Run it with the runtime mounted in and the device passed through:
   ```sh
   docker run -d \
     --name=handbrake \
     --device /dev/dri \
     -v /opt/amdgpu-pro/lib/x86_64-linux-gnu/libamfrt64.so.1:/usr/lib/x86_64-linux-gnu/libamfrt64.so.1:ro \
     -e GPU_VENDOR=amd \
     ... \
     handbrake:vce
   ```
4. Check the log for `AMD hardware encoding enabled: --encoder vce_h264`. If it
   is not there, `/config/handbrake-gpu.log` says which piece is missing.

One more caveat, because it has caught people out: on cards newer than RDNA2 the
AMF runtime can report encoder capabilities and still encode on the CPU. If the
transcode runs at software speed, that is what is happening; there is no fix
available today other than waiting for HandBrake's VA-API encoders.

### 8.3 What the container tells you

Every non-`none` `GPU_VENDOR` writes `/config/handbrake-gpu.log` on each start:
the render nodes and their permissions, the groups the container user is in, the
kernel driver behind each node, the encoders HandBrake really offers on your
machine, and `vainfo` / `vpl-inspect` output.

```sh
docker exec handbrake cat /config/handbrake-gpu.log
```

That file is the first thing to read when hardware encoding does not engage, and
the one thing to attach to a report.
````

- [ ] **Step 3: Update the `GPU_VENDOR` row in section 5**

In the Configuration table, replace the `GPU_VENDOR` row with:

```markdown
| `GPU_VENDOR` | `none` | `none`, `intel`, `amd` (and `nvidia`) — see [Hardware Encoding](#8-hardware-encoding) |
```

If Plan 2 has landed and already rewrote this row, leave its wording alone and
only make sure `intel` and `amd` are listed.

- [ ] **Step 4: Verify the README renders and the anchors still work**

```bash
cd /d/nextcloud/it/github/handbrake
grep -n '^## ' README.md
grep -c '](#8-hardware-encoding)' README.md
```

Expected: the thirteen top-level sections are unchanged and still numbered 1-13 (Hardware Encoding stays section 8, so no anchor in the table of contents moves), and the anchor is referenced at least twice.

- [ ] **Step 5: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add README.md
git commit -m "docs: document Intel QSV and the AMD VCE situation in the README"
```

---

### Task 14: README + issue form — Community Verification

The maintainer has no Intel and no AMD GPU. Saying "reports welcome" in passing is not a plan; this task makes the ask explicit and gives reporters a form that collects the one file that answers most questions.

**Files:**
- Modify: `d:\nextcloud\it\github\handbrake\README.md`
- Create: `d:\nextcloud\it\github\handbrake\.github\ISSUE_TEMPLATE\hardware-report.yml`
- Create: `d:\nextcloud\it\github\handbrake\.github\ISSUE_TEMPLATE\config.yml`

**Interfaces:**
- Consumes: `/config/handbrake-gpu.log` (Task 6).
- Produces: the `hardware-report` label and a form-driven report channel.

- [ ] **Step 1: Add the Community Verification subsection to the README**

Append to section 8, after `### 8.3 What the container tells you`:

````markdown
### 8.4 Help us verify this (please)

**Intel QSV and AMD VCN in this image are implemented against Intel's, AMD's and
HandBrake's own documentation. They have not been verified on real hardware by
the maintainer, because there is no Intel and no AMD GPU here to test on.** The
NVIDIA path is the only one with a card behind it. Every part that could be
tested without the hardware has been: the runtime libraries are asserted in CI,
the encoder selection logic is exercised in CI on GPU-less runners, and the
fallback path is checked on both architectures.

What is missing is somebody with the actual hardware saying whether a file comes
out the other end faster.

If you have an Intel iGPU or Arc card, or an AMD Radeon:

1. Set `GPU_VENDOR=intel` or `GPU_VENDOR=amd` and pass `--device /dev/dri`.
2. Convert one file.
3. Open a report with the hardware report form:
   [**Report your GPU result**](https://github.com/junkerderprovinz/handbrake/issues/new?template=hardware-report.yml)

Attach `/config/handbrake-gpu.log` and say whether it worked. A report that says
"it does not work" is just as useful as one that says it does, and the log file
usually contains the reason.
````

- [ ] **Step 2: Write the issue form**

`d:\nextcloud\it\github\handbrake\.github\ISSUE_TEMPLATE\hardware-report.yml` (issue prose: no em dashes anywhere in this file):

```yaml
name: GPU hardware report
description: Tell us whether Intel QSV or AMD hardware encoding worked on your machine
title: "[hardware] "
labels: ["hardware-report"]
body:
  - type: markdown
    attributes:
      value: |
        Thanks for helping out. Intel QSV and AMD VCN in this image are built
        against the vendors' documentation but have never been run on real
        Intel or AMD hardware by the maintainer, so your report is the only way
        this gets confirmed. Reports that say it did not work are just as
        welcome as the ones that say it did.
  - type: dropdown
    id: vendor
    attributes:
      label: Which GPU_VENDOR did you set?
      options:
        - intel
        - amd
        - nvidia
    validations:
      required: true
  - type: dropdown
    id: result
    attributes:
      label: Did hardware encoding engage?
      options:
        - "Yes, and it was clearly faster"
        - "Yes, but it was not faster"
        - "No, it fell back to software encoding"
        - "No, conversions failed"
    validations:
      required: true
  - type: input
    id: gpu
    attributes:
      label: GPU model
      placeholder: "Intel Arc A380 / Intel UHD 770 / Radeon RX 6700 XT"
    validations:
      required: true
  - type: input
    id: host
    attributes:
      label: Host OS and kernel
      placeholder: "Unraid 7.x, kernel 6.x"
    validations:
      required: true
  - type: input
    id: version
    attributes:
      label: Image version
      description: "Output of: docker exec handbrake cat /etc/handbrake-build"
      placeholder: "sha=abc1234 date=..."
    validations:
      required: true
  - type: textarea
    id: diag
    attributes:
      label: GPU diagnostics
      description: "Output of: docker exec handbrake cat /config/handbrake-gpu.log"
      render: text
    validations:
      required: true
  - type: textarea
    id: log
    attributes:
      label: Container log lines
      description: "Output of: docker logs handbrake 2>&1 | grep handbrake-gpu"
      render: text
    validations:
      required: true
  - type: textarea
    id: notes
    attributes:
      label: Anything else
      description: Speed before and after, encoder you used, anything odd.
    validations:
      required: false
  - type: checkboxes
    id: privacy
    attributes:
      label: Before you post
      options:
        - label: I checked the pasted output for anything private, such as file names or IP addresses.
          required: true
```

- [ ] **Step 3: Keep blank issues available**

`d:\nextcloud\it\github\handbrake\.github\ISSUE_TEMPLATE\config.yml`:

```yaml
blank_issues_enabled: true
contact_links:
  - name: Question or support
    url: https://github.com/junkerderprovinz/handbrake/discussions
    about: For usage questions that are not a bug report.
```

- [ ] **Step 4: Create the label and validate the form**

```bash
cd /d/nextcloud/it/github/handbrake
gh label create hardware-report --color 1d99f3 --description "Report from a user with real GPU hardware" 2>/dev/null \
  || echo "label already exists"
python -c "import yaml; yaml.safe_load(open('.github/ISSUE_TEMPLATE/hardware-report.yml')); yaml.safe_load(open('.github/ISSUE_TEMPLATE/config.yml')); print('issue templates OK')"
grep -n '—' .github/ISSUE_TEMPLATE/hardware-report.yml && echo "EM DASH FOUND — remove it" || echo "no em dashes (correct)"
```

Expected: `issue templates OK` and `no em dashes (correct)`.

- [ ] **Step 5: Commit and confirm the form renders**

```bash
cd /d/nextcloud/it/github/handbrake
git add README.md .github/ISSUE_TEMPLATE/hardware-report.yml .github/ISSUE_TEMPLATE/config.yml
git commit -m "docs: ask for community hardware verification and add a GPU report form"
git push origin main
```

Then open `https://github.com/junkerderprovinz/handbrake/issues/new/choose` in a
clean browser. Expected: "GPU hardware report" is offered alongside a blank
issue, and every field above appears. GitHub refuses to render a malformed form,
so a missing form means the YAML is wrong, not that the cache is stale.

---

### Task 15: Documentation consistency pass

Plan 1's repo guide says GPU support does not exist. After this plan that is wrong in three places, and a wrong repo guide sends the next contributor down the path this plan exists to prevent.

**Files:**
- Modify: `d:\nextcloud\it\github\handbrake\CLAUDE.md`
- Modify: `d:\nextcloud\it\github\handbrake\rootfs\etc\s6-overlay\s6-rc.d\init-handbrake\run` (comment only)

**Interfaces:**
- Consumes: everything above.
- Produces: an accurate guide for whoever implements Plan 4.

- [ ] **Step 1: Replace the GPU bullet under "Conventions / gotchas"**

Replace the bullet starting `- **GPU support lives in \`handbrake-gpu.sh\` only.**` with:

```markdown
- **GPU support lives in `handbrake-gpu.sh` only.** It resolves `GPU_VENDOR`
  (`none` | `nvidia` | `intel` | `amd`) into the extra `HandBrakeCLI` arguments
  written to `/run/handbrake/gpu-args`, and writes a diagnostics report to
  `/config/handbrake-gpu.log`. **Its stdout is a command line, not a log** —
  every human-readable line goes to stderr, or the text ends up as a
  `HandBrakeCLI` argument.
- **Never read hardware encoder availability from
  `/usr/local/share/handbrake-cli-help.txt`.** libhb lists a hardware encoder
  only when it is compiled in *and* usable on the machine right now
  (`hb_video_encoder_is_enabled()`), and that dump is recorded during
  `docker build` on a GPU-less machine, so it never contains one. Ask the live
  binary, as `abc`, which is what `hb_load_encoders()` does. Details in
  `docs/handbrake-capabilities.md`.
- **Intel QSV is a packaging story, AMD VCE is not.** Ubuntu builds
  `handbrake-cli` with `--enable-qsv` on amd64 (the .deb already depends on
  `libvpl2`), so Intel needs only the oneVPL GPU runtime plus the iHD driver,
  which the Dockerfile installs on amd64. Ubuntu never passes `--enable-vce`, so
  AMD needs a source rebuild (`Dockerfile.vce`, opt-in, not published, not
  CI-gated) plus AMD's proprietary AMF runtime, which cannot ship here.
- **Neither Intel nor AMD hardware encoding has been verified on real hardware.**
  Do not add a claim that it has. CI asserts the runtime libraries and the
  fallback logic only.
```

- [ ] **Step 2: Update the Layout section**

In the `rootfs/usr/local/bin/` bullet nothing changes. Add, after the
`Dockerfile` bullet:

```markdown
- `Dockerfile.vce` — optional AMD VCE variant. Rebuilds only `HandBrakeCLI` with
  `--enable-vce` on top of the published image, re-records the capability dumps
  from the new binary, and is built by users, not by CI (`just build-vce`).
```

- [ ] **Step 3: Correct the stale comment in `init-handbrake/run`**

This is a **comment-only** edit to a file Plan 1 owns, with no behaviour change,
because the comment now states the opposite of what the container does. In
`rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/run`, replace

```bash
# -- 4) GPU seam --------------------------------------------------------------
# v1 has no GPU acceleration; the seam exists so the watch daemon never needs to
# know about vendors. See handbrake-gpu.sh for the extension point.
```

with

```bash
# -- 4) GPU seam --------------------------------------------------------------
# handbrake-gpu.sh resolves GPU_VENDOR into the extra HandBrakeCLI arguments, so
# the watch daemon never needs to know about vendors. Its stdout lands in
# /run/handbrake/gpu-args verbatim; everything human-readable goes to stderr.
```

If Plan 2 already corrected these lines, leave its wording in place.

- [ ] **Step 4: Verify nothing stale is left anywhere**

```bash
cd /d/nextcloud/it/github/handbrake
grep -rn 'ships none\|ships NO GPU\|has no GPU acceleration\|ships software encoding only\|arrives in a later release' \
  CLAUDE.md README.md Dockerfile rootfs/ \
  && echo "STALE TEXT LEFT — fix it in place" || echo "no stale GPU claims"
```

Expected: `no stale GPU claims`. Every hit is Plan 1 text that this plan has
made false and that must be corrected where it sits, not left for later.

- [ ] **Step 5: Lint what changed and commit**

```bash
cd /d/nextcloud/it/github/handbrake
shellcheck -S warning -x -e SC1091 rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/run && echo "shellcheck OK"
git add CLAUDE.md rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/run
git commit -m "docs: bring the repo guide and the init comments in line with the GPU paths"
```

Expected: `shellcheck OK` (the edit is comment-only, so anything else means a line was mangled).

---

### Task 16: Release notes and version entry

**Files:**
- Create: `d:\nextcloud\it\github\handbrake\.github\release-notes\vX.Y.Z.md` (exact name decided in Step 1)

**Interfaces:**
- Consumes: everything above.
- Produces: the release body `release.yml` publishes.

**Sequencing is jdp's decision, not this plan's.** Plan 2 (NVIDIA) and Plan 3 (Intel/AMD) are siblings; the GPU work can ship as one minor release or as two. Both shapes are written out below in full, so whichever jdp picks is a copy-paste, not a drafting exercise.

- [ ] **Step 1: Ask jdp which shape to use**

Plan 2 ships `v1.1.0`, so the two shapes are concrete. Ask with a popup
(AskUserQuestion), offering exactly these two options:

- **One release (`v1.1.0`)** — fold the Intel/AMD notes into Plan 2's
  `.github/release-notes/v1.1.0.md`, so NVENC, QSV and AMD ship as a single
  "hardware encoding" minor. Use Variant B.
- **Own release (`v1.2.0`)** — Plan 2 already shipped `v1.1.0`; Intel and AMD
  ship separately with their own notes file. Use Variant A.

Also confirm the numbers against what is actually released, because Plan 2's tag
is itself gated on jdp's approval and may not exist yet:

```bash
cd /d/nextcloud/it/github/handbrake
git tag --list 'v*' --sort=-v:refname | head -5
ls -1 .github/release-notes/
```

If Plan 2 has not shipped at all yet, the answer is almost certainly "one
release"; still ask, and use the numbers jdp gives.

- [ ] **Step 2 (Variant A): New notes file**

`d:\nextcloud\it\github\handbrake\.github\release-notes\v1.2.0.md` (substitute
the version jdp chose in Step 1 into the filename):

```markdown
Intel Quick Sync hardware encoding, and an honest answer for AMD. Set `GPU_VENDOR`, pass the GPU through, and the watch-folder converter encodes on the GPU instead of the CPU — or tells you exactly why it cannot.

## ✨ Added

- **Intel Quick Sync (QSV) hardware encoding.** Set `GPU_VENDOR=intel`, pass the iGPU or Arc card through with `--device /dev/dri`, and every watch-folder job is encoded with `qsv_h264` instead of x264. Nothing has to be installed on the host beyond the open-source `i915` kernel driver every current Linux ships, and nothing has to be installed inside the container: the amd64 image now carries Intel's oneVPL GPU runtime and the iHD VA-API driver.
- **`GPU_VENDOR=amd` is a real code path now.** AMD hardware encoding on Linux runs through AMD's AMF framework, which Ubuntu's HandBrake is not built for and whose runtime is proprietary and cannot ship in a public image. The container now says precisely that, names the missing piece, and keeps converting in software instead of pretending. For anyone with an RX 5000/6000 series card who can supply AMD's AMF runtime, `Dockerfile.vce` builds a variant image with the VCE encoders compiled in.
- **A GPU diagnostics report.** `/config/handbrake-gpu.log` records the render nodes and their permissions, the groups the container user is in, the kernel driver behind each node, the encoders HandBrake really offers on your machine, and `vainfo` / `vpl-inspect` output. It is written on every start and is the first thing to read when acceleration does not engage.

## ⚡ Improved

- **Hardware detection asks HandBrake instead of guessing.** HandBrake only offers a hardware encoder when it is both compiled in and usable on the machine, so the container queries the real binary at startup, as the user that runs the conversions. That catches a GPU that was not passed through, a container user without access to the device, and an encoder this build does not have, all before the first job instead of on every job.
- **No silent fallbacks.** Any `GPU_VENDOR` that cannot be honoured now logs the reason and the fix, and leaves the command line untouched so conversions still complete in software.

## 🐛 Fixed

- The startup order now waits for the base image's device-group setup before probing the GPU, so a first start no longer reports a device as unusable that becomes usable a second later.
```

- [ ] **Step 2 (Variant B): Merge into Plan 2's notes file**

Open the existing `.github/release-notes/v1.1.0.md` and merge the bullets from
Variant A into the categories that are already there, so the file reads as one
release and never mentions that it was assembled from two plans:

- Every `## ✨ Added` bullet from Variant A goes after Plan 2's NVENC bullet.
- Every `## ⚡ Improved` bullet goes into Plan 2's `## ⚡ Improved` section, or
  creates it if Plan 2 has none.
- The `## 🐛 Fixed` bullet goes into Plan 2's `## 🐛 Fixed` section, or creates
  it.
- Rewrite the lead paragraph to cover all three vendors, for example:
  `Hardware encoding arrives: NVENC, Quick Sync, and an honest answer for AMD. Set GPU_VENDOR, pass the GPU through, and the watch-folder converter encodes on the GPU instead of the CPU — or tells you exactly why it cannot.`

Keep the category order `✨ Added`, `🎨 Design`, `⚡ Improved`, `🐛 Fixed` and
drop any category that would be empty.

- [ ] **Step 3: Check the notes against the house rules**

```bash
cd /d/nextcloud/it/github/handbrake
f=$(ls -1t .github/release-notes/*.md | head -1); echo "checking ${f}"
grep -nE '^#[^#]' "$f" && echo "H1 FOUND — remove it" || echo "no H1 heading (correct)"
grep -nE '^## ' "$f"
grep -niE 'claude|generated with|co-authored' "$f" && echo "AI REFERENCE FOUND — remove it" || echo "no AI references (correct)"
grep -niE 'verified on|tested on (intel|amd)' "$f" && echo "CHECK: does this claim hardware verification?" || echo "no hardware-verification claim (correct)"
```

Expected: `no H1 heading (correct)`, only non-empty emoji categories, `no AI
references (correct)`, and `no hardware-verification claim (correct)`.

- [ ] **Step 4: Commit and push, then stop**

```bash
cd /d/nextcloud/it/github/handbrake
git add .github/release-notes/
git commit -m "docs: add the release notes for Intel QSV and AMD GPU support"
git push origin main
gh run watch "$(gh run list --workflow=build.yml --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
gh run watch "$(gh run list --workflow=lint.yml  --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
```

Expected: both green on both arches.

- [ ] **Step 5: STOP — do not tag**

Report that everything is pushed and green, state plainly that Intel QSV and AMD
were implemented per documentation and are not hardware-verified, and ask jdp
for approval before cutting the tag. Tagging without explicit approval is a
house-rule violation.

- [ ] **Step 6: Follow-ups outside this repo (after the release is approved)**

1. **`unraid-apps` feed repo:** the `GPU_VENDOR` template field needs `intel` and
   `amd` added to its dropdown, and the template description needs a line saying
   that Intel and AMD additionally require `--device=/dev/dri` in *Extra
   Parameters*. Follow the existing entry's option formatting (fixed-option
   fields are pipe separated).
2. **Vault:** dated changelog entry plus an update to the repo note under
   `02 Projekte`, recording that Intel/AMD shipped unverified and that community
   reports are the open loop.

---

## Self-review checklist

Walked before this plan was declared finished; walk it again after implementing.

- [ ] No `TBD`, no `TODO`, no "similar to Task N", no "add appropriate error handling". Every hardware gap is stated as a gap **with** the alternative check next to it (Tasks 8, 9, 12).
- [ ] Names match Plan 1 exactly: `handbrake-gpu.sh`, `gpu_args_for_vendor()`, `/run/handbrake/gpu-args`, `/run/handbrake/gpu-vendor`, `GPU_VENDOR`, `init-handbrake`, `svc-handbrake-watch`, log prefix `[handbrake-gpu]`.
- [ ] The Intel/AMD asymmetry is reflected in the task shape, not just in prose: Intel is one package layer plus one branch (Tasks 3, 4, 6); AMD is a research finding, a different branch behaviour, a separate multi-stage Dockerfile, its own capability recording and its own README treatment (Tasks 2, 6, 11, 12, 13).
- [ ] The source rebuild is costed out loud (Task 11 preamble: 30-60 minutes, amd64 only, deliberately out of the CI matrix) rather than dropped into the default build.
- [ ] Community verification is a task with deliverables (Task 14: README subsection, issue form, label), not a sentence at the end of the README.
- [ ] Every claim about Ubuntu's packaging, HandBrake's encoder filtering, the AMF runtime and the preset/encoder interaction is backed by a reproducible command or a source quote in the research section.
- [ ] Plan 1's incorrect instruction ("read the encoder id from the build-time help dump") is corrected explicitly, in the plan, in the code comments, in `CLAUDE.md` and in `docs/handbrake-capabilities.md`, instead of being silently worked around.
- [ ] No task claims hardware verification anywhere it does not exist, and Task 16 Step 3 greps the release notes for exactly that mistake.
- [ ] Shared files carry a merge rule for Plan 2 (Coordination table, Task 6 Step 1, Task 10 Step 1, Task 13 Step 1, Task 16 Step 1).
- [ ] Out of scope and deliberately absent: NVENC selection (Plan 2), watch-daemon changes of any kind, hardware *decoding* by default, `--qsv-adapter`/`--qsv-preset` plumbing, a published VCE image tag, and any VA-API encoder code (HandBrake 1.11 has none, and when it gains them the existing lookup picks them up).

---

## Handoff: what Plan 4 must know

- **The GPU seam is unchanged in shape.** `handbrake-gpu.sh` still prints arguments on stdout and diagnostics on stderr; `init-handbrake` still redirects it into `/run/handbrake/gpu-args`; `handbrake-watch.sh` still splices that file before the user's `AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS`. Plan 4 should not touch any of it.
- **New helpers available to any later plan:** `hb_load_encoders`, `hb_has_encoder`, `hb_pick_encoder <id...>`, `hb_render_nodes`, `hb_have_amf_runtime`, `hb_write_diag <vendor>` in `rootfs/usr/local/bin/handbrake-gpu.sh`.
- **New runtime artefact:** `/config/handbrake-gpu.log`, written on every start when `GPU_VENDOR` is not `none`, owned by `PUID:PGID`, mode `0644`. If Plan 4 adds a log-collection or support-bundle feature, include this file.
- **New ordering edge:** `init-handbrake` now also depends on the base image's `init-video`.
- **New optional artefact:** `Dockerfile.vce`, built only by hand (`just build-vce`). If Plan 4 changes anything the Dockerfile installs or any path under `/usr/local/share/handbrake-*`, check that the variant's re-recording layer still matches.
- **Open loop, deliberately:** Intel QSV and AMD hardware encoding are unverified on real hardware. The `hardware-report` label collects the evidence. When the first credible confirmation arrives, the README's section 8 table (`Verified by the maintainer` column) and section 8.4 must be updated in the same pass, and the confirming issue linked.
