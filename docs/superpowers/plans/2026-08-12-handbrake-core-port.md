# HandBrake — Core Port Implementation Plan (Plan 1 of 4)

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking. Execute task-by-task, committing after each passing task.

**Goal:** Ship `junkerderprovinz/handbrake` v1.0.0 — HandBrake's full GTK GUI plus an automated watch-folder converter, running in a browser through a Selkies web desktop, dark by default, with a real CI boot-smoke gate that transcodes an actual video — and zero GPU-acceleration code.

**Architecture:** A single-stage Docker image on `ghcr.io/linuxserver/baseimage-selkies:ubunturesolute` (Ubuntu 26.04, glibc) that apt-installs the distro's `handbrake` (GTK4 `ghb`) and `handbrake-cli` (`HandBrakeCLI`) packages. s6-overlay v3 oneshots seed `/config`, force the GTK4 dark theme via `GTK_THEME=Adwaita:dark`, and prepare the watch/output mounts; two longruns supervise the watch-folder conversion daemon and the READY banner. The openbox `autostart` runs `ghb` in a relaunch loop on the Selkies desktop.

**Tech Stack:** Docker (BuildKit), LinuxServer `baseimage-selkies`, s6-overlay v3, POSIX sh + bash, HandBrake 1.11 (`ghb` GTK4 + `HandBrakeCLI`), GitHub Actions (hadolint, shellcheck, native amd64/arm64 matrix build, Trivy), GHCR + Docker Hub.

## Global Constraints

- Repo: `d:\nextcloud\it\github\handbrake`, remote `https://github.com/junkerderprovinz/handbrake`, branch `main`, git identity `junkerderprovinz` / `jdp@braethoria.com` (already configured).
- Versioning: 3-digit SemVer, tags `vX.Y.Z`. First release is `v1.0.0`.
- **Everything inside the repo is English** — code, comments, commit messages, README, release notes, log strings.
- **No AI attribution anywhere.** No `Co-Authored-By: Claude`, no "Generated with", no assistant references in commits, code or docs.
- **No em dashes in GitHub issue/PR/forum prose.** (Repo files such as README may use them; issue and forum text may not.)
- LF line endings are mandatory for everything under `rootfs/`, every `*.sh`, `.github/workflows/*.yml` and `.github/assets/banner-raw.txt` — enforced by `.gitattributes`. CRLF breaks shebangs inside the Linux image.
- CI must contain a **real boot-smoke gate**: build the image, boot it, require the Selkies WebUI to answer, require `ghb` to still be alive after a real interval with an unchanged PID, require the watch daemon to be alive, and require a genuine end-to-end transcode of a generated test clip. Gate runs on **both** arches natively.
- Release notes are **hand-written** at `.github/release-notes/vX.Y.Z.md`, emoji-categorised (`## ✨ Added`, `## 🎨 Design`, `## ⚡ Improved`, `## 🐛 Fixed`, `## 🌐 Translations`) with only non-empty categories, and no repo-name or version heading in the body (the GitHub release title carries `vX.Y.Z`).
- **Never tag or publish a release without explicit approval from jdp.** Building, pushing to `main` and letting `:latest` rebuild is fine; cutting `vX.Y.Z` is gated.
- No real user data, no real IPs, no licensed/commercial assets in the repo.
- Never `git add -A`. Always stage explicit paths.

---

## Task Overview

| # | Task | Ships |
|---|---|---|
| 1 | Repository scaffolding | `.gitattributes`, `.gitignore`, `LICENSE`, `NOTICE`, `renovate.json`, `.github/FUNDING.yml` |
| 2 | Brand assets + init banner | `.github/assets/*`, `rootfs/usr/local/bin/print-banner.sh` |
| 3 | Dockerfile | `Dockerfile` |
| 4 | s6 skeleton + no-login default | `rootfs/etc/s6-overlay/s6-rc.d/init-nologin/**`, `user/contents.d/**` |
| 5 | Theme seeding + desktop session | `handbrake-theme.sh`, `defaults/autostart`, `defaults/startwm.sh` |
| 6 | `init-handbrake` oneshot | `rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/**` |
| 7 | Watch-folder conversion daemon | `handbrake-watch.sh`, `svc-handbrake-watch/**` |
| 8 | READY banner service | `svc-handbrake-ready/**` |
| 9 | Build + record HandBrake capabilities | `docs/handbrake-capabilities.md` |
| 10 | End-to-end local verification | (no new files) |
| 11 | Lint workflow | `.github/workflows/lint.yml` |
| 12 | Build + smoke-gate workflow | `.github/workflows/build.yml` |
| 13 | Release + registry-cleanup workflows | `.github/workflows/release.yml`, `registry-cleanup.yml` |
| 14 | `justfile` + `CLAUDE.md` | `justfile`, `CLAUDE.md` |
| 15 | README | `README.md` |
| 16 | Release v1.0.0 | `.github/release-notes/v1.0.0.md` |

---

## Established conventions (read this before Task 1)

These are the conventions Plans 2, 3 and 4 must extend. Do not invent alternatives.

**No `/etc/cont-init.d/` is used in this repo.** The Selkies base restores `/etc/xdg/openbox/rc.xml` and rewrites parts of `/config` in `init-selkies-config`, which runs **after** the legacy `cont-init.d` stage — anything written there can be silently undone. All init therefore lives in s6-overlay v3 under `rootfs/etc/s6-overlay/s6-rc.d/`, ordered by explicit `dependencies.d/` entries, never by numeric filename prefixes. (Same choice as `krusader`.)

**Service naming:** `init-<topic>` for oneshots, `svc-<topic>` for longruns. Every service needs four things:

1. `rootfs/etc/s6-overlay/s6-rc.d/<name>/type` — `oneshot` or `longrun`
2. `rootfs/etc/s6-overlay/s6-rc.d/<name>/run` — the script (oneshots also need `up` containing the path to `run`)
3. `rootfs/etc/s6-overlay/s6-rc.d/<name>/dependencies.d/<other-service>` — empty file, one per ordering edge
4. `rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/<name>` — empty file, enables the service

**A new oneshot that must see a fully seeded `/config`** declares `dependencies.d/init-handbrake` and gets an `init-config-end/dependencies.d/<name>` entry so the base waits for it. Plans 2 and 3 add `init-handbrake-gpu` exactly this way.

**GPU seam:** the Dockerfile declares `ENV GPU_VENDOR=none`. `init-handbrake` normalises it and writes the extra `HandBrakeCLI` arguments for that vendor to `/run/handbrake/gpu-args` (empty in v1). `handbrake-watch.sh` reads that file and splices its contents into every `HandBrakeCLI` invocation. Plans 2/3 change **only** the `gpu_args_for_vendor()` function in `rootfs/usr/local/bin/handbrake-gpu.sh` plus the Dockerfile package layer — nothing else in the daemon.

---

### Task 1: Repository scaffolding

**Files:**
- Create: `d:\nextcloud\it\github\handbrake\.gitattributes`
- Create: `d:\nextcloud\it\github\handbrake\.gitignore`
- Create: `d:\nextcloud\it\github\handbrake\LICENSE`
- Create: `d:\nextcloud\it\github\handbrake\NOTICE`
- Create: `d:\nextcloud\it\github\handbrake\renovate.json`
- Create: `d:\nextcloud\it\github\handbrake\.github\FUNDING.yml`
- Test/Verify: `git check-attr text eol -- rootfs/x.sh` reports `eol: lf`; `LICENSE` is the full AGPL-3.0 text.

**Interfaces:**
- Consumes: nothing.
- Produces: the LF guarantee every later task relies on; `renovate.json` custom manager that tracks `ARG BASE_TAG=` in the `Dockerfile` created in Task 3.

- [ ] **Step 1: Write `.gitattributes`**

`d:\nextcloud\it\github\handbrake\.gitattributes`:

```gitattributes
# Shell scripts and the init banner run on Linux — always store and check out LF.
*.sh text eol=lf
.github/assets/banner-raw.txt text eol=lf

# Everything under rootfs/ ships into the Linux image: extensionless s6-rc.d
# service scripts (run / up / type), the openbox autostart, the session starter
# and configs. No binaries live here — pin the whole tree to LF so a CRLF
# checkout on Windows can never break a shebang inside the image.
rootfs/** text eol=lf

# Workflows are parsed by GitHub's YAML reader and by shellcheck in CI.
.github/workflows/*.yml text eol=lf

# Binary assets: never touched by line-ending normalisation.
*.png binary
*.jpg binary
*.ico binary
```

- [ ] **Step 2: Write `.gitignore`**

`d:\nextcloud\it\github\handbrake\.gitignore`:

```gitignore
# OS / Editor
.DS_Store
Thumbs.db
*.swp
*.swo
.idea/
.vscode/

# Build artefacts
*.tar
*.tar.gz
*.log

# Local Claude Code / agent config (never commit)
.claude/

# Importable Unraid template deliverable (the canonical template lives in the
# unraid-apps feed repo — this is only the local copy handed to the user)
my-HandBrake.xml

# Local smoke-test scratch
.smoke/
```

- [ ] **Step 3: Fetch the AGPL-3.0 licence text**

```bash
cd /d/nextcloud/it/github/handbrake
curl -fsSL https://www.gnu.org/licenses/agpl-3.0.txt -o LICENSE
```

- [ ] **Step 4: Verify the licence file**

Run: `head -n 3 /d/nextcloud/it/github/handbrake/LICENSE && wc -l /d/nextcloud/it/github/handbrake/LICENSE`
Expected: first line `                    GNU AFFERO GENERAL PUBLIC LICENSE`, line count `661`.

- [ ] **Step 5: Write `NOTICE`**

The HandBrake logo we ship (Task 2) is licensed **CC BY-SA 4.0** and upstream requires a specific attribution form — confirmed at `https://github.com/HandBrake/HandBrake/blob/1.11.x/graphics/LICENSE`. That attribution lives here.

`d:\nextcloud\it\github\handbrake\NOTICE`:

```text
NOTICE — Bundled Software and Artwork in the HandBrake Unraid Container Image
=============================================================================

The GNU Affero General Public License v3.0 (AGPL-3.0, see LICENSE) covers ONLY
the wrapper assets in this repository:
  * Dockerfile and the rootfs/ overlay
  * Helper scripts under rootfs/usr/local/bin/
  * Unraid container template (maintained in the junkerderprovinz/unraid-apps repo)
  * README text and the banner layout

It does NOT relicense any software or artwork shipped inside the resulting
container image. Each bundled component retains its upstream license:

  * HandBrake (ghb GTK GUI + HandBrakeCLI)   GPL-2.0-only
                                             https://handbrake.fr
                                             https://github.com/HandBrake/HandBrake
  * HandBrake logo and icon artwork          CC BY-SA 4.0
                                             https://github.com/HandBrake/HandBrake/blob/master/graphics/LICENSE
  * x264                                     GPL-2.0-or-later
  * x265                                     GPL-2.0-or-later
  * FFmpeg libraries (libav*)                LGPL-2.1-or-later / GPL-2.0-or-later
  * GTK 4 and GLib                           LGPL-2.1-or-later
  * LinuxServer.io baseimage-selkies         GPL-3.0
                                             https://github.com/linuxserver/docker-baseimage-selkies

Artwork attribution, in the form required by HandBrake's graphics license:

  Copyright HandBrake Team <https://handbrake.fr>
  Copyright junkerderprovinz <jdp@braethoria.com> (banner and icon derivations)

  The HandBrake logo is used unmodified except for rasterisation and scaling.
  Derived works in .github/assets/ are shared under the same
  Creative Commons Attribution-ShareAlike 4.0 International Public License.
  https://creativecommons.org/licenses/by-sa/4.0/

When you run, redistribute or rebuild the resulting container image you must
comply with the licenses of all bundled components in addition to the AGPL-3.0
license that covers this repository.
```

- [ ] **Step 6: Write `renovate.json`**

`d:\nextcloud\it\github\handbrake\renovate.json`:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:recommended",
    ":semanticCommits",
    ":dependencyDashboard",
    ":enableVulnerabilityAlertsWithLabel(security)"
  ],
  "timezone": "Europe/Vienna",
  "schedule": ["before 6am on monday"],
  "labels": ["dependencies"],
  "prHourlyLimit": 4,
  "prConcurrentLimit": 6,
  "packageRules": [
    {
      "description": "LinuxServer Selkies base image — group and label all updates, manual review required",
      "matchPackageNames": ["ghcr.io/linuxserver/baseimage-selkies"],
      "groupName": "LSIO Selkies base",
      "commitMessageTopic": "LSIO Selkies base",
      "commitMessagePrefix": "feat:",
      "labels": ["base-image"]
    },
    {
      "description": "GitHub Actions: auto-merge all updates",
      "matchManagers": ["github-actions"],
      "matchUpdateTypes": ["major", "minor", "patch", "digest"],
      "automerge": true,
      "automergeType": "pr",
      "platformAutomerge": true,
      "commitMessagePrefix": "ci:",
      "labels": ["github-actions"]
    }
  ],
  "customManagers": [
    {
      "customType": "regex",
      "description": "Track the LinuxServer Selkies base image tag from ARG BASE_TAG=<tag>",
      "managerFilePatterns": ["/(^|/)Dockerfile$/"],
      "matchStrings": [
        "ARG BASE_TAG=(?<currentValue>[^\\s]+)"
      ],
      "depNameTemplate": "ghcr.io/linuxserver/baseimage-selkies",
      "datasourceTemplate": "docker"
    }
  ]
}
```

- [ ] **Step 7: Write `.github/FUNDING.yml`**

```bash
mkdir -p /d/nextcloud/it/github/handbrake/.github
```

`d:\nextcloud\it\github\handbrake\.github\FUNDING.yml`:

```yaml
# These are supported funding model platforms

buy_me_a_coffee: junkerderprovinz
```

- [ ] **Step 8: Verify the LF attribute actually applies**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
git check-attr text eol -- rootfs/usr/local/bin/example.sh
git check-attr text eol -- .github/workflows/build.yml
python -c "import json;json.load(open('renovate.json'));print('renovate.json OK')"
```
Expected:
```
rootfs/usr/local/bin/example.sh: text: set
rootfs/usr/local/bin/example.sh: eol: lf
.github/workflows/build.yml: text: set
.github/workflows/build.yml: eol: lf
renovate.json OK
```

- [ ] **Step 9: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add .gitattributes .gitignore LICENSE NOTICE renovate.json .github/FUNDING.yml
git commit -m "chore: scaffold repository (licence, notice, gitattributes, renovate)"
```

---

### Task 2: Brand assets and the init-log banner

**Files:**
- Create: `d:\nextcloud\it\github\handbrake\.github\assets\handbrake-logo.svg`
- Create: `d:\nextcloud\it\github\handbrake\.github\assets\icon.png`
- Create: `d:\nextcloud\it\github\handbrake\.github\assets\favicon.ico`
- Create: `d:\nextcloud\it\github\handbrake\.github\assets\banner-raw.txt`
- Create: `d:\nextcloud\it\github\handbrake\.github\assets\gen-banner.mjs`
- Create (generated): `handbrake-banner.svg`, `handbrake-banner.png`, `handbrake-banner-dark.svg`, `handbrake-banner-dark.png` in `.github/assets/`
- Create: `d:\nextcloud\it\github\handbrake\.github\assets\button-buy-me-a-coffee.svg`
- Create: `d:\nextcloud\it\github\handbrake\rootfs\usr\local\bin\print-banner.sh`
- Test/Verify: `icon.png` is a 512x512 PNG; both banner PNGs are 1600x500; `print-banner.sh` prints the wordmark.

**Interfaces:**
- Consumes: nothing.
- Produces: `.github/assets/icon.png` (COPYed by the Dockerfile onto `/usr/share/selkies/www/icon.png`), `.github/assets/banner-raw.txt` (COPYed to `/usr/local/share/banner-raw.txt`, CR-stripped to `/usr/local/share/banner.txt`), `/usr/local/bin/print-banner.sh` (called by `svc-handbrake-ready` in Task 8 with two arguments: container name and subtitle), and the README banner pair used in Task 15.

- [ ] **Step 1: Confirm HandBrake's artwork licence before embedding anything**

The spec requires verifying HandBrake's logo/trademark policy before shipping the logo. Run the check and read the result — do not skip it:

```bash
curl -fsSL https://raw.githubusercontent.com/HandBrake/HandBrake/1.11.x/graphics/LICENSE
```
Expected: the text states the graphic assets are released under the **Creative Commons Attribution-ShareAlike 4.0 International Public License**, and prescribes the attribution form `Copyright HandBrake Team <https://handbrake.fr>`.

If — and only if — this text has changed to something that forbids redistribution, stop and report; otherwise continue. The attribution is already written into `NOTICE` (Task 1, Step 5).

- [ ] **Step 2: Fetch the official app icon (SVG, upstream verbatim)**

```bash
mkdir -p /d/nextcloud/it/github/handbrake/.github/assets
cd /d/nextcloud/it/github/handbrake/.github/assets
curl -fsSL -o handbrake-logo.svg \
  https://raw.githubusercontent.com/HandBrake/HandBrake/1.11.x/gtk/icons/scalable/apps/fr.handbrake.ghb.svg
head -c 200 handbrake-logo.svg; echo
```
Expected: an `<svg ...>` document (starts with `<?xml` or `<svg`).

- [ ] **Step 3: Render `icon.png` (512x512) and `favicon.ico`**

Requires `@resvg/resvg-js` (already used by the house banner generator) and ImageMagick for the `.ico`:

```bash
npm i -g @resvg/resvg-js
cd /d/nextcloud/it/github/handbrake/.github/assets
node -e "
const {Resvg}=require(require('child_process').execSync('npm root -g').toString().trim()+'/@resvg/resvg-js');
const fs=require('fs');
const svg=fs.readFileSync('handbrake-logo.svg','utf8');
for (const [size,out] of [[512,'icon.png'],[256,'icon-256.png']]) {
  const png=new Resvg(svg,{fitTo:{mode:'width',value:size}}).render().asPng();
  fs.writeFileSync(out,png);
  console.log('wrote',out,size+'x'+size);
}
"
magick icon-256.png -define icon:auto-resize=256,128,64,48,32,16 favicon.ico
rm -f icon-256.png
```

- [ ] **Step 4: Verify the raster assets**

Run:
```bash
cd /d/nextcloud/it/github/handbrake/.github/assets
python -c "
import struct
d=open('icon.png','rb').read()
w,h=struct.unpack('>II', d[16:24])
print('icon.png', w, 'x', h)
assert (w,h)==(512,512), 'icon.png must be 512x512'
"
ls -l icon.png favicon.ico handbrake-logo.svg
```
Expected: `icon.png 512 x 512` and three non-empty files.

Note (house rule "CA icon background"): the HandBrake logo has its own strong silhouette, so it keeps a transparent background — do **not** add a solid tile behind it.

- [ ] **Step 5: Write the init-log ASCII banner**

`d:\nextcloud\it\github\handbrake\.github\assets\banner-raw.txt` (exact content, no trailing spaces, LF only):

```text
█   █  ███  █   █ ████  ████  ████   ███  █   █ █████
█   █ █   █ ██  █ █   █ █   █ █   █ █   █ █  █  █
█████ █████ █ █ █ █   █ ████  ████  █████ ███   ████
█   █ █   █ █  ██ █   █ █   █ █  █  █   █ █  █  █
█   █ █   █ █   █ ████  ████  █   █ █   █ █   █ █████
```

- [ ] **Step 6: Write `print-banner.sh` (house-shared, identical to the other containers)**

```bash
mkdir -p /d/nextcloud/it/github/handbrake/rootfs/usr/local/bin
```

`d:\nextcloud\it\github\handbrake\rootfs\usr\local\bin\print-banner.sh`:

```bash
#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# print-banner.sh <container-name> <subtitle>
# Shared init-log banner for all Junker der Provinz containers.
# ─────────────────────────────────────────────────────────────────

CONTAINER="${1:-Container}"
SUBTITLE="${2:-}"
BANNER_FILE="/usr/local/share/banner.txt"

echo ""

if [ -f "${BANNER_FILE}" ]; then
    cat "${BANNER_FILE}"
    # The shared banner file has no trailing newline; add blank lines so the
    # banner gets breathing room before the title block.
    echo ""
    echo ""
else
    echo ""
    echo "  Junker der Provinz"
    echo ""
fi

# Clean title block: name + subtitle only, no rules (house look).
printf '  %s\n' "${CONTAINER}"
[ -n "${SUBTITLE}" ] && printf '  %s\n' "${SUBTITLE}"
echo ""
```

- [ ] **Step 7: Write the README banner generator**

`d:\nextcloud\it\github\handbrake\.github\assets\gen-banner.mjs`:

```javascript
/**
 * Generates the HandBrake README banners (house theme-adaptive pair):
 *   handbrake-banner.svg / .png      : light 1600x500 - white bg, dark wordmark
 *   handbrake-banner-dark.svg / .png : dark 1600x500 - GitHub-dark bg, light wordmark
 * Both embed the SAME official HandBrake logo verbatim (CC BY-SA 4.0, see
 * NOTICE); only the background and text colours flip. The README serves the
 * pair via <picture>.
 *
 * Wordmark face: DejaVu Sans Bold, claim: DejaVu Sans Book. Both are free
 * (Bitstream Vera / DejaVu licence), fetched at runtime from the
 * dejavu-fonts-ttf npm package via jsDelivr, cached in the OS temp dir, and
 * never committed.
 *
 * The text is converted to SVG paths (opentype.js) so the SVG is self-contained.
 * NOTE: DejaVu's GSUB ccmp lookups crash opentype.js's feature engine, so glyph
 * runs are shaped glyph-by-glyph with manual pair kerning (plain Latin - no loss).
 *
 * Deps: `npm i -g @resvg/resvg-js opentype.js`.
 * Run:  node .github/assets/gen-banner.mjs
 */
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";
import { createRequire } from "node:module";
import { execSync } from "node:child_process";

const require = createRequire(import.meta.url);
const gRoot = execSync("npm root -g").toString().trim();
const { Resvg } = require(`${gRoot}/@resvg/resvg-js`);
const opentype = require(`${gRoot}/opentype.js`);

const __dir = dirname(fileURLToPath(import.meta.url));

// ---- content + styling -----------------------------------------------------
const NAME = "HandBrake";
const CLAIM = "Rip it. Squish it. In the dark.";
const THEMES = [
  { suffix: "", bg: "#ffffff", name: "#1f2328", claim: "#5a5d5e" },
  { suffix: "-dark", bg: "#0d1117", name: "#e6edf3", claim: "#9aa4ad" },
];
const W = 1600, H = 500;
const LH = 400; // logo height
// House banner standard: name 132 / claim 44, logo-to-text gap 70, name-to-claim gap 8.
const nameSize = 132, claimSize = 44, gap = 70, lineGap = 8;
const startX = 165; // left-anchored (house banner standard)
// ---------------------------------------------------------------------------

function shapeRun(font, text, size) {
  const scale = size / font.unitsPerEm;
  const run = [];
  let x = 0;
  let prev = null;
  for (const ch of text) {
    const g = font.charToGlyph(ch);
    if (prev) x += font.getKerningValue(prev, g) * scale;
    run.push({ g, x });
    x += g.advanceWidth * scale;
    prev = g;
  }
  return { run, width: x };
}
function runWidth(font, text, size) {
  return shapeRun(font, text, size).width;
}
function runPathData(font, text, x, y, size) {
  let d = "";
  for (const { g, x: gx } of shapeRun(font, text, size).run) {
    d += g.getPath(x + gx, y, size).toPathData(2);
  }
  return d;
}

async function loadFont(url, cacheName) {
  const path = join(tmpdir(), `handbrake-${cacheName}.ttf`);
  if (!existsSync(path)) {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`font fetch ${cacheName}: ${res.status}`);
    writeFileSync(path, Buffer.from(await res.arrayBuffer()));
  }
  const buf = readFileSync(path);
  return opentype.parse(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength));
}
const DEJAVU = "https://cdn.jsdelivr.net/npm/dejavu-fonts-ttf@2.37.3/ttf";
const nameFont = await loadFont(`${DEJAVU}/DejaVuSans-Bold.ttf`, "DejaVuSans-Bold");
const claimFont = await loadFont(`${DEJAVU}/DejaVuSans.ttf`, "DejaVuSans-Book");

const nameW = runWidth(nameFont, NAME, nameSize);
const claimW = runWidth(claimFont, CLAIM, claimSize);
const LW = LH; // square logo
const groupW = LW + gap + Math.max(nameW, claimW);
const LX = startX, LY = (H - LH) / 2;
const textX = startX + LW + gap;

const em = (f, s) => s / f.unitsPerEm;
const nameAsc = nameFont.ascender * em(nameFont, nameSize);
const nameDesc = -nameFont.descender * em(nameFont, nameSize);
const claimAsc = claimFont.ascender * em(claimFont, claimSize);
const blockH = nameAsc + nameDesc + lineGap + claimAsc;
const nameBaseline = H / 2 - blockH / 2 + nameAsc;
const claimBaseline = nameBaseline + nameDesc + lineGap + claimAsc;

const namePath = runPathData(nameFont, NAME, textX, nameBaseline, nameSize);
const claimPath = runPathData(claimFont, CLAIM, textX, claimBaseline, claimSize);

// Embed the official logo verbatim inside a positioned wrapper. Its viewBox is
// read from the source so the artwork itself is never touched.
const logoSrc = readFileSync(join(__dir, "handbrake-logo.svg"), "utf8")
  .replace(/<\?xml[^>]*\?>\s*/, "");
const vbMatch = logoSrc.match(/viewBox="([^"]+)"/);
const viewBox = vbMatch ? vbMatch[1] : "0 0 128 128";
const logo = logoSrc.replace(
  /<svg[\s\S]*?>/,
  `<svg x="${LX.toFixed(1)}" y="${LY.toFixed(1)}" width="${LW}" height="${LH}" viewBox="${viewBox}" xmlns="http://www.w3.org/2000/svg">`,
);

for (const t of THEMES) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" role="img" aria-label="HandBrake">
  <rect width="${W}" height="${H}" fill="${t.bg}"/>
  ${logo}
  <path d="${namePath}" fill="${t.name}"/>
  <path d="${claimPath}" fill="${t.claim}"/>
</svg>
`;
  writeFileSync(join(__dir, `handbrake-banner${t.suffix}.svg`), svg);
  const png = new Resvg(svg, { fitTo: { mode: "width", value: W }, background: t.bg }).render().asPng();
  writeFileSync(join(__dir, `handbrake-banner${t.suffix}.png`), png);
  console.log(`wrote handbrake-banner${t.suffix}.svg + .png (name ${Math.round(nameW)}px, claim ${Math.round(claimW)}px, group ${Math.round(groupW)}px)`);
}
```

- [ ] **Step 8: Generate the banners**

```bash
npm i -g @resvg/resvg-js opentype.js
cd /d/nextcloud/it/github/handbrake
node .github/assets/gen-banner.mjs
```
Expected output (two lines):
```
wrote handbrake-banner.svg + .png (name ..px, claim ..px, group ..px)
wrote handbrake-banner-dark.svg + .png (name ..px, claim ..px, group ..px)
```

- [ ] **Step 9: Copy the shared Buy-me-a-coffee button**

```bash
cp /d/nextcloud/it/github/krusader/.github/assets/button-buy-me-a-coffee.svg \
   /d/nextcloud/it/github/handbrake/.github/assets/button-buy-me-a-coffee.svg
```

- [ ] **Step 10: Verify the banner dimensions**

Run:
```bash
cd /d/nextcloud/it/github/handbrake/.github/assets
python -c "
import struct
for f in ('handbrake-banner.png','handbrake-banner-dark.png'):
    d=open(f,'rb').read(); w,h=struct.unpack('>II', d[16:24]); print(f,w,'x',h)
    assert (w,h)==(1600,500), f+' must be 1600x500'
"
```
Expected:
```
handbrake-banner.png 1600 x 500
handbrake-banner-dark.png 1600 x 500
```

- [ ] **Step 11: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add .github/assets/handbrake-logo.svg .github/assets/icon.png .github/assets/favicon.ico \
        .github/assets/banner-raw.txt .github/assets/gen-banner.mjs \
        .github/assets/handbrake-banner.svg .github/assets/handbrake-banner.png \
        .github/assets/handbrake-banner-dark.svg .github/assets/handbrake-banner-dark.png \
        .github/assets/button-buy-me-a-coffee.svg \
        rootfs/usr/local/bin/print-banner.sh
git commit -m "feat: add HandBrake brand assets, README banners and the init-log banner"
```

---

### Task 3: Dockerfile

**Files:**
- Create: `d:\nextcloud\it\github\handbrake\Dockerfile`
- Test/Verify: `hadolint Dockerfile --ignore DL3008 --ignore DL3009` is clean. (The image itself is not buildable until Task 8 finishes — the Dockerfile `COPY`s and `chmod`s files that Tasks 4-8 create. That is intentional; the first real build is Task 9.)

**Interfaces:**
- Consumes: `.github/assets/icon.png`, `.github/assets/banner-raw.txt` (Task 2).
- Produces, for every later task and for Plans 2-4:
  - Base: `ARG BASE_TAG=ubunturesolute` on `ghcr.io/linuxserver/baseimage-selkies` (Renovate-tracked).
  - Binaries: `/usr/bin/ghb` (GTK4 GUI), `/usr/bin/HandBrakeCLI`.
  - Recorded capability dumps inside the image: `/usr/local/share/handbrake-cli-help.txt`, `/usr/local/share/handbrake-preset-list.txt`, `/usr/local/share/handbrake-version.txt`.
  - Mount points: `/config`, `/storage`, `/watch`, `/watch2`…`/watch5`, `/output`.
  - Env contract: `HANDBRAKE_THEME=dark`, `GPU_VENDOR=none`, `APP_NICENESS=0`, `KEYBOARD_LAYOUT=us`, and the whole `AUTOMATED_CONVERSION*` block.
  - Build stamp: `/etc/handbrake-build` (`sha=`/`date=` lines).

- [ ] **Step 1: Write the Dockerfile**

`d:\nextcloud\it\github\handbrake\Dockerfile`:

```dockerfile
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
# GPU_VENDOR       – none (default) | nvidia | intel | amd. v1 ships NO GPU
#                    acceleration: any value other than "none" logs a clear
#                    warning and falls back to software encoding. The seam is
#                    /usr/local/bin/handbrake-gpu.sh -> /run/handbrake/gpu-args.
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
```

- [ ] **Step 2: Lint the Dockerfile**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
hadolint Dockerfile --ignore DL3008 --ignore DL3009
```
Expected: no output, exit code 0. (`DL3008` = apt version pinning, deliberately skipped because the package set moves with Ubuntu; `DL3009` = apt lists cleaned once at the end of the install layer.)

- [ ] **Step 3: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add Dockerfile
git commit -m "feat: add the Dockerfile (Selkies base, HandBrake GUI + CLI, capability dumps)"
```

---

### Task 4: s6 service skeleton and the no-login default

**Files:**
- Create: `rootfs/etc/s6-overlay/s6-rc.d/init-nologin/run`
- Create: `rootfs/etc/s6-overlay/s6-rc.d/init-nologin/type`
- Create: `rootfs/etc/s6-overlay/s6-rc.d/init-nologin/up`
- Create: `rootfs/etc/s6-overlay/s6-rc.d/init-nginx/dependencies.d/init-nologin` (empty)
- Create: `rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/init-nologin` (empty)
- Create: `rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/init-handbrake` (empty)
- Create: `rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/svc-handbrake-watch` (empty)
- Create: `rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/svc-handbrake-ready` (empty)
- Create: `rootfs/etc/s6-overlay/s6-rc.d/init-config-end/dependencies.d/init-handbrake` (empty)
- Test/Verify: `shellcheck -S warning` passes on `init-nologin/run`; all nine paths exist.

**Interfaces:**
- Consumes: nothing.
- Produces: the enabled-service registry. Plans 2/3 add their oneshot by creating `user/contents.d/init-handbrake-gpu` and `init-config-end/dependencies.d/init-handbrake-gpu` the same way.

- [ ] **Step 1: Create the directory tree and the empty marker files**

`git` cannot store empty directories but stores empty *files* fine — every marker below is an intentionally empty file.

```bash
cd /d/nextcloud/it/github/handbrake
S6=rootfs/etc/s6-overlay/s6-rc.d
mkdir -p "$S6/init-nologin" \
         "$S6/init-nginx/dependencies.d" \
         "$S6/init-config-end/dependencies.d" \
         "$S6/user/contents.d"
: > "$S6/init-nginx/dependencies.d/init-nologin"
: > "$S6/init-config-end/dependencies.d/init-handbrake"
: > "$S6/user/contents.d/init-nologin"
: > "$S6/user/contents.d/init-handbrake"
: > "$S6/user/contents.d/svc-handbrake-watch"
: > "$S6/user/contents.d/svc-handbrake-ready"
```

- [ ] **Step 2: Write `init-nologin/run`**

`d:\nextcloud\it\github\handbrake\rootfs\etc\s6-overlay\s6-rc.d\init-nologin\run`:

```bash
#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# The HandBrake template exposes optional WebUI auth via the CUSTOM_USER /
# PASSWORD fields. Unraid passes them as EMPTY environment variables when the
# fields are left blank, and the base image's init-nginx enables HTTP basic auth
# whenever PASSWORD is merely SET — even to "" — writing /etc/nginx/.htpasswd and
# uncommenting the auth_basic lines. That pops a browser login prompt (with an
# unusable empty password) even though the template promises "leave empty for no
# login". Strip the empty values here, before init-nginx runs, so the no-login
# default actually holds. A real, non-empty password is left untouched and still
# enables basic auth on the WebUI exactly as documented.
if [ -z "${PASSWORD}" ]; then
  rm -f /run/s6/container_environment/PASSWORD
fi
if [ -z "${CUSTOM_USER}" ]; then
  rm -f /run/s6/container_environment/CUSTOM_USER
fi
```

- [ ] **Step 3: Write `init-nologin/type` and `init-nologin/up`**

`rootfs/etc/s6-overlay/s6-rc.d/init-nologin/type` (single line, no trailing text):

```text
oneshot
```

`rootfs/etc/s6-overlay/s6-rc.d/init-nologin/up`:

```text
/etc/s6-overlay/s6-rc.d/init-nologin/run
```

- [ ] **Step 4: Verify the tree**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
find rootfs/etc/s6-overlay -type f | sort
shellcheck -S warning -x -e SC1091 rootfs/etc/s6-overlay/s6-rc.d/init-nologin/run
```
Expected file list:
```
rootfs/etc/s6-overlay/s6-rc.d/init-config-end/dependencies.d/init-handbrake
rootfs/etc/s6-overlay/s6-rc.d/init-nginx/dependencies.d/init-nologin
rootfs/etc/s6-overlay/s6-rc.d/init-nologin/run
rootfs/etc/s6-overlay/s6-rc.d/init-nologin/type
rootfs/etc/s6-overlay/s6-rc.d/init-nologin/up
rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/init-handbrake
rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/init-nologin
rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/svc-handbrake-ready
rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/svc-handbrake-watch
```
and shellcheck prints nothing.

- [ ] **Step 5: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add rootfs/etc/s6-overlay
git commit -m "feat: add the s6-rc service skeleton and the no-default-login oneshot"
```

---

### Task 5: Theme seeding and the desktop session

**Files:**
- Create: `rootfs/usr/local/bin/handbrake-theme.sh`
- Create: `rootfs/defaults/autostart`
- Create: `rootfs/defaults/startwm.sh`
- Test/Verify: `shellcheck -S warning -x -e SC1091` clean on all three; `bash -n` / `sh -n` parse clean.

**Interfaces:**
- Consumes: `HANDBRAKE_THEME` and `APP_NICENESS`/`KEYBOARD_LAYOUT` from the Dockerfile ENV (Task 3).
- Produces:
  - `/usr/local/bin/handbrake-theme.sh <dark|light>` — the single theme entry point, called by `init-handbrake` (Task 6). It writes `/run/s6/container_environment/GTK_THEME`, `/config/.profile.d/handbrake-theme.sh`, `/config/.config/gtk-3.0/settings.ini` and `/config/.config/gtk-4.0/settings.ini`.
  - `GTK_THEME=Adwaita:dark` (dark) or `GTK_THEME=Adwaita` (light) — the value the CI smoke gate asserts.
  - `/defaults/autostart` — the openbox session entry point; runs `ghb` in a relaunch loop and writes GUI output to `/config/handbrake-gui.log`.
  - `/defaults/startwm.sh` — session starter, deliberately **not** redirected to `/dev/null` so `[handbrake-autostart]` lines reach `docker logs`.

- [ ] **Step 1: Write `handbrake-theme.sh`**

Why `GTK_THEME` and not a settings file alone — this is load-bearing, do not "simplify" it away: HandBrake 1.11's GUI is **GTK4 without libadwaita** (`gtk/meson.build` lists `gtk4` and no `libadwaita`), and `gtk/src/application.c` calls `color_scheme_set_async(APP_PREFERS_LIGHT)` on every startup. That call sets `gtk-application-prefer-dark-theme` to FALSE unless the freedesktop desktop portal reports a dark preference — and there is no portal in this container. So `gtk-application-prefer-dark-theme=1` in `settings.ini` is overwritten at startup and cannot be the mechanism. GTK4's `get_theme_name()` however checks `$GTK_THEME` **first** and returns immediately, ignoring both the settings property and HandBrake's own preference. `GTK_THEME=Adwaita:dark` therefore gives a deterministic native dark UI with zero extra packages. The `settings.ini` files are still written as a second layer for any other GTK app on the desktop.

`d:\nextcloud\it\github\handbrake\rootfs\usr\local\bin\handbrake-theme.sh`:

```bash
#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# handbrake-theme.sh <dark|light>
# ---------------------------------------------------------------------------
# Applies HandBrake's NATIVE dark mode. HandBrake's GUI is GTK4 (no libadwaita),
# so "dark mode" here means the stock Adwaita dark variant that ships inside
# libgtk-4-1 — exactly the mechanism jlesage's DARK_MODE uses, and exactly what
# a well-behaved GTK app picks up on any desktop.
#
# WHY THE ENV VAR IS THE PRIMARY MECHANISM
#   ghb calls color_scheme_set_async(APP_PREFERS_LIGHT) at startup
#   (gtk/src/application.c) which sets GtkSettings:gtk-application-prefer-dark-
#   theme to FALSE whenever the freedesktop desktop portal reports no
#   preference — and this container has no portal. A settings.ini
#   "gtk-application-prefer-dark-theme=1" is therefore overwritten seconds after
#   the app starts. GTK4's theme resolution reads $GTK_THEME FIRST and returns
#   before it ever looks at the setting, so the env var wins deterministically.
#
# TRADE-OFF, DOCUMENT IT IN THE README: because $GTK_THEME wins, HandBrake's own
# in-app light/dark toggle has no visible effect. The container's
# HANDBRAKE_THEME variable is the single source of truth for the theme.
# ---------------------------------------------------------------------------
set -eu

log() { echo "[handbrake-theme] $*"; }

REQUESTED="${1:-dark}"
case "$(printf '%s' "${REQUESTED}" | tr '[:upper:]' '[:lower:]')" in
    light|adwaita|breezelight)
        THEME="light"
        GTK_THEME_VALUE="Adwaita"
        PREFER_DARK="0"
        ;;
    *)
        THEME="dark"
        GTK_THEME_VALUE="Adwaita:dark"
        PREFER_DARK="1"
        ;;
esac

CONFIG_HOME="/config/.config"
PROFILE_D="/config/.profile.d"

mkdir -p "${CONFIG_HOME}/gtk-3.0" "${CONFIG_HOME}/gtk-4.0" "${PROFILE_D}"

# Second layer: a real settings file, so every OTHER GTK app on the desktop
# (file dialogs, future additions) follows the same choice even if it never
# reads $GTK_THEME. Harmless for ghb, which the env var already pins.
for ver in 3.0 4.0; do
    cat > "${CONFIG_HOME}/gtk-${ver}/settings.ini" <<EOF
[Settings]
gtk-theme-name=Adwaita
gtk-icon-theme-name=Adwaita
gtk-application-prefer-dark-theme=${PREFER_DARK}
gtk-font-name=DejaVu Sans 10
EOF
done

# The Selkies desktop session does NOT inherit /run/s6/container_environment,
# so the value is additionally written as a profile snippet that
# /defaults/autostart sources right before launching ghb.
cat > "${PROFILE_D}/handbrake-theme.sh" <<EOF
# Written by handbrake-theme.sh — do not edit, it is rewritten on every start.
export GTK_THEME="${GTK_THEME_VALUE}"
export HANDBRAKE_THEME="${THEME}"
EOF
chmod 0644 "${PROFILE_D}/handbrake-theme.sh"

# Primary layer: the s6 container environment, inherited by every s6 service
# (the watch daemon, the READY service) and asserted by the CI smoke gate.
mkdir -p /run/s6/container_environment
printf '%s' "${GTK_THEME_VALUE}" > /run/s6/container_environment/GTK_THEME
printf '%s' "${THEME}"           > /run/s6/container_environment/HANDBRAKE_THEME

chown -R abc:abc "${CONFIG_HOME}/gtk-3.0" "${CONFIG_HOME}/gtk-4.0" "${PROFILE_D}" 2>/dev/null || true

log "theme=${THEME} GTK_THEME=${GTK_THEME_VALUE} (native GTK4 Adwaita)"
```

- [ ] **Step 2: Write `rootfs/defaults/autostart`**

```bash
mkdir -p /d/nextcloud/it/github/handbrake/rootfs/defaults
```

`d:\nextcloud\it\github\handbrake\rootfs\defaults\autostart`:

```sh
#!/bin/sh
# -----------------------------------------------------------------------------
# HandBrake autostart for linuxserver/baseimage-selkies
# -----------------------------------------------------------------------------
# POSIX WARNING: openbox executes this with /bin/sh (dash) and IGNORES the
# shebang. Bashisms like [[ ]] fail SILENTLY ("[[: not found") while the rest of
# the script keeps running. Only POSIX sh here.
#
# init-handbrake copies this file to /config/.config/openbox/autostart on every
# start, so image updates always ship a fresh copy.
# -----------------------------------------------------------------------------

# --- Theme: sourced from the snippet handbrake-theme.sh wrote ----------------
if [ -f /config/.profile.d/handbrake-theme.sh ]; then
    # shellcheck disable=SC1091
    . /config/.profile.d/handbrake-theme.sh
fi
# Unconditional fallback: dark is the default, and an unset GTK_THEME would let
# HandBrake's own APP_PREFERS_LIGHT default win.
export GTK_THEME="${GTK_THEME:-Adwaita:dark}"

# --- XDG base dirs: pin to the persistent /config paths for EVERY PUID -------
# Under PUID=0 the session runs as literal root, whose default
# $HOME/.{config,cache,local/share} differ from abc's /config tree — HandBrake's
# own preferences (~/.config/ghb) would then land where the next start does not
# read them. Pin them so root and non-root behave identically.
export HOME="${HOME:-/config}"
export XDG_CONFIG_HOME="/config/.config"
export XDG_DATA_HOME="/config/.local/share"
export XDG_CACHE_HOME="/config/.cache"
case ":${XDG_DATA_DIRS:-}:" in
    *":/usr/share:"*) : ;;
    *) export XDG_DATA_DIRS="${XDG_DATA_DIRS:+$XDG_DATA_DIRS:}/usr/local/share:/usr/share" ;;
esac

export LANG="${LANG:-en_US.UTF-8}"
export LANGUAGE="${LANGUAGE:-en_US:en}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

echo "[handbrake-autostart] GTK_THEME=$GTK_THEME XDG_CONFIG_HOME=$XDG_CONFIG_HOME LANG=$LANG" >&2

# --- Keyboard map: bind a complete keymap so Shift resolves ------------------
# The Selkies base starts Xvfb with NO keymap. Without a real Shift binding the
# web client's keystroke re-type paste path injects Shift_L plus the LOWERCASE
# keysym, and with no keymap Shift_L never binds — every pasted capital falls to
# keymap level 0. Loading a full keymap binds Shift_L as a real modifier.
if setxkbmap_out=$(setxkbmap -display "${DISPLAY:-:1}" -layout "${KEYBOARD_LAYOUT:-us}" 2>&1); then
    echo "[handbrake-autostart] keymap: layout=${KEYBOARD_LAYOUT:-us} bound OK" >&2
else
    echo "[handbrake-autostart] keymap: setxkbmap FAILED (layout=${KEYBOARD_LAYOUT:-us}): ${setxkbmap_out}" >&2
fi

# Paint the root window in the Adwaita-dark window background so the area around
# HandBrake's window is dark instead of the default X grey.
case "${GTK_THEME}" in
    *:dark) xsetroot -solid '#242424' 2>/dev/null || true ;;
    *)      xsetroot -solid '#fafafa' 2>/dev/null || true ;;
esac

# --- Niceness ----------------------------------------------------------------
# Negative nice needs privileges the session does not have; clamp to 0..19.
NICE_LEVEL="${APP_NICENESS:-0}"
case "${NICE_LEVEL}" in
    ''|*[!0-9]*) NICE_LEVEL=0 ;;
esac
[ "${NICE_LEVEL}" -gt 19 ] && NICE_LEVEL=19

GUI_LOG="/config/handbrake-gui.log"

# --- Launch loop -------------------------------------------------------------
# HandBrake's GUI is restarted if it exits (the KEEP_APP_RUNNING equivalent).
# ghb's own stdout/stderr (GTK warnings, scan chatter) goes to ${GUI_LOG} so the
# container log stays readable and the READY banner is not buried; only the
# concise status lines below reach `docker logs`.
: > "${GUI_LOG}" 2>/dev/null || true
fast_exits=0
while true; do
    echo "[handbrake-autostart] launching HandBrake GUI (ghb, nice ${NICE_LEVEL})..." >&2
    launch_ts=$(date +%s)
    nice -n "${NICE_LEVEL}" /usr/bin/ghb >> "${GUI_LOG}" 2>&1
    rc=$?
    run_dur=$(( $(date +%s) - launch_ts ))
    echo "[handbrake-autostart] ghb exited (code ${rc}) after ${run_dur}s — see ${GUI_LOG}" >&2

    if [ "${run_dur}" -ge 60 ]; then
        fast_exits=0
    else
        fast_exits=$((fast_exits + 1))
    fi
    if [ "${fast_exits}" -ge 3 ]; then
        delay=$((15 * fast_exits))
        [ "${delay}" -gt 300 ] && delay=300
        echo "[handbrake-autostart] ghb keeps exiting fast (${fast_exits}x <60s) — backing off ${delay}s" >&2
        echo "[handbrake-autostart] last 20 lines of ${GUI_LOG}:" >&2
        tail -n 20 "${GUI_LOG}" >&2 2>/dev/null || true
        sleep "${delay}"
    else
        sleep 3
    fi
done
```

- [ ] **Step 3: Write `rootfs/defaults/startwm.sh`**

`d:\nextcloud\it\github\handbrake\rootfs\defaults\startwm.sh`:

```bash
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
```

- [ ] **Step 4: Verify**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
sh -n rootfs/defaults/autostart && echo "autostart parses"
bash -n rootfs/defaults/startwm.sh && echo "startwm parses"
bash -n rootfs/usr/local/bin/handbrake-theme.sh && echo "theme parses"
shellcheck -S warning -x -e SC1091 \
  rootfs/defaults/autostart \
  rootfs/defaults/startwm.sh \
  rootfs/usr/local/bin/handbrake-theme.sh
```
Expected:
```
autostart parses
startwm parses
theme parses
```
and shellcheck prints nothing.

- [ ] **Step 5: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add rootfs/usr/local/bin/handbrake-theme.sh rootfs/defaults/autostart rootfs/defaults/startwm.sh
git commit -m "feat: seed HandBrake's native GTK4 dark theme and wire the desktop session"
```

---

### Task 6: `init-handbrake` oneshot and the GPU seam

**Files:**
- Create: `rootfs/usr/local/bin/handbrake-gpu.sh`
- Create: `rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/run`
- Create: `rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/type`
- Create: `rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/up`
- Create: `rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/dependencies.d/init-selkies-config` (empty)
- Test/Verify: `shellcheck -S warning -x -e SC1091` clean; `bash -n` parses.

**Interfaces:**
- Consumes: `/usr/local/bin/handbrake-theme.sh` (Task 5), `/defaults/autostart` (Task 5), `/etc/handbrake-build` and the capability dumps (Task 3).
- Produces, for Tasks 7-8 and **for Plans 2 and 3**:
  - `/usr/local/bin/handbrake-gpu.sh <vendor>` — prints the extra `HandBrakeCLI` arguments for that vendor on stdout and a human-readable decision line on stderr. **This is the only file Plans 2/3 change to add NVENC / QSV / VCN argument selection.**
  - `/run/handbrake/gpu-vendor` — the normalised vendor string (`none` in v1).
  - `/run/handbrake/gpu-args` — the extra `HandBrakeCLI` arguments (empty file in v1). `handbrake-watch.sh` splices this into every invocation.
  - `/config/handbrake/watch-state/` — the watch daemon's state directory, created and chowned here.
  - `/config/.config/openbox/autostart` — refreshed from `/defaults/autostart` on every start.

- [ ] **Step 1: Write the GPU seam script**

`d:\nextcloud\it\github\handbrake\rootfs\usr\local\bin\handbrake-gpu.sh`:

```bash
#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# handbrake-gpu.sh <vendor>
# ---------------------------------------------------------------------------
# Resolves GPU_VENDOR into the extra HandBrakeCLI arguments used for hardware
# encoding. Prints the argument string on STDOUT (empty = software encoding) and
# a human-readable decision line on STDERR.
#
# v1 SHIPS NO GPU ACCELERATION. Every vendor other than "none" resolves to an
# empty argument string plus a loud warning, so a user who sets GPU_VENDOR early
# gets software encoding and a clear explanation instead of a silent failure.
#
# EXTENSION POINT — this is the ONLY place a GPU plan needs to touch:
#   * add the vendor's branch to gpu_args_for_vendor()
#   * emit the encoder identifier taken from
#     /usr/local/share/handbrake-cli-help.txt (never a guessed name)
#   * install the vendor runtime libraries in the Dockerfile
# The watch daemon and the init oneshot need no changes at all.
# ---------------------------------------------------------------------------
set -eu

VENDOR_RAW="${1:-none}"
VENDOR="$(printf '%s' "${VENDOR_RAW}" | tr '[:upper:]' '[:lower:]')"

case "${VENDOR}" in
    ""|none|off|disabled) VENDOR="none" ;;
    nvidia|nvenc)         VENDOR="nvidia" ;;
    intel|qsv)            VENDOR="intel" ;;
    amd|vce|vcn)          VENDOR="amd" ;;
    *)
        echo "[handbrake-gpu] unrecognised GPU_VENDOR='${VENDOR_RAW}' — use none, nvidia, intel or amd" >&2
        VENDOR="none"
        ;;
esac

gpu_args_for_vendor() {
    case "$1" in
        none)
            printf ''
            echo "[handbrake-gpu] GPU acceleration: none — software encoding (x264/x265)" >&2
            ;;
        *)
            printf ''
            echo "[handbrake-gpu] GPU_VENDOR='$1' requested, but this image build ships no GPU acceleration yet." >&2
            echo "[handbrake-gpu] Falling back to software encoding. Hardware encoding arrives in a later release." >&2
            ;;
    esac
}

printf '%s' "${VENDOR}" > /run/handbrake/gpu-vendor 2>/dev/null || true
gpu_args_for_vendor "${VENDOR}"
```

- [ ] **Step 2: Write `init-handbrake/run`**

`d:\nextcloud\it\github\handbrake\rootfs\etc\s6-overlay\s6-rc.d\init-handbrake\run`:

```bash
#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# -----------------------------------------------------------------------------
# init-handbrake — config bootstrap, theme, mounts and the GPU seam
# -----------------------------------------------------------------------------
# Runs as an s6-rc oneshot AFTER init-selkies-config (dependencies.d), because
# that base oneshot rewrites parts of /config and restores /etc/xdg/openbox/rc.xml
# from a .bak on EVERY start. Anything written before it can be silently undone —
# which is exactly why this repo uses no /etc/cont-init.d scripts at all.
# -----------------------------------------------------------------------------
set -e

log() { echo "[init-handbrake] $*"; }

set_env() {
    printf '%s' "$2" > "/run/s6/container_environment/$1"
}

mkdir -p /run/s6/container_environment /run/handbrake

# -- 1) Directories -----------------------------------------------------------
CONFIG_HOME="/config/.config"
mkdir -p "${CONFIG_HOME}/openbox" \
         "${CONFIG_HOME}/ghb" \
         "/config/.local/share" \
         "/config/.cache" \
         "/config/.profile.d" \
         "/config/handbrake/watch-state"

# -- 2) openbox autostart: ALWAYS refreshed from the image --------------------
cp -af /defaults/autostart "${CONFIG_HOME}/openbox/autostart"
chmod 0755 "${CONFIG_HOME}/openbox/autostart"
log "autostart synced from /defaults/autostart"

# -- 3) Theme (HandBrake's native GTK4 dark mode) -----------------------------
/usr/local/bin/handbrake-theme.sh "${HANDBRAKE_THEME:-dark}" || log "theme hook failed (non-fatal)"

# The desktop session is started by svc-de, which inherits the s6 container
# environment; the profile snippet in /config covers the paths that do not.
if [ -f /config/.profile.d/handbrake-theme.sh ]; then
    _gtk=$(grep '^export GTK_THEME=' /config/.profile.d/handbrake-theme.sh | head -1 | cut -d= -f2- | tr -d '"')
    [ -n "${_gtk}" ] && set_env GTK_THEME "${_gtk}"
fi

# X11 is the mode the whole Selkies window pipeline is built on; pin the GDK
# backend so a future base default of Wayland cannot silently change it.
set_env GDK_BACKEND    "x11"
set_env XDG_CONFIG_HOME "/config/.config"
set_env XDG_DATA_HOME   "/config/.local/share"
set_env XDG_CACHE_HOME  "/config/.cache"

# -- 4) GPU seam --------------------------------------------------------------
# v1 has no GPU acceleration; the seam exists so the watch daemon never needs to
# know about vendors. See handbrake-gpu.sh for the extension point.
if /usr/local/bin/handbrake-gpu.sh "${GPU_VENDOR:-none}" > /run/handbrake/gpu-args; then
    log "gpu-args: '$(cat /run/handbrake/gpu-args)' (vendor $(cat /run/handbrake/gpu-vendor 2>/dev/null || echo none))"
else
    : > /run/handbrake/gpu-args
    log "WARNING: handbrake-gpu.sh failed — continuing with software encoding"
fi
chmod 0644 /run/handbrake/gpu-args

# -- 5) Mount points: ownership + a LOUD warning when they are not writable ---
# Docker creates a MISSING host path as root:root, which the container user
# cannot write — conversions would then fail on every single file. chown only
# the TOP level (no -R) so we never traverse a large media share.
check_mount() {
    local dir="$1" role="$2"
    [ -d "${dir}" ] || return 0
    chown "${PUID:-911}:${PGID:-911}" "${dir}" 2>/dev/null || true
    # init-adduser has already remapped abc to PUID/PGID at this point, so
    # testing as abc is testing as the real runtime user. /usr/bin/test (not the
    # shell builtin) is what s6-setuidgid execs.
    if s6-setuidgid abc /usr/bin/test -w "${dir}" 2>/dev/null; then
        log "${role} ${dir}: writable"
    else
        log "WARNING: ${role} ${dir} is NOT writable by the container user (PUID=${PUID:-911})."
        log "         Automated conversion will fail for this folder. Fix the host share's owner,"
        log "         e.g. on the Unraid console:  chown nobody:users /mnt/user/<share>"
    fi
}
for w in /watch /watch2 /watch3 /watch4 /watch5; do
    [ -d "${w}" ] && check_mount "${w}" "watch folder"
done
check_mount "${AUTOMATED_CONVERSION_OUTPUT_DIR:-/output}" "output folder"

# -- 6) Ownership of everything we just created -------------------------------
chown -R "${PUID:-911}:${PGID:-911}" /config/.config /config/.profile.d /config/handbrake 2>/dev/null || true

# -- 7) Diagnostics -----------------------------------------------------------
if [ -f /etc/handbrake-build ]; then
    BUILD_SHA=$(grep '^sha='  /etc/handbrake-build | cut -d= -f2)
    BUILD_DATE=$(grep '^date=' /etc/handbrake-build | cut -d= -f2)
    log "BUILD: ${BUILD_SHA:0:7}  (${BUILD_DATE})"
fi
log "$(head -n 1 /usr/local/share/handbrake-version.txt 2>/dev/null || echo 'HandBrakeCLI version unknown')"
log "theme=${HANDBRAKE_THEME:-dark}  automated conversion=${AUTOMATED_CONVERSION:-1}  preset='${AUTOMATED_CONVERSION_PRESET:-General/Very Fast 1080p30}'"
log "init-handbrake done"
exit 0
```

- [ ] **Step 3: Write `init-handbrake/type`, `up` and the dependency marker**

`rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/type`:

```text
oneshot
```

`rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/up`:

```text
/etc/s6-overlay/s6-rc.d/init-handbrake/run
```

```bash
cd /d/nextcloud/it/github/handbrake
mkdir -p rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/dependencies.d
: > rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/dependencies.d/init-selkies-config
```

- [ ] **Step 4: Verify**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
bash -n rootfs/usr/local/bin/handbrake-gpu.sh && echo "gpu parses"
bash -n rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/run && echo "init parses"
shellcheck -S warning -x -e SC1091 \
  rootfs/usr/local/bin/handbrake-gpu.sh \
  rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/run
GPU_ARGS=$(bash rootfs/usr/local/bin/handbrake-gpu.sh none 2>/dev/null || true)
echo "gpu args for 'none' = '${GPU_ARGS}'"
```
Expected:
```
gpu parses
init parses
gpu args for 'none' = ''
```
and shellcheck prints nothing. (Running the script on the host writes to `/run/handbrake/...` guarded by `|| true`, so a failure there is harmless.)

- [ ] **Step 5: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add rootfs/usr/local/bin/handbrake-gpu.sh rootfs/etc/s6-overlay/s6-rc.d/init-handbrake
git commit -m "feat: add the init-handbrake oneshot and the GPU argument seam"
```

---

### Task 7: Watch-folder conversion daemon

**Files:**
- Create: `rootfs/usr/local/bin/handbrake-watch.sh`
- Create: `rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-watch/run`
- Create: `rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-watch/type`
- Create: `rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-watch/dependencies.d/init-handbrake` (empty)
- Test/Verify: `shellcheck -S warning -x -e SC1091` clean; `bash -n` parses; the real end-to-end conversion is proven in Task 10 and gated in CI in Task 12.

**Interfaces:**
- Consumes: `/run/handbrake/gpu-args` (Task 6), the `AUTOMATED_CONVERSION*` env block and `APP_NICENESS` (Task 3).
- Produces, for Task 12 (CI gate) and Plan 4 (hooks, staging dir, trash):
  - `/usr/local/bin/handbrake-watch.sh` — the daemon. Runs as `abc` via `s6-setuidgid`, logs with the `[handbrake-watch]` prefix, and is **quiet when idle** so the READY banner stays the last block in `docker logs`.
  - `/config/handbrake/watch-state/done.list` and `failed.list` — one `sha1(path)|size|mtime` key per line.
  - `/config/handbrake-watch.log` — full `HandBrakeCLI` output per job.
  - Output naming: converted files land at `<OUTPUT_DIR>[/subdir]/<basename>.<format>`, written first as `.<basename>.<format>.partial` and renamed on success (so a media scanner never sees a half-written file). Plan 4's configurable staging directory replaces only the `partial_path()` helper.
  - Function `hb_run()` is the single `HandBrakeCLI` invocation site — Plan 4's pre/post hooks wrap exactly this call.

- [ ] **Step 1: Write the daemon**

`d:\nextcloud\it\github\handbrake\rootfs\usr\local\bin\handbrake-watch.sh`:

```bash
#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# handbrake-watch.sh — automated watch-folder conversion daemon
# ---------------------------------------------------------------------------
# Polls one or more watch folders and converts every new video with
# HandBrakeCLI. Variable names deliberately mirror jlesage/docker-handbrake so a
# migrating user keeps their template values.
#
# DESIGN NOTES
#   * Runs as abc (see svc-handbrake-watch/run), so every produced file gets the
#     right ownership and the container UMASK without any chown afterwards.
#   * QUIET WHEN IDLE. The poll loop logs nothing on an empty pass; only real
#     events reach the container log. This is what keeps the "HANDBRAKE IS
#     READY" banner as the last block of `docker logs` on an idle container.
#   * A file is only picked up once it has been STABLE for
#     AUTOMATED_CONVERSION_SOURCE_STABLE_TIME seconds (size+mtime unchanged
#     between two passes), so a file still being copied in is never transcoded.
#   * Every processed source is remembered by sha1(path)|size|mtime in
#     done.list / failed.list. Re-copying or editing the source changes the key,
#     so it is picked up again; an unchanged source is never re-processed.
#   * Output is written to a hidden .partial sibling and renamed on success.
# ---------------------------------------------------------------------------
set -uo pipefail

log() { echo "[handbrake-watch] $*"; }

truthy() {
    case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

# ---- configuration ---------------------------------------------------------
PRESET="${AUTOMATED_CONVERSION_PRESET:-General/Very Fast 1080p30}"
FORMAT="$(printf '%s' "${AUTOMATED_CONVERSION_FORMAT:-mp4}" | tr '[:upper:]' '[:lower:]')"
OUTPUT_DIR="${AUTOMATED_CONVERSION_OUTPUT_DIR:-/output}"
OUTPUT_SUBDIR="${AUTOMATED_CONVERSION_OUTPUT_SUBDIR:-}"
WATCH_DIR_SETTING="${AUTOMATED_CONVERSION_WATCH_DIR:-AUTO}"
MAX_WATCH_FOLDERS="${AUTOMATED_CONVERSION_MAX_WATCH_FOLDERS:-5}"
STABLE_TIME="${AUTOMATED_CONVERSION_SOURCE_STABLE_TIME:-5}"
CHECK_INTERVAL="${AUTOMATED_CONVERSION_CHECK_INTERVAL:-5}"
NICE_LEVEL="${APP_NICENESS:-0}"

STATE_DIR="/config/handbrake/watch-state"
DONE_LIST="${STATE_DIR}/done.list"
FAILED_LIST="${STATE_DIR}/failed.list"
JOB_LOG="/config/handbrake-watch.log"

DEFAULT_VIDEO_EXTENSIONS="mkv mp4 m4v avi mov wmv flv webm mpg mpeg m2ts mts ts vob 3gp ogv divx asf rm rmvb iso"

# Numeric guards — a hand-edited template value must not break the loop.
for _var in MAX_WATCH_FOLDERS STABLE_TIME CHECK_INTERVAL NICE_LEVEL; do
    case "${!_var}" in
        ''|*[!0-9]*) printf -v "${_var}" '%s' "0" ;;
    esac
done
[ "${CHECK_INTERVAL}" -lt 1 ] && CHECK_INTERVAL=5
[ "${MAX_WATCH_FOLDERS}" -lt 1 ] && MAX_WATCH_FOLDERS=1
[ "${NICE_LEVEL}" -gt 19 ] && NICE_LEVEL=19

# Container mux name for the requested extension.
case "${FORMAT}" in
    mp4|m4v) MUX="av_mp4" ;;
    mkv)     MUX="av_mkv" ;;
    webm)    MUX="av_webm" ;;
    *)
        MUX=""
        log "WARNING: unknown AUTOMATED_CONVERSION_FORMAT='${FORMAT}' — letting the preset choose the container"
        ;;
esac

# Extension allow-list.
EXT_SETTING="${AUTOMATED_CONVERSION_VIDEO_FILE_EXTENSIONS:-}"
[ -z "${EXT_SETTING}" ] && EXT_SETTING="${DEFAULT_VIDEO_EXTENSIONS}"
read -r -a VIDEO_EXTENSIONS <<< "$(printf '%s' "${EXT_SETTING}" | tr ',' ' ' | tr '[:upper:]' '[:lower:]')"

# Extra HandBrakeCLI arguments: the GPU seam first, the user's custom args last
# (so a user can always override what the vendor branch chose).
read -r -a HB_GPU_ARGS <<< "$(cat /run/handbrake/gpu-args 2>/dev/null || true)"
read -r -a HB_EXTRA_ARGS <<< "${AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS:-}"

# ---- shutdown handling -----------------------------------------------------
CURRENT_PARTIAL=""
CURRENT_PID=""

cleanup() {
    log "stop requested — shutting down"
    if [ -n "${CURRENT_PID}" ] && kill -0 "${CURRENT_PID}" 2>/dev/null; then
        log "cancelling the running conversion (pid ${CURRENT_PID})"
        kill -TERM "${CURRENT_PID}" 2>/dev/null || true
        wait "${CURRENT_PID}" 2>/dev/null || true
    fi
    if [ -n "${CURRENT_PARTIAL}" ] && [ -e "${CURRENT_PARTIAL}" ]; then
        rm -f -- "${CURRENT_PARTIAL}"
        log "removed the partial output ${CURRENT_PARTIAL}"
    fi
    exit 0
}
trap cleanup TERM INT

# ---- helpers ---------------------------------------------------------------
file_key() {
    local f="$1" sz mt hash
    sz="$(stat -c %s -- "${f}" 2>/dev/null || echo 0)"
    mt="$(stat -c %Y -- "${f}" 2>/dev/null || echo 0)"
    hash="$(printf '%s' "${f}" | sha1sum | cut -d' ' -f1)"
    printf '%s|%s|%s' "${hash}" "${sz}" "${mt}"
}

in_list() { grep -qxF -- "$2" "$1" 2>/dev/null; }

is_video() {
    local ext="$1" e
    for e in "${VIDEO_EXTENSIONS[@]}"; do
        [ "${ext}" = "${e}" ] && return 0
    done
    return 1
}

partial_path() {
    # Plan 4 replaces this single helper when it adds a configurable staging
    # directory. Everything else in the daemon keeps working unchanged.
    printf '%s/.%s.partial' "$1" "$2"
}

hb_run() {
    # $1 = source, $2 = destination. The ONE HandBrakeCLI invocation site.
    local src="$1" dst="$2" rc
    local -a args
    args=( --preset "${PRESET}" --input "${src}" --output "${dst}" )
    [ -n "${MUX}" ] && args+=( --format "${MUX}" )
    [ "${#HB_GPU_ARGS[@]}" -gt 0 ] && args+=( "${HB_GPU_ARGS[@]}" )
    [ "${#HB_EXTRA_ARGS[@]}" -gt 0 ] && args+=( "${HB_EXTRA_ARGS[@]}" )

    {
        echo "=== $(date -Is) HandBrakeCLI ${args[*]}"
    } >> "${JOB_LOG}"

    nice -n "${NICE_LEVEL}" HandBrakeCLI "${args[@]}" >> "${JOB_LOG}" 2>&1 &
    CURRENT_PID=$!
    wait "${CURRENT_PID}"
    rc=$?
    CURRENT_PID=""
    return "${rc}"
}

# ---- watch folder resolution -----------------------------------------------
resolve_watch_dirs() {
    local -a dirs=()
    local i d
    if [ "${WATCH_DIR_SETTING}" = "AUTO" ]; then
        for (( i = 1; i <= MAX_WATCH_FOLDERS; i++ )); do
            if [ "${i}" -eq 1 ]; then d="/watch"; else d="/watch${i}"; fi
            [ -d "${d}" ] && dirs+=( "${d}" )
        done
    else
        [ -d "${WATCH_DIR_SETTING}" ] && dirs+=( "${WATCH_DIR_SETTING}" )
    fi
    printf '%s\n' "${dirs[@]:-}"
}

# ---- startup ---------------------------------------------------------------
if ! truthy "${AUTOMATED_CONVERSION:-1}"; then
    log "automated conversion is disabled (AUTOMATED_CONVERSION=${AUTOMATED_CONVERSION:-1}) — idling"
    exec sleep infinity
fi

mkdir -p "${STATE_DIR}"
touch "${DONE_LIST}" "${FAILED_LIST}" "${JOB_LOG}"

mapfile -t WATCH_DIRS < <(resolve_watch_dirs)
# mapfile keeps one empty element when resolve_watch_dirs printed nothing.
if [ "${#WATCH_DIRS[@]}" -eq 1 ] && [ -z "${WATCH_DIRS[0]}" ]; then
    WATCH_DIRS=()
fi

if [ "${#WATCH_DIRS[@]}" -eq 0 ]; then
    log "no watch folder found (AUTOMATED_CONVERSION_WATCH_DIR=${WATCH_DIR_SETTING}) — idling"
    exec sleep infinity
fi

mkdir -p "${OUTPUT_DIR}"
log "watching: ${WATCH_DIRS[*]}"
log "output:   ${OUTPUT_DIR}${OUTPUT_SUBDIR:+ (subdir ${OUTPUT_SUBDIR})}  format=${FORMAT}${MUX:+ (${MUX})}"
log "preset:   ${PRESET}   keep-source=${AUTOMATED_CONVERSION_KEEP_SOURCE:-1}   nice=${NICE_LEVEL}"
log "extensions: ${VIDEO_EXTENSIONS[*]}"
log "job log:  ${JOB_LOG}   state: ${STATE_DIR}"

declare -A SEEN_KEY
declare -A SEEN_AT

# ---- main loop -------------------------------------------------------------
while true; do
    for watch_dir in "${WATCH_DIRS[@]}"; do
        while IFS= read -r -d '' src; do
            base="$(basename -- "${src}")"
            case "${base}" in .*) continue ;; esac

            ext="$(printf '%s' "${base##*.}" | tr '[:upper:]' '[:lower:]')"
            [ "${ext}" = "${base}" ] && continue
            is_video "${ext}" || continue

            key="$(file_key "${src}")"
            in_list "${DONE_LIST}"   "${key}" && continue
            in_list "${FAILED_LIST}" "${key}" && continue

            now="$(date +%s)"
            if [ "${SEEN_KEY[${src}]:-}" != "${key}" ]; then
                SEEN_KEY["${src}"]="${key}"
                SEEN_AT["${src}"]="${now}"
                continue
            fi
            [ $(( now - ${SEEN_AT[${src}]} )) -ge "${STABLE_TIME}" ] || continue

            # -- destination -------------------------------------------------
            out_base="${OUTPUT_DIR}"
            case "${OUTPUT_SUBDIR}" in
                "") : ;;
                SAME_AS_SRC)
                    rel="${src#"${watch_dir}"/}"
                    rel_dir="$(dirname -- "${rel}")"
                    [ "${rel_dir}" != "." ] && out_base="${OUTPUT_DIR}/${rel_dir}"
                    ;;
                *) out_base="${OUTPUT_DIR}/${OUTPUT_SUBDIR}" ;;
            esac
            mkdir -p -- "${out_base}"

            stem="${base%.*}"
            dst="${out_base}/${stem}.${FORMAT}"

            if [ -e "${dst}" ] && ! truthy "${AUTOMATED_CONVERSION_OVERWRITE_OUTPUT:-0}"; then
                log "skip '${base}': ${dst} already exists (AUTOMATED_CONVERSION_OVERWRITE_OUTPUT=0)"
                printf '%s\n' "${key}" >> "${DONE_LIST}"
                continue
            fi

            CURRENT_PARTIAL="$(partial_path "${out_base}" "${stem}.${FORMAT}")"
            rm -f -- "${CURRENT_PARTIAL}"

            log "converting '${src}' -> '${dst}'"
            started="$(date +%s)"
            if hb_run "${src}" "${CURRENT_PARTIAL}" && [ -s "${CURRENT_PARTIAL}" ]; then
                mv -f -- "${CURRENT_PARTIAL}" "${dst}"
                CURRENT_PARTIAL=""
                took=$(( $(date +%s) - started ))
                log "done '${base}' in ${took}s -> ${dst}"
                if truthy "${AUTOMATED_CONVERSION_KEEP_SOURCE:-1}"; then
                    printf '%s\n' "${key}" >> "${DONE_LIST}"
                else
                    rm -f -- "${src}"
                    log "removed source '${src}' (AUTOMATED_CONVERSION_KEEP_SOURCE=0)"
                    unset "SEEN_KEY[${src}]" "SEEN_AT[${src}]"
                fi
            else
                rm -f -- "${CURRENT_PARTIAL}"
                CURRENT_PARTIAL=""
                printf '%s\n' "${key}" >> "${FAILED_LIST}"
                log "FAILED '${src}' — it will not be retried until the file changes."
                log "last 20 lines of ${JOB_LOG}:"
                tail -n 20 "${JOB_LOG}" || true
            fi
        done < <(find "${watch_dir}" -type f -print0 2>/dev/null)
    done
    sleep "${CHECK_INTERVAL}"
done
```

- [ ] **Step 2: Write `svc-handbrake-watch/run`**

`d:\nextcloud\it\github\handbrake\rootfs\etc\s6-overlay\s6-rc.d\svc-handbrake-watch\run`:

```bash
#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# Longrun: the automated watch-folder conversion daemon.
#
# Runs as abc (the PUID/PGID-remapped runtime user) so every converted file is
# created with the right ownership and the container UMASK — no post-hoc chown.
# s6-setuidgid only changes uid/gid, NOT the environment, so HOME and the XDG
# paths are set explicitly; HandBrakeCLI otherwise writes its state next to a
# root-owned HOME it cannot use.
exec s6-setuidgid abc \
    env HOME=/config \
        XDG_CONFIG_HOME=/config/.config \
        XDG_CACHE_HOME=/config/.cache \
    /usr/local/bin/handbrake-watch.sh
```

- [ ] **Step 3: Write `svc-handbrake-watch/type` and the dependency marker**

`rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-watch/type`:

```text
longrun
```

```bash
cd /d/nextcloud/it/github/handbrake
mkdir -p rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-watch/dependencies.d
: > rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-watch/dependencies.d/init-handbrake
```

- [ ] **Step 4: Verify**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
bash -n rootfs/usr/local/bin/handbrake-watch.sh && echo "watch parses"
bash -n rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-watch/run && echo "svc parses"
shellcheck -S warning -x -e SC1091 \
  rootfs/usr/local/bin/handbrake-watch.sh \
  rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-watch/run
```
Expected:
```
watch parses
svc parses
```
and shellcheck prints nothing.

- [ ] **Step 5: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add rootfs/usr/local/bin/handbrake-watch.sh rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-watch
git commit -m "feat: add the automated watch-folder conversion daemon"
```

---

### Task 8: READY banner service

**Files:**
- Create: `rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-ready/run`
- Create: `rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-ready/type`
- Create: `rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-ready/dependencies.d/init-handbrake` (empty)
- Test/Verify: `shellcheck -S warning` clean; the banner is asserted in `docker logs` in Task 10 and in CI in Task 12.

**Interfaces:**
- Consumes: `/usr/local/bin/print-banner.sh` (Task 2), `HANDBRAKE_THEME` (Task 5).
- Produces: the exact log line `  ✓ HANDBRAKE IS READY`, which the CI smoke gate greps for. Do not change that string without updating `build.yml`.

- [ ] **Step 1: Write the service**

`d:\nextcloud\it\github\handbrake\rootfs\etc\s6-overlay\s6-rc.d\svc-handbrake-ready\run`:

```bash
#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# -----------------------------------------------------------------------------
# svc-handbrake-ready — print a loud "READY" banner once the WebUI actually
# serves AND the HandBrake GUI process is alive, so the user knows the first
# start has finished. House standard: every own-image container prints an
# "<APP> IS READY" banner directly under the ASCII brand banner, as the LAST
# block of the container log.
# -----------------------------------------------------------------------------
FLAG="/run/handbrake-ready.printed"

# /run is tmpfs (wiped on every container start) -> the banner prints once per start.
if [[ -f "${FLAG}" ]]; then
    exec sleep infinity
fi

# 1) Wait for the Selkies WebUI (nginx) to accept connections on its internal
#    HTTP port (3000 is always served regardless of the HTTPS preference).
ready=0
for _ in $(seq 1 150); do
    if (exec 3<>/dev/tcp/127.0.0.1/3000) 2>/dev/null; then
        exec 3>&- 3<&-
        ready=1
        break
    fi
    sleep 2
done

# 2) Wait for the GUI process itself. A serving WebUI only proves Selkies; the
#    banner must not claim HandBrake is up while ghb is still starting or is
#    crash-looping.
gui=0
if [[ "${ready}" -eq 1 ]]; then
    for _ in $(seq 1 60); do
        if pgrep -x ghb >/dev/null 2>&1; then
            gui=1
            break
        fi
        sleep 2
    done
fi

# Small settle so HandBrake's window is actually drawn before we announce.
[[ "${gui}" -eq 1 ]] && sleep 4

case "${HANDBRAKE_THEME:-dark}" in
    light | Light | Adwaita) TH="Light" ;;
    *) TH="Dark Mode" ;;
esac

/usr/local/bin/print-banner.sh "HandBrake for Unraid" "${TH} · Selkies · GTK4" 2>/dev/null || true

if [[ "${gui}" -eq 1 ]]; then
    echo "  ✓ HANDBRAKE IS READY"
    echo "    Open the WebUI via HTTPS on port ${CUSTOM_HTTPS_PORT:-3001}"
    if [[ "${AUTOMATED_CONVERSION:-1}" != "0" ]]; then
        echo "    Watch-folder conversion is active — drop a video into /watch"
    fi
    echo ""
elif [[ "${ready}" -eq 1 ]]; then
    echo "  ! HANDBRAKE WEBUI IS UP, BUT THE GUI DID NOT START"
    echo "    Check /config/handbrake-gui.log and the log above"
    echo ""
else
    echo "  ✗ HANDBRAKE DID NOT BECOME READY"
    echo "    The WebUI never answered within 5 minutes — check the log above"
    echo ""
fi

touch "${FLAG}"
# Longrun: stay up so s6 does not restart us and re-print the banner.
exec sleep infinity
```

- [ ] **Step 2: Write `type` and the dependency marker**

`rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-ready/type`:

```text
longrun
```

```bash
cd /d/nextcloud/it/github/handbrake
mkdir -p rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-ready/dependencies.d
: > rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-ready/dependencies.d/init-handbrake
```

- [ ] **Step 3: Verify the complete rootfs tree**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
shellcheck -S warning -x -e SC1091 rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-ready/run
find rootfs -type f | sort
```
Expected file list (exactly these 25 files, no more and no less):
```
rootfs/defaults/autostart
rootfs/defaults/startwm.sh
rootfs/etc/s6-overlay/s6-rc.d/init-config-end/dependencies.d/init-handbrake
rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/dependencies.d/init-selkies-config
rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/run
rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/type
rootfs/etc/s6-overlay/s6-rc.d/init-handbrake/up
rootfs/etc/s6-overlay/s6-rc.d/init-nginx/dependencies.d/init-nologin
rootfs/etc/s6-overlay/s6-rc.d/init-nologin/run
rootfs/etc/s6-overlay/s6-rc.d/init-nologin/type
rootfs/etc/s6-overlay/s6-rc.d/init-nologin/up
rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-ready/dependencies.d/init-handbrake
rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-ready/run
rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-ready/type
rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-watch/dependencies.d/init-handbrake
rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-watch/run
rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-watch/type
rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/init-handbrake
rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/init-nologin
rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/svc-handbrake-ready
rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/svc-handbrake-watch
rootfs/usr/local/bin/handbrake-gpu.sh
rootfs/usr/local/bin/handbrake-theme.sh
rootfs/usr/local/bin/handbrake-watch.sh
rootfs/usr/local/bin/print-banner.sh
```

- [ ] **Step 4: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-ready
git commit -m "feat: add the HANDBRAKE IS READY log banner service"
```

---

### Task 9: First build and recording HandBrake's real capabilities

This is where the spec's open questions get **answered with real command output**, not restated. Do not write anything into `docs/handbrake-capabilities.md` by hand — paste what the commands print.

**Files:**
- Create: `d:\nextcloud\it\github\handbrake\docs\handbrake-capabilities.md`
- Test/Verify: the file contains the actual `HandBrakeCLI --version` string, the actual `--encoder` list and the actual preset categories from the built image.

**Interfaces:**
- Consumes: the image built from Tasks 3-8, and the in-image dumps `/usr/local/share/handbrake-version.txt`, `handbrake-cli-help.txt`, `handbrake-preset-list.txt` (Task 3).
- Produces: `docs/handbrake-capabilities.md` — **the handoff artefact Plans 2 and 3 read** to learn which hardware encoders this packaging actually compiled in, and Task 15's README wording about hardware support.

- [ ] **Step 1: Build the image**

```bash
cd /d/nextcloud/it/github/handbrake
docker build -t handbrake:dev .
```
Expected: the build succeeds and the capability layer prints, among other lines, `handbrake: HandBrake 1.11...` and a block of encoder names. If either `ghb` or `HandBrakeCLI` is missing the build fails loudly by design — fix the package names before continuing.

- [ ] **Step 2: Record the version**

Run and keep the output:
```bash
docker run --rm --entrypoint sh handbrake:dev -c 'cat /usr/local/share/handbrake-version.txt'
```

- [ ] **Step 3: Record the encoder list (answers spec open question 1)**

```bash
docker run --rm --entrypoint sh handbrake:dev -c \
  "sed -n '/-e, --encoder/,/^[[:space:]]*-[a-zA-Z-]/p' /usr/local/share/handbrake-cli-help.txt"
```
Read the output and note explicitly which of `nvenc_h264`, `nvenc_h265`, `nvenc_h265_10bit`, `nvenc_av1`, `qsv_h264`, `qsv_h265`, `qsv_av1`, `vce_h264`, `vce_h265` are present. Ubuntu's packaging builds with `--enable-nvenc` (amd64/arm64) and `--enable-qsv` (amd64) and does **not** pass `--enable-vce`, so the expectation is: NVENC and QSV encoders listed, AMD VCE encoders **absent**. Record what you actually see, not what is expected here.

- [ ] **Step 4: Record the preset catalogue (validates the default preset)**

```bash
docker run --rm --entrypoint sh handbrake:dev -c \
  "grep -E '^[A-Za-z].*/$|^ +[A-Za-z]' /usr/local/share/handbrake-preset-list.txt | head -n 60"
docker run --rm --entrypoint sh handbrake:dev -c \
  "grep -c 'Very Fast 1080p30' /usr/local/share/handbrake-preset-list.txt"
```
Expected: the second command prints a number `>= 1`. If it prints `0` the build would already have failed in Task 3 — investigate before continuing.

- [ ] **Step 5: Confirm the container-format flag spelling**

```bash
docker run --rm --entrypoint sh handbrake:dev -c \
  "sed -n '/-f, --format/,+4p' /usr/local/share/handbrake-cli-help.txt"
```
Expected: the help text names the muxers, e.g. `av_mp4`, `av_mkv`, `av_webm`. If any of the three spellings in `handbrake-watch.sh`'s `case "${FORMAT}"` block does not appear here, correct the script now and re-run Task 7's verification.

- [ ] **Step 6: Confirm HandBrake's GTK toolkit and dark-mode mechanism**

```bash
docker run --rm --entrypoint sh handbrake:dev -c \
  "ldd /usr/bin/ghb | grep -E 'gtk|adwaita' || echo 'no gtk/adwaita in ldd output'"
```
Expected: `libgtk-4.so.1` is listed and **`libadwaita` is not**. That is what makes `GTK_THEME=Adwaita:dark` the correct mechanism (a libadwaita app would ignore it and need `AdwStyleManager`). If `libadwaita` ever shows up here, the theme approach must be revisited before release.

- [ ] **Step 7: Write `docs/handbrake-capabilities.md` from the recorded output**

```bash
mkdir -p /d/nextcloud/it/github/handbrake/docs
```

Create `d:\nextcloud\it\github\handbrake\docs\handbrake-capabilities.md` with this exact skeleton and **paste the real command output** into the fenced blocks (replace every `<paste ...>` with the literal text the commands printed in Steps 2-6):

````markdown
# HandBrake capabilities in this image

Recorded from the image built at commit `<paste: git rev-parse --short HEAD>` on
`<paste: date -I>`. Regenerate with the commands below after every base-image or
HandBrake version bump — never edit this file by hand.

The same three dumps ship inside the image:

```sh
docker exec handbrake cat /usr/local/share/handbrake-version.txt
docker exec handbrake cat /usr/local/share/handbrake-cli-help.txt
docker exec handbrake cat /usr/local/share/handbrake-preset-list.txt
```

## Version

```text
<paste the output of Step 2>
```

## Video encoders (`HandBrakeCLI --help`, `-e/--encoder`)

```text
<paste the output of Step 3>
```

**Hardware encoders present in this build:** `<list the hardware encoder ids you
actually saw, or "none">`

**Hardware encoders absent:** `<list the ones you did not see>`

## Container formats (`-f/--format`)

```text
<paste the output of Step 5>
```

## Preset catalogue (first 60 lines)

```text
<paste the output of Step 4>
```

The default `AUTOMATED_CONVERSION_PRESET` is `General/Very Fast 1080p30`; the
Dockerfile fails the build if that preset disappears from the catalogue.

## GUI toolkit

```text
<paste the output of Step 6>
```

HandBrake's GUI is GTK4 without libadwaita, so the dark theme is applied through
`GTK_THEME=Adwaita:dark` (see `rootfs/usr/local/bin/handbrake-theme.sh`).
````

- [ ] **Step 8: Verify the document has no unfilled placeholders**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
grep -n '<paste' docs/handbrake-capabilities.md && echo "PLACEHOLDERS LEFT — fix them" || echo "no placeholders"
```
Expected: `no placeholders`.

- [ ] **Step 9: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add docs/handbrake-capabilities.md
git commit -m "docs: record the HandBrake encoder, preset and toolkit capabilities of this build"
```

---

### Task 10: End-to-end local verification

**Files:**
- Modify: none (this task only runs and observes; any defect found is fixed in the owning task's file and re-verified here).
- Test/Verify: every expectation below must be met before CI is written.

**Interfaces:**
- Consumes: `handbrake:dev` from Task 9.
- Produces: confidence that the CI gate written in Task 12 asserts things that genuinely hold.

- [ ] **Step 1: Boot the container**

```bash
cd /d/nextcloud/it/github/handbrake
docker rm -f hb-dev 2>/dev/null || true
docker run -d --name hb-dev -p 3000:3000 -p 3001:3001 handbrake:dev
```

- [ ] **Step 2: WebUI answers**

Run:
```bash
for i in $(seq 1 150); do
  c=$(curl -k -o /dev/null -s -w '%{http_code}' --max-time 5 https://localhost:3001/ || true)
  [ -n "$c" ] && [ "$c" != "000" ] && { echo "WebUI up after ${i}s (HTTP $c)"; break; }
  sleep 1
done
```
Expected: a line like `WebUI up after 12s (HTTP 200)`.

- [ ] **Step 3: The READY banner printed**

Run: `docker logs hb-dev 2>&1 | grep -n 'HANDBRAKE IS READY'`
Expected: one match, `  ✓ HANDBRAKE IS READY`.

- [ ] **Step 4: Dark theme is actually applied**

Run:
```bash
docker exec hb-dev cat /run/s6/container_environment/GTK_THEME; echo
docker exec hb-dev cat /config/.config/gtk-4.0/settings.ini
```
Expected: `Adwaita:dark`, then a settings file containing `gtk-application-prefer-dark-theme=1`.

- [ ] **Step 5: The GUI is alive and stays alive**

Run:
```bash
p1=$(docker exec hb-dev pgrep -x ghb | head -n1); echo "ghb pid ${p1}"
sleep 20
p2=$(docker exec hb-dev pgrep -x ghb | head -n1); echo "ghb pid after 20s ${p2}"
[ -n "$p1" ] && [ "$p1" = "$p2" ] && echo "GUI stable" || echo "GUI NOT stable — inspect /config/handbrake-gui.log"
```
Expected: the same non-empty PID twice and `GUI stable`.

- [ ] **Step 6: Look at the desktop and confirm the dark UI visually**

Open `https://localhost:3001/` in a browser. Expected: HandBrake's window is drawn in the dark Adwaita palette (dark grey window chrome, light text), maximised on the desktop, with toolbar icons visible (not empty boxes). Take a screenshot for the README (Task 15) while you are here:

```bash
mkdir -p /d/nextcloud/it/github/handbrake/.github/assets/screenshots
```

and save it as `.github/assets/screenshots/handbrake-1.png`.

While the desktop is open, also check for the spec's last open question: **does HandBrake's GUI show any forced first-run dialog** (an analogue of JDownloader's installer dialogs that would need an auto-confirm mechanism)? Note what you see. HandBrake 1.11 is expected to open straight into its main window with no modal prompt; if a dialog does appear, it must be handled before release — record it and raise it rather than shipping a container that opens onto a blocked GUI.

If the UI is **light**, the theme mechanism regressed: check `docker exec hb-dev env | grep GTK_THEME` inside the session (`docker exec hb-dev sh -c 'cat /proc/$(pgrep -x ghb)/environ | tr "\0" "\n" | grep GTK_THEME'`) — the value must be `Adwaita:dark` in ghb's own process environment.

- [ ] **Step 7: The watch daemon runs**

Run:
```bash
docker exec hb-dev pgrep -af handbrake-watch.sh
docker logs hb-dev 2>&1 | grep '\[handbrake-watch\]'
```
Expected: one process, and startup lines listing `watching: /watch /watch2 ...`, the output dir, the preset and the extension list.

- [ ] **Step 8: A real end-to-end conversion**

```bash
command -v ffmpeg >/dev/null || echo "install ffmpeg first"
ffmpeg -v error -y -f lavfi -i testsrc=size=320x240:rate=15:duration=2 \
       -f lavfi -i sine=frequency=440:duration=2 \
       -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest /tmp/hb-smoke.mkv
docker cp /tmp/hb-smoke.mkv hb-dev:/watch/hb-smoke.mkv
docker exec hb-dev chown abc:abc /watch/hb-smoke.mkv
for i in $(seq 1 180); do
  if docker exec hb-dev test -s /output/hb-smoke.mp4 2>/dev/null; then echo "converted after ${i}s"; break; fi
  sleep 1
done
docker exec hb-dev ls -l /output
docker logs hb-dev 2>&1 | grep '\[handbrake-watch\]' | tail -n 5
```
Expected: `converted after <n>s` with `n` well under 180, `/output/hb-smoke.mp4` present and non-empty, and log lines `converting '/watch/hb-smoke.mkv' -> '/output/hb-smoke.mp4'` followed by `done 'hb-smoke.mkv' in Ns -> /output/hb-smoke.mp4`.

- [ ] **Step 9: The source is not re-processed**

Run:
```bash
sleep 20
docker logs hb-dev 2>&1 | grep -c "converting '/watch/hb-smoke.mkv'"
docker exec hb-dev cat /config/handbrake/watch-state/done.list
```
Expected: the count is exactly `1`, and `done.list` holds one `<sha1>|<size>|<mtime>` line.

- [ ] **Step 10: No login prompt by default**

Run: `curl -k -o /dev/null -s -w '%{http_code}\n' https://localhost:3001/`
Expected: `200` (not `401`).

- [ ] **Step 11: Graceful stop leaves no partial file**

```bash
ffmpeg -v error -y -f lavfi -i testsrc=size=1920x1080:rate=30:duration=120 \
       -c:v libx264 -pix_fmt yuv420p /tmp/hb-long.mkv
docker cp /tmp/hb-long.mkv hb-dev:/watch/hb-long.mkv
docker exec hb-dev chown abc:abc /watch/hb-long.mkv
sleep 20
docker exec hb-dev sh -c 'ls -a /output'
docker stop hb-dev
docker start hb-dev
sleep 15
docker exec hb-dev sh -c 'ls -a /output'
```
Expected: during the run `/output` contains a `.hb-long.mp4.partial` file; after `docker stop` and a restart that partial file is **gone** (the daemon's SIGTERM trap removed it) and the job restarts from scratch.

- [ ] **Step 12: Clean up**

```bash
docker rm -f hb-dev
rm -f /tmp/hb-smoke.mkv /tmp/hb-long.mkv
```

- [ ] **Step 13: Commit the screenshot**

```bash
cd /d/nextcloud/it/github/handbrake
git add .github/assets/screenshots/handbrake-1.png
git commit -m "docs: add the HandBrake dark-mode WebUI screenshot"
```

---

### Task 11: Lint workflow

**Files:**
- Create: `d:\nextcloud\it\github\handbrake\.github\workflows\lint.yml`
- Test/Verify: the same commands run locally and pass.

**Interfaces:**
- Consumes: `Dockerfile`, `rootfs/**`.
- Produces: the `Lint` check whose green state is a precondition for tagging (Task 16).

- [ ] **Step 1: Write the workflow**

`d:\nextcloud\it\github\handbrake\.github\workflows\lint.yml`:

```yaml
name: Lint

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
  workflow_dispatch:

jobs:
  hadolint:
    name: Hadolint (Dockerfile)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: hadolint/hadolint-action@v3.4.0
        with:
          dockerfile: Dockerfile
          # DL3008 = pin apt versions — deliberately skipped, the package set
          #          moves with the Ubuntu series of the Selkies base.
          # DL3009 = clean apt lists — cleaned once at the end of the install
          #          layer instead of after every RUN.
          ignore: DL3008,DL3009
          failure-threshold: warning

  shellcheck:
    name: ShellCheck (shipped scripts)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - name: Run shellcheck
        run: |
          sudo apt-get update
          sudo apt-get install -y shellcheck
          # Everything shipped into the image that a shell executes: *.sh, the
          # extensionless s6-rc.d service scripts (run) and the openbox
          # autostart. Shebangs are honored (no forced --shell); the
          # with-contenv scripts carry a "shellcheck shell=bash" directive.
          SCRIPTS=$(find rootfs -type f \( -name '*.sh' -o -name 'run' -o -name 'autostart' \))

          if [ -z "${SCRIPTS}" ]; then
            echo "ERROR: no shell scripts found — the find pattern is broken." >&2
            exit 1
          fi

          echo "Checking the following scripts:"
          echo "${SCRIPTS}"
          echo "---"

          # -S warning: fail on warnings and up
          # -x:         follow sourced files
          # -e SC1091:  allow sourcing files that do not exist at lint time
          # shellcheck disable=SC2086
          shellcheck -S warning -x -e SC1091 ${SCRIPTS}

          echo "All scripts passed shellcheck."

  xml-validate:
    name: XML Validation
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - name: Validate XML files
        run: |
          sudo apt-get update
          sudo apt-get install -y libxml2-utils
          found=0
          for f in $(find . -name '*.xml' -not -path './.git/*'); do
            echo "Checking $f"
            xmllint --noout "$f"
            found=1
          done
          [ "$found" -eq 0 ] && echo "No XML files in this repo — nothing to validate."
          exit 0

  line-endings:
    name: Line endings (rootfs must be LF)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - name: Reject CR in shipped files
        run: |
          set -euo pipefail
          # A CRLF checkout breaks every shebang inside the image. .gitattributes
          # prevents it, but a file committed with `-c core.autocrlf=false` from a
          # Windows editor could still slip through — fail loudly here.
          if grep -rlI $'\r' rootfs .github/assets/banner-raw.txt .github/workflows 2>/dev/null; then
            echo "::error::the files listed above contain CR characters — they must be LF only"
            exit 1
          fi
          echo "No CR characters in rootfs/, the banner or the workflows."
```

- [ ] **Step 2: Verify locally**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
hadolint Dockerfile --ignore DL3008 --ignore DL3009
SCRIPTS=$(find rootfs -type f \( -name '*.sh' -o -name 'run' -o -name 'autostart' \))
echo "$SCRIPTS"
# shellcheck disable=SC2086
shellcheck -S warning -x -e SC1091 $SCRIPTS && echo "shellcheck OK"
grep -rlI $'\r' rootfs .github/assets/banner-raw.txt .github/workflows && echo "CR FOUND — fix" || echo "LF OK"
```
Expected: hadolint silent, `shellcheck OK`, `LF OK`, and the script list containing exactly ten paths — the four s6 `run` scripts (`init-nologin`, `init-handbrake`, `svc-handbrake-watch`, `svc-handbrake-ready`), `rootfs/defaults/autostart`, and the five `*.sh` files (`defaults/startwm.sh`, `print-banner.sh`, `handbrake-theme.sh`, `handbrake-gpu.sh`, `handbrake-watch.sh`).

- [ ] **Step 3: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add .github/workflows/lint.yml
git commit -m "ci: add the lint workflow (hadolint, shellcheck, xmllint, LF guard)"
```

---

### Task 12: Build workflow with the real boot-smoke gate

**Files:**
- Create: `d:\nextcloud\it\github\handbrake\.github\workflows\build.yml`
- Test/Verify: pushed to `main`, the workflow must go green on both arches.

**Interfaces:**
- Consumes: `Dockerfile`, the `  ✓ HANDBRAKE IS READY` log line (Task 8), `GTK_THEME` in the s6 container environment (Task 5), the watch daemon's `/output` behaviour (Task 7).
- Produces: `ghcr.io/junkerderprovinz/handbrake` (and the Docker Hub mirror once `DOCKERHUB_USERNAME`/`DOCKERHUB_TOKEN` exist) as a multi-arch manifest, plus the `Build & Push` check that gates tagging.

- [ ] **Step 1: Write the workflow**

`d:\nextcloud\it\github\handbrake\.github\workflows\build.yml`:

```yaml
name: Build & Push

# -----------------------------------------------------------------------------
# Builds the HandBrake-on-Selkies image and pushes it to:
#   * GitHub Container Registry  (ghcr.io/junkerderprovinz/handbrake)
#   * Docker Hub                 (docker.io/<DOCKERHUB_USERNAME>/handbrake)
#     — active only once the DOCKERHUB_USERNAME variable and DOCKERHUB_TOKEN
#       secret are set together; until then the build stays GHCR-only.
#
# Architecture: one NATIVE build job per platform (amd64 on ubuntu-latest,
# arm64 on ubuntu-24.04-arm — free for public repos). Each job boots its image
# and runs the full smoke gate, including a REAL transcode, then pushes by
# digest; a merge job assembles the multi-arch manifest under the final tags.
# Native beats QEMU here because the gate actually encodes video: a HandBrake
# run under arm64 emulation would take minutes and time the gate out.
#
# Triggers:
#   * Push to main           -> tags: latest, sha-<short>
#   * Tag v*.*.*             -> tags: latest, <version>, <major>, <major>.<minor>
#   * Weekly cron (Sun 04 UTC) — picks up upstream Selkies base updates
#   * Manual workflow_dispatch
# -----------------------------------------------------------------------------

on:
  push:
    branches: [ main ]
    tags: [ 'v*.*.*' ]
  schedule:
    - cron: '0 4 * * 0'
  workflow_dispatch:

env:
  IMAGE_NAME: handbrake

jobs:
  build:
    strategy:
      fail-fast: true
      matrix:
        include:
          - platform: linux/amd64
            arch: amd64
            runner: ubuntu-latest
          - platform: linux/arm64
            arch: arm64
            runner: ubuntu-24.04-arm
    runs-on: ${{ matrix.runner }}
    permissions:
      contents: read
      packages: write
      security-events: write

    steps:
      - name: Checkout
        uses: actions/checkout@v7

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v4

      - name: Login to GHCR
        uses: docker/login-action@v4
        with:
          registry: ghcr.io
          username: ${{ github.repository_owner }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata (labels)
        id: meta
        uses: docker/metadata-action@v6
        with:
          images: ghcr.io/${{ github.repository_owner }}/${{ env.IMAGE_NAME }}

      - name: Build ${{ matrix.arch }} image for the smoke gate
        uses: docker/build-push-action@v7
        with:
          context: .
          file: ./Dockerfile
          platforms: ${{ matrix.platform }}
          push: false
          load: true
          tags: handbrake:smoke-${{ matrix.arch }}
          build-args: |
            BUILD_SHA=${{ github.sha }}
            BUILD_DATE=${{ github.event.repository.updated_at }}
          cache-from: type=gha,scope=build-${{ matrix.arch }}

      # ---------------------------------------------------------------------
      # SMOKE GATE. A green docker build only proves the image BUILDS. This
      # proves it boots, serves the WebUI, keeps HandBrake's GUI alive, applies
      # the dark theme, and actually transcodes a video end to end.
      # ---------------------------------------------------------------------
      - name: Smoke test — ${{ matrix.arch }} must boot, stay up and transcode
        run: |
          set -euo pipefail
          img=handbrake:smoke-${{ matrix.arch }}
          name=hb-smoke

          fail() {
            echo "::error::$1"
            echo "---- container log ----"
            docker logs "$name" 2>&1 | tail -n 120 || true
            echo "---- GUI log ----"
            docker exec "$name" cat /config/handbrake-gui.log 2>/dev/null | tail -n 60 || true
            echo "---- watch job log ----"
            docker exec "$name" cat /config/handbrake-watch.log 2>/dev/null | tail -n 60 || true
            docker rm -f "$name" >/dev/null 2>&1 || true
            exit 1
          }

          echo "== static asserts =="
          docker run --rm --entrypoint sh "$img" -c 'test -x /usr/bin/ghb' \
            || { echo "::error::/usr/bin/ghb missing from the image"; exit 1; }
          docker run --rm --entrypoint sh "$img" -c 'HandBrakeCLI --version' \
            || { echo "::error::HandBrakeCLI does not run"; exit 1; }

          echo "== boot =="
          docker run -d --name "$name" -p 3000:3000 -p 3001:3001 "$img"

          up() {
            local c
            c=$(curl -k -o /dev/null -s -w '%{http_code}' --max-time 5 https://localhost:3001/ || true)
            { [ -n "$c" ] && [ "$c" != "000" ]; } && return 0
            c=$(curl -o /dev/null -s -w '%{http_code}' --max-time 5 http://localhost:3000/ || true)
            { [ -n "$c" ] && [ "$c" != "000" ]; } && return 0
            return 1
          }

          # Real 180s wall-clock deadline (each probe can spend ~10s in curl
          # timeouts, so an iteration counter would overshoot badly).
          deadline=$((SECONDS + 180))
          webui=0
          while [ "$SECONDS" -lt "$deadline" ]; do
            if up; then echo "WebUI responded after ${SECONDS}s"; webui=1; break; fi
            if [ -z "$(docker ps -q --filter "name=$name")" ]; then fail "container exited early"; fi
            sleep 1
          done
          [ "$webui" -eq 1 ] || fail "WebUI did not respond within 180s"

          echo "== dark theme =="
          theme=$(docker exec "$name" cat /run/s6/container_environment/GTK_THEME 2>/dev/null || echo "")
          echo "GTK_THEME=${theme}"
          [ "$theme" = "Adwaita:dark" ] || fail "GTK_THEME is '${theme}', expected 'Adwaita:dark' (dark must be the default)"

          echo "== HandBrake GUI is up and STAYS up =="
          pid1=""
          deadline=$((SECONDS + 120))
          while [ "$SECONDS" -lt "$deadline" ]; do
            pid1=$(docker exec "$name" pgrep -x ghb 2>/dev/null | head -n1 || true)
            [ -n "$pid1" ] && break
            sleep 2
          done
          [ -n "$pid1" ] || fail "the ghb GUI process never started"
          echo "ghb pid ${pid1}; holding 20s to prove it is not crash-looping"
          sleep 20
          pid2=$(docker exec "$name" pgrep -x ghb 2>/dev/null | head -n1 || true)
          [ -n "$pid2" ] || fail "the ghb GUI process died within 20s"
          [ "$pid1" = "$pid2" ] || fail "ghb restarted within 20s (pid ${pid1} -> ${pid2}) — crash loop"
          echo "ghb stayed up with an unchanged pid"

          echo "== watch daemon is up =="
          docker exec "$name" pgrep -f handbrake-watch.sh >/dev/null 2>&1 \
            || fail "the watch-folder daemon is not running"

          echo "== READY banner printed =="
          docker logs "$name" 2>&1 | grep -q 'HANDBRAKE IS READY' \
            || fail "the READY banner never printed"

          echo "== end-to-end transcode =="
          command -v ffmpeg >/dev/null 2>&1 || { sudo apt-get update -qq && sudo apt-get install -y -qq ffmpeg; }
          ffmpeg -v error -y -f lavfi -i testsrc=size=320x240:rate=15:duration=2 \
                 -f lavfi -i sine=frequency=440:duration=2 \
                 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest /tmp/hb-smoke.mkv
          docker cp /tmp/hb-smoke.mkv "$name":/watch/hb-smoke.mkv
          docker exec "$name" chown abc:abc /watch/hb-smoke.mkv
          converted=0
          deadline=$((SECONDS + 240))
          while [ "$SECONDS" -lt "$deadline" ]; do
            if docker exec "$name" test -s /output/hb-smoke.mp4 2>/dev/null; then converted=1; break; fi
            sleep 2
          done
          [ "$converted" -eq 1 ] || fail "the watch folder never produced /output/hb-smoke.mp4 within 240s"
          size=$(docker exec "$name" stat -c %s /output/hb-smoke.mp4)
          echo "converted file is ${size} bytes"
          [ "$size" -gt 1000 ] || fail "/output/hb-smoke.mp4 is suspiciously small (${size} bytes)"
          docker exec "$name" sh -c 'ls -a /output | grep -q "\.partial$"' \
            && fail "a .partial staging file was left behind in /output"

          echo "✅ smoke gate passed on ${{ matrix.arch }}"
          docker rm -f "$name" >/dev/null

      # CVE scan of the locally-loaded smoke image. Report-only: exit-code 0 so
      # a HIGH/CRITICAL finding never blocks the build — results land in the
      # repo's Security tab. ignore-unfixed hides CVEs with no upstream fix.
      - name: Scan image for CVEs (Trivy)
        uses: aquasecurity/trivy-action@v0.36.0
        with:
          image-ref: handbrake:smoke-${{ matrix.arch }}
          format: sarif
          output: trivy-results-${{ matrix.arch }}.sarif
          severity: HIGH,CRITICAL
          ignore-unfixed: true
          exit-code: "0"     # MUST stay 0 — report only, never fail the build

      - name: Upload Trivy results to the Security tab
        if: ${{ github.event_name != 'pull_request' }}
        uses: github/codeql-action/upload-sarif@v4
        with:
          sarif_file: trivy-results-${{ matrix.arch }}.sarif
          category: trivy-${{ matrix.arch }}

      - name: Push ${{ matrix.arch }} by digest
        id: push
        uses: docker/build-push-action@v7
        with:
          context: .
          file: ./Dockerfile
          platforms: ${{ matrix.platform }}
          labels: ${{ steps.meta.outputs.labels }}
          build-args: |
            BUILD_SHA=${{ github.sha }}
            BUILD_DATE=${{ github.event.repository.updated_at }}
          outputs: type=image,name=ghcr.io/${{ github.repository_owner }}/${{ env.IMAGE_NAME }},push-by-digest=true,name-canonical=true,push=true
          cache-from: type=gha,scope=build-${{ matrix.arch }}
          cache-to: type=gha,mode=max,scope=build-${{ matrix.arch }}

      - name: Export digest
        run: |
          mkdir -p /tmp/digests
          digest="${{ steps.push.outputs.digest }}"
          touch "/tmp/digests/${digest#sha256:}"

      - name: Upload digest
        uses: actions/upload-artifact@v7
        with:
          name: digests-${{ matrix.arch }}
          path: /tmp/digests/*
          if-no-files-found: error
          retention-days: 1

  merge:
    needs: build
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Download digests
        uses: actions/download-artifact@v8
        with:
          path: /tmp/digests
          pattern: digests-*
          merge-multiple: true

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v4

      - name: Login to GHCR
        uses: docker/login-action@v4
        with:
          registry: ghcr.io
          username: ${{ github.repository_owner }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Login to Docker Hub
        if: ${{ vars.DOCKERHUB_USERNAME != '' }}
        uses: docker/login-action@v4
        with:
          username: ${{ vars.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v6
        with:
          images: |
            ghcr.io/${{ github.repository_owner }}/${{ env.IMAGE_NAME }}
            name=docker.io/${{ vars.DOCKERHUB_USERNAME }}/${{ env.IMAGE_NAME }},enable=${{ vars.DOCKERHUB_USERNAME != '' }}
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=semver,pattern={{major}}
            type=schedule,pattern=weekly
            type=raw,value=latest,enable={{is_default_branch}}
            type=sha,format=short

      - name: Create multi-arch manifests
        working-directory: /tmp/digests
        # tags come from the DOCKER_METADATA_OUTPUT_TAGS env the metadata action
        # exports — no ${{ }} interpolation inside the script (injection hygiene)
        run: |
          set -euo pipefail
          src="ghcr.io/${{ github.repository_owner }}/${{ env.IMAGE_NAME }}"
          sources=""
          for d in *; do sources="$sources ${src}@sha256:${d}"; done
          echo "sources:${sources}"
          tagargs=""
          while IFS= read -r tag; do
            [ -n "$tag" ] && tagargs="$tagargs -t $tag"
          done <<< "$DOCKER_METADATA_OUTPUT_TAGS"
          echo "tags:${tagargs}"
          # Cross-registry copy (GHCR -> Docker Hub) can hit a transient HTTP/2
          # PROTOCOL_ERROR on large layers; retry a few times before failing.
          n=0
          until docker buildx imagetools create ${tagargs} ${sources}; do
            n=$((n + 1))
            if [ "$n" -ge 4 ]; then echo "imagetools create failed after $n attempts"; exit 1; fi
            echo "imagetools create failed (attempt $n); retrying in $((n * 15))s..."
            sleep $((n * 15))
          done

      - name: Inspect
        run: |
          docker buildx imagetools inspect ghcr.io/${{ github.repository_owner }}/${{ env.IMAGE_NAME }}:${{ steps.meta.outputs.version }}

      # Mirror the GitHub README to the Docker Hub repo description. Editing the
      # description needs a credential the push token lacks (it returns 403), so
      # this uses a separate DOCKERHUB_PASSWORD secret. Skipped until that
      # secret is set, so a missing credential never fails the build.
      - name: Checkout (README for the Docker Hub sync)
        if: ${{ vars.DOCKERHUB_USERNAME != '' && github.event_name != 'pull_request' }}
        uses: actions/checkout@v7

      - name: Docker Hub description sync ready?
        id: dhdesc
        if: ${{ vars.DOCKERHUB_USERNAME != '' && github.event_name != 'pull_request' }}
        env:
          PW: ${{ secrets.DOCKERHUB_PASSWORD }}
        run: |
          if [ -n "$PW" ]; then
            echo "go=true" >> "$GITHUB_OUTPUT"
          else
            echo "DOCKERHUB_PASSWORD not set — skipping the Docker Hub description sync"
            echo "go=false" >> "$GITHUB_OUTPUT"
          fi

      - name: Sync README to Docker Hub
        if: ${{ steps.dhdesc.outputs.go == 'true' }}
        uses: peter-evans/dockerhub-description@v5
        with:
          username: ${{ vars.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_PASSWORD }}
          repository: ${{ vars.DOCKERHUB_USERNAME }}/${{ env.IMAGE_NAME }}
          short-description: "HandBrake video transcoder for Unraid, in your browser via Selkies, dark by default."
          enable-url-completion: true
```

- [ ] **Step 2: Verify the YAML parses**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/build.yml')); print('build.yml OK')"
python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/lint.yml')); print('lint.yml OK')"
```
Expected: `build.yml OK` and `lint.yml OK`.

- [ ] **Step 3: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add .github/workflows/build.yml
git commit -m "ci: add the multi-arch build with a transcoding boot-smoke gate"
```

---

### Task 13: Release and registry-cleanup workflows

**Files:**
- Create: `d:\nextcloud\it\github\handbrake\.github\workflows\release.yml`
- Create: `d:\nextcloud\it\github\handbrake\.github\workflows\registry-cleanup.yml`
- Test/Verify: both parse as YAML; `release.yml` is only exercised in Task 16.

**Interfaces:**
- Consumes: `.github/release-notes/vX.Y.Z.md` (Task 16).
- Produces: the GitHub release whose title is the bare version and whose body is the hand-written notes file.

- [ ] **Step 1: Write `release.yml`**

`d:\nextcloud\it\github\handbrake\.github\workflows\release.yml`:

```yaml
name: Release

# Creates a GitHub Release whenever a semver tag (vX.Y.Z) is pushed. The body is
# the hand-written .github/release-notes/<tag>.md; auto-generated notes are only
# a fallback for a tag that was cut without a notes file.
# House rule: the release TITLE is the bare version (vX.Y.Z) — no repo name, no
# extra heading inside the body.

on:
  push:
    tags:
      - "v*.*.*"
  workflow_dispatch:
    inputs:
      tag:
        description: "Tag to release (e.g. v1.0.0)"
        required: true

permissions:
  contents: write

jobs:
  release:
    name: Create GitHub Release
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v7
        with:
          fetch-depth: 0

      - name: Resolve tag
        id: tag
        run: |
          if [ "${{ github.event_name }}" = "workflow_dispatch" ]; then
            echo "tag=${{ github.event.inputs.tag }}" >> "$GITHUB_OUTPUT"
          else
            echo "tag=${GITHUB_REF_NAME}" >> "$GITHUB_OUTPUT"
          fi

      - name: Check for release notes file
        id: notes
        run: |
          TAG="${{ steps.tag.outputs.tag }}"
          NOTES_FILE=".github/release-notes/${TAG}.md"
          # If the notes file is not in the tagged commit, fetch it from main.
          if [ ! -f "${NOTES_FILE}" ]; then
            git fetch origin main --depth=1 2>/dev/null || true
            mkdir -p .github/release-notes
            git show "origin/main:${NOTES_FILE}" > "${NOTES_FILE}" 2>/dev/null || true
          fi
          if [ -s "${NOTES_FILE}" ]; then
            echo "Using release notes from ${NOTES_FILE}"
            echo "notes_file=${NOTES_FILE}" >> "$GITHUB_OUTPUT"
          else
            echo "No release notes file at ${NOTES_FILE}; will auto-generate."
            echo "notes_file=" >> "$GITHUB_OUTPUT"
          fi

      - name: Create GitHub Release (with notes file)
        if: steps.notes.outputs.notes_file != ''
        uses: softprops/action-gh-release@v3
        with:
          tag_name: ${{ steps.tag.outputs.tag }}
          body_path: ${{ steps.notes.outputs.notes_file }}
          generate_release_notes: false
          make_latest: true

      - name: Create GitHub Release (auto-generated fallback)
        if: steps.notes.outputs.notes_file == ''
        uses: softprops/action-gh-release@v3
        with:
          tag_name: ${{ steps.tag.outputs.tag }}
          generate_release_notes: true
          make_latest: true
```

- [ ] **Step 2: Write `registry-cleanup.yml`**

`d:\nextcloud\it\github\handbrake\.github\workflows\registry-cleanup.yml`:

```yaml
name: Registry Cleanup

# Manual maintenance tool: deletes ONE image tag from GHCR and Docker Hub.
# Safety: refuses to delete a GHCR version that also carries the "latest" tag.

on:
  workflow_dispatch:
    inputs:
      tag:
        description: "Image tag to delete (e.g. 1.0.1)"
        required: true

env:
  IMAGE_NAME: handbrake

jobs:
  cleanup:
    runs-on: ubuntu-latest
    permissions:
      packages: write
    steps:
      - name: Delete tag from GHCR
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          TAG: ${{ inputs.tag }}
        run: |
          set -euo pipefail
          api="/users/${{ github.repository_owner }}/packages/container/${IMAGE_NAME}"
          if ! versions=$(gh api --paginate "${api}/versions"); then
            echo "::warning::GHCR: listing versions failed (token scope?) — skipping GHCR"
            exit 0
          fi
          id=$(echo "$versions" | jq -r --arg t "$TAG" \
            '.[] | select(.metadata.container.tags | index($t)) | .id' | head -1)
          if [ -z "$id" ]; then
            echo "GHCR: no version tagged '$TAG' — nothing to do"
            exit 0
          fi
          tags=$(echo "$versions" | jq -r --arg t "$TAG" \
            '.[] | select(.metadata.container.tags | index($t)) | .metadata.container.tags | join(", ")')
          echo "GHCR: version $id carries tags: $tags"
          case ", $tags," in
            *", latest,"*)
              echo "::error::Refusing to delete: this version also carries 'latest'"
              exit 1
              ;;
          esac
          gh api -X DELETE "${api}/versions/${id}"
          echo "GHCR: deleted version $id (tag $TAG)"

      - name: Delete tag from Docker Hub
        if: ${{ vars.DOCKERHUB_USERNAME != '' }}
        env:
          DH_USER: ${{ vars.DOCKERHUB_USERNAME }}
          DH_PASS: ${{ secrets.DOCKERHUB_PASSWORD }}
          TAG: ${{ inputs.tag }}
        run: |
          set -euo pipefail
          if [ -z "$DH_PASS" ]; then
            echo "::warning::DOCKERHUB_PASSWORD not set — skipping Docker Hub"
            exit 0
          fi
          jwt=$(curl -s -X POST -H "Content-Type: application/json" \
            -d "{\"username\":\"$DH_USER\",\"password\":\"$DH_PASS\"}" \
            https://hub.docker.com/v2/users/login/ | jq -r .token)
          if [ -z "$jwt" ] || [ "$jwt" = "null" ]; then
            echo "::error::Docker Hub login failed"
            exit 1
          fi
          code=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE \
            -H "Authorization: JWT $jwt" \
            "https://hub.docker.com/v2/repositories/${DH_USER}/${IMAGE_NAME}/tags/${TAG}/")
          echo "Docker Hub: DELETE tags/${TAG} -> HTTP $code"
          case "$code" in
            2*) echo "Docker Hub: deleted" ;;
            404) echo "Docker Hub: tag already gone" ;;
            *) echo "::error::Docker Hub: unexpected status $code"; exit 1 ;;
          esac
```

- [ ] **Step 3: Verify**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
python -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml')); print('release.yml OK')"
python -c "import yaml; yaml.safe_load(open('.github/workflows/registry-cleanup.yml')); print('registry-cleanup.yml OK')"
```
Expected: `release.yml OK` and `registry-cleanup.yml OK`.

- [ ] **Step 4: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add .github/workflows/release.yml .github/workflows/registry-cleanup.yml
git commit -m "ci: add the release and registry-cleanup workflows"
```

---

### Task 14: `justfile` and `CLAUDE.md`

**Files:**
- Create: `d:\nextcloud\it\github\handbrake\justfile`
- Create: `d:\nextcloud\it\github\handbrake\CLAUDE.md`
- Test/Verify: `just --list` shows every recipe; `just check` passes.

**Interfaces:**
- Consumes: everything built so far.
- Produces: `just check` (the pre-push lint chain) and `just smoke` (the local boot gate) that later plans reuse verbatim.

- [ ] **Step 1: Write the `justfile`**

`d:\nextcloud\it\github\handbrake\justfile`:

```makefile
# HandBrake (Unraid container) task runner — run `just` to list recipes.
# Recipes use sh (Git Bash on Windows). See CLAUDE.md for the full guide.
# This is a container repo: no Go, no Node app — the deliverable is the image.

set shell := ["sh", "-cu"]

# List available recipes
default:
    @just --list

# Build the image locally (same tag the CI gate uses)
build:
    docker build -t handbrake:smoke-amd64 .

# Build + boot the container locally (Ctrl-C to stop; WebUI on 3000/HTTP, 3001/HTTPS)
smoke: build
    docker run --rm -it --name hb-smoke -p 3000:3000 -p 3001:3001 handbrake:smoke-amd64

# End-to-end watch-folder test against a running `just smoke` container
convert-test:
    ffmpeg -v error -y -f lavfi -i testsrc=size=320x240:rate=15:duration=2 -c:v libx264 -pix_fmt yuv420p /tmp/hb-smoke.mkv
    docker cp /tmp/hb-smoke.mkv hb-smoke:/watch/hb-smoke.mkv
    docker exec hb-smoke chown abc:abc /watch/hb-smoke.mkv
    @echo "dropped /watch/hb-smoke.mkv — watch: docker logs -f hb-smoke"

# Lint the Dockerfile (same ignores as CI)
hadolint:
    hadolint Dockerfile --ignore DL3008 --ignore DL3009

# ShellCheck every shipped script (honor shebangs; no --shell override, like CI)
shellcheck:
    find rootfs -type f \( -name '*.sh' -o -name 'run' -o -name 'autostart' \) -print0 \
      | xargs -0 shellcheck -S warning -x -e SC1091

# Validate every XML file (Unraid template etc.)
xml:
    find . -name '*.xml' -not -path './.git/*' -print0 | xargs -0 -r xmllint --noout

# Reject CR characters in anything that ships into the Linux image
lf:
    ! grep -rlI "$(printf '\r')" rootfs .github/assets/banner-raw.txt .github/workflows

# Full pre-push chain: every lint CI runs
check: hadolint shellcheck xml lf
    @echo "All lint checks passed."

# Secret-scan the working tree
secrets:
    gitleaks dir . --redact --no-banner

# Re-record docs/handbrake-capabilities.md inputs from a built image
caps:
    docker run --rm --entrypoint sh handbrake:smoke-amd64 -c 'cat /usr/local/share/handbrake-version.txt'
    docker run --rm --entrypoint sh handbrake:smoke-amd64 -c "sed -n '/-e, --encoder/,/^[[:space:]]*-[a-zA-Z-]/p' /usr/local/share/handbrake-cli-help.txt"

# Regenerate the README banner pair
banner:
    node .github/assets/gen-banner.mjs

# Scaffold release notes for a version, e.g. `just notes 1.1.0`
notes version:
    printf '## ✨ Added\n\n## ⚡ Improved\n\n## 🐛 Fixed\n' > .github/release-notes/v{{version}}.md
    @echo "Wrote .github/release-notes/v{{version}}.md — edit it, then commit (NEVER tag without approval)."
```

- [ ] **Step 2: Write `CLAUDE.md`**

`d:\nextcloud\it\github\handbrake\CLAUDE.md`:

```markdown
# CLAUDE.md — HandBrake for Unraid (Selkies)

Guide for working in this repo. Owner: `junkerderprovinz`. Public repo.

## What this is

An **own-image container** repo: HandBrake (the GTK4 video transcoder) packaged
on top of `ghcr.io/linuxserver/baseimage-selkies`, streamed to the browser via
Selkies, dark by default, with an automated watch-folder conversion daemon.
There is **no Go, no Node app, no Python service** — the deliverable is the
Docker image. `.github/assets/gen-banner.mjs` is a one-off asset generator, not
part of the runtime.

## Layout

- `Dockerfile` — the whole build. Single stage on the Selkies base: apt-installs
  `handbrake` (`/usr/bin/ghb`, GTK4) and `handbrake-cli` (`/usr/bin/HandBrakeCLI`)
  from Ubuntu universe, asserts both binaries exist, and records
  `/usr/local/share/handbrake-{version,cli-help,preset-list}.txt` into the image.
- `rootfs/` — everything shipped into the image (LF-only, see `.gitattributes`):
  - `rootfs/etc/s6-overlay/s6-rc.d/` — s6-overlay v3 init. **No `/etc/cont-init.d`
    is used**: the Selkies base rewrites `/config` and restores openbox's
    `rc.xml` in `init-selkies-config`, which runs *after* the legacy cont-init
    stage, so anything written there can be silently undone.
    Services: `init-nologin`, `init-handbrake` (oneshots),
    `svc-handbrake-watch`, `svc-handbrake-ready` (longruns).
  - `rootfs/usr/local/bin/` — `handbrake-theme.sh`, `handbrake-gpu.sh`,
    `handbrake-watch.sh`, `print-banner.sh`.
  - `rootfs/defaults/` — `autostart` (openbox session, POSIX sh only) and
    `startwm.sh`.
- `.github/workflows/` — `build.yml`, `lint.yml`, `release.yml`,
  `registry-cleanup.yml`.
- `.github/release-notes/<tag>.md` — per-release notes consumed by `release.yml`.
- `.github/assets/` — banner/icon sources and the generator.
- `docs/handbrake-capabilities.md` — the recorded encoder/preset/toolkit
  capabilities of the current build. Regenerate it after every version bump.

The Unraid Community Applications **template XML lives in the central
`unraid-apps` feed repo, not here.**

## Build / test / lint

`just --list` shows the wrapped flows. The underlying commands:

```sh
docker build -t handbrake:dev .
docker run -d --name hb -p 3000:3000 -p 3001:3001 handbrake:dev
hadolint Dockerfile --ignore DL3008 --ignore DL3009
find rootfs -type f \( -name '*.sh' -o -name 'run' -o -name 'autostart' \) -print0 \
  | xargs -0 shellcheck -S warning -x -e SC1091
gitleaks dir . --redact --no-banner
```

`just check` runs the whole lint chain. There is no unit-test suite; correctness
is proven by lint plus the boot smoke gate.

## CI gates

- **lint.yml** — hadolint, shellcheck, xmllint, and a CR-character guard on
  `rootfs/`, the banner and the workflows.
- **build.yml** — one NATIVE build job per arch (amd64 on `ubuntu-latest`,
  arm64 on `ubuntu-24.04-arm`). Each job runs the **smoke gate**: WebUI answers,
  `GTK_THEME` equals `Adwaita:dark`, the `ghb` process starts and keeps the same
  PID for 20s, the watch daemon runs, the READY banner printed, and a generated
  test clip dropped into `/watch` really is transcoded into `/output` with no
  `.partial` left behind. Then a non-blocking Trivy scan, push by digest, and a
  `merge` job that assembles the multi-arch manifest for GHCR and the Docker Hub
  mirror.
- Runs on push to `main`, on `v*.*.*` tags, weekly (Sunday 04:00 UTC) and on
  dispatch.

## Release (NEVER tag without explicit approval)

1. Write `.github/release-notes/vX.Y.Z.md` (3-digit SemVer, emoji categories,
   only non-empty categories, no version heading inside the body).
2. Commit and push; wait for **Lint** and **Build & Push** to go green.
3. `git tag vX.Y.Z && git push origin vX.Y.Z`. The tag build publishes
   `:X.Y.Z / :X.Y / :X / :latest`; `release.yml` creates the GitHub release from
   the notes file. Release **title = the version only** (`vX.Y.Z`).
4. Keep the `unraid-apps` template entry in sync if anything user-facing changed.

The image stamps its build SHA/date to `/etc/handbrake-build`.

## Conventions / gotchas

- **Dark mode is `GTK_THEME=Adwaita:dark`, and that is load-bearing.** HandBrake
  1.11's GUI is GTK4 *without* libadwaita and calls
  `color_scheme_set_async(APP_PREFERS_LIGHT)` at startup, which resets
  `gtk-application-prefer-dark-theme` whenever no desktop portal answers — and
  there is no portal in this container. GTK4 reads `$GTK_THEME` before it looks
  at that setting, so the env var is the only deterministic mechanism. Side
  effect to keep documented: HandBrake's own in-app theme toggle has no visible
  effect; `HANDBRAKE_THEME` is the single source of truth.
- **`rootfs/defaults/autostart` is POSIX sh.** openbox runs it with dash and
  ignores the shebang; `[[ ]]` fails silently and skips the block.
- **The watch daemon must stay quiet when idle** so `HANDBRAKE IS READY` remains
  the last block in `docker logs`.
- **`SELKIES_ENABLE_BASIC_AUTH=false`** on purpose: the base enables basic auth
  with well-known default credentials otherwise. No login unless the user sets
  `CUSTOM_USER`/`PASSWORD`; `init-nologin` strips the empty values Unraid sends
  for blank template fields.
- **GPU support lives in `handbrake-gpu.sh` only.** It resolves `GPU_VENDOR` into
  the extra `HandBrakeCLI` arguments written to `/run/handbrake/gpu-args`. v1
  ships none. Never guess an encoder identifier — read it from
  `/usr/local/share/handbrake-cli-help.txt`.
- `rootfs/**` and every `*.sh` MUST stay **LF** (see `.gitattributes`); CRLF
  breaks the shebang scripts inside the image.
- **German** chat/vault, **English** repo. No AI attribution in commits or code.
  No real user data / IPs.
```

- [ ] **Step 3: Verify**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
just --list
just check
```
Expected: the recipe list prints, and `just check` ends with `All lint checks passed.`

- [ ] **Step 4: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add justfile CLAUDE.md
git commit -m "chore: add the justfile task runner and the repo guide"
```

---

### Task 15: README

**Files:**
- Create: `d:\nextcloud\it\github\handbrake\README.md`
- Test/Verify: every relative asset path resolves; the rendered page is checked in a clean browser.

**Interfaces:**
- Consumes: the banner pair and the screenshot (Tasks 2 and 10), `docs/handbrake-capabilities.md` (Task 9).
- Produces: the text mirrored to Docker Hub by `build.yml`.

- [ ] **Step 1: Write the README**

`d:\nextcloud\it\github\handbrake\README.md`:

````markdown
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/junkerderprovinz/handbrake/main/.github/assets/handbrake-banner-dark.png">
    <img src="https://raw.githubusercontent.com/junkerderprovinz/handbrake/main/.github/assets/handbrake-banner.png" alt="HandBrake for Unraid" width="100%">
  </picture>
</p>

<p align="center">
  <a href="https://github.com/junkerderprovinz/handbrake/actions/workflows/build.yml"><img src="https://img.shields.io/github/actions/workflow/status/junkerderprovinz/handbrake/build.yml?branch=main&label=Build&style=for-the-badge&logo=githubactions&logoColor=white" alt="Build" height="36"></a>&nbsp;
  <a href="https://github.com/junkerderprovinz/handbrake/actions/workflows/lint.yml"><img src="https://img.shields.io/github/actions/workflow/status/junkerderprovinz/handbrake/lint.yml?branch=main&label=Lint&style=for-the-badge&logo=githubactions&logoColor=white" alt="Lint" height="36"></a>&nbsp;
  <a href="https://hub.docker.com/r/junkerderprovinz/handbrake"><img src="https://img.shields.io/docker/pulls/junkerderprovinz/handbrake?style=for-the-badge&logo=docker&logoColor=white&label=Pulls&color=1d99f3" alt="Docker Pulls" height="36"></a>&nbsp;
  <a href="https://hub.docker.com/r/junkerderprovinz/handbrake"><img src="https://img.shields.io/docker/image-size/junkerderprovinz/handbrake/latest?style=for-the-badge&logo=docker&logoColor=white&label=Size&color=1d99f3" alt="Image Size" height="36"></a>&nbsp;
  <a href="https://github.com/junkerderprovinz/handbrake/pkgs/container/handbrake"><img src="https://img.shields.io/badge/Arch-amd64%20%7C%20arm64-success?style=for-the-badge&logo=linux&logoColor=white" alt="Arch" height="36"></a>&nbsp;
  <a href="https://github.com/selkies-project/selkies"><img src="https://img.shields.io/badge/Web-Selkies-3daee9?style=for-the-badge&logo=googlechrome&logoColor=white" alt="Selkies" height="36"></a>&nbsp;
  <a href="https://unraid.net"><img src="https://img.shields.io/badge/Unraid-Template-f15a2c?style=for-the-badge&logo=unraid&logoColor=white" alt="Unraid" height="36"></a>&nbsp;
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-AGPL--3.0-blue?style=for-the-badge&logo=gnu&logoColor=white" alt="License: AGPL-3.0" height="36"></a>
</p>

<br>

<p align="center">
A modern, plug-and-play Docker image for <b>HandBrake</b> on Unraid. The full
transcoder GUI in your browser via Selkies, <b>dark by default</b> using
HandBrake's own native GTK dark mode, plus a <b>watch-folder converter</b> that
transcodes anything you drop into <code>/watch</code> without opening the UI at
all. Everything is configurable from the Unraid template, no SSH or config-file
editing required.
</p>

<br>

<p align="center">
  <a href="https://buymeacoffee.com/junkerderprovinz">
    <img src=".github/assets/button-buy-me-a-coffee.svg" alt="Buy me a coffee" width="220">
  </a>
</p>

<br>

## Table of Contents

1. [Overview](#1-overview)
2. [Screenshots](#2-screenshots)
3. [Quick Start](#3-quick-start)
4. [Volumes and Ports](#4-volumes-and-ports)
5. [Configuration](#5-configuration)
6. [Automated Watch-Folder Conversion](#6-automated-watch-folder-conversion)
7. [Dark Mode](#7-dark-mode)
8. [Hardware Encoding](#8-hardware-encoding)
9. [Migrating from jlesage/handbrake](#9-migrating-from-jlesagehandbrake)
10. [Building Locally](#10-building-locally)
11. [Troubleshooting](#11-troubleshooting)
12. [License](#12-license)
13. [Support this project](#13-support-this-project)

<br>

## 1. Overview

This image packages [HandBrake](https://handbrake.fr) — the open-source video
transcoder — into a self-contained Docker container that runs in any modern web
browser. It is built on
[`linuxserver/baseimage-selkies`](https://github.com/linuxserver/docker-baseimage-selkies),
so it inherits LSIO's actively maintained Selkies desktop-streaming stack (a
hybrid VNC/H.264 pipeline) and weekly security updates, while everything
HandBrake-specific is layered on top here.

What you get beyond bare HandBrake:

- **Selkies instead of noVNC** — a hybrid VNC/H.264 pipeline for a smooth web
  desktop, real bidirectional browser clipboard, native file upload and
  download, high-DPI ready
- **Dark by default** — HandBrake's own native GTK dark mode, not a repaint;
  switch to light with one variable
- **Watch-folder automation** — drop a file into `/watch`, get a transcode in
  `/output`, no GUI interaction
- **Atomic output** — conversions are written to a hidden `.partial` file and
  renamed on success, so a media scanner never indexes a half-written video
- **Multi-arch** — amd64 and arm64, both gated by a CI smoke test that really
  transcodes a clip before anything is published

| | **This image** | jlesage/handbrake |
|---|:---:|:---:|
| Web stack | **Selkies (WebRTC/H.264)** | noVNC |
| Base | Ubuntu (glibc) | Alpine (musl) |
| Dark mode default | ✅ | opt-in via `DARK_MODE=1` |
| Watch-folder conversion | ✅ | ✅ |
| Browser clipboard | ✅ | ⚠️ |
| File upload via WebUI | ✅ | ❌ |
| Multi-arch | ✅ amd64 + arm64 | ✅ |
| Direct VNC client | ❌ (Selkies only, by design) | ✅ |

<br>

## 2. Screenshots

<p align="center">
  <img src=".github/assets/screenshots/handbrake-1.png" alt="HandBrake running in the browser in dark mode" width="100%">
</p>

<br>

## 3. Quick Start

Unraid: install from Community Applications and adjust the paths in the
template. Everything else has a working default.

Plain Docker:

```sh
docker run -d \
  --name=handbrake \
  -p 3000:3000 \
  -p 3001:3001 \
  -e PUID=99 \
  -e PGID=100 \
  -e TZ=Europe/Vienna \
  -v /mnt/user/appdata/handbrake:/config \
  -v /mnt/user/media:/storage:ro \
  -v /mnt/user/media/watch:/watch \
  -v /mnt/user/media/converted:/output \
  --restart unless-stopped \
  ghcr.io/junkerderprovinz/handbrake:latest
```

Then open `https://<host>:3001/`. Wait for `HANDBRAKE IS READY` in the container
log on the very first start.

<br>

## 4. Volumes and Ports

| Container path | Mode | Purpose |
|---|---|---|
| `/config` | rw | HandBrake presets, queue, logs and container state |
| `/storage` | ro | Media you want to browse from inside the GUI |
| `/watch` | rw | Watch folder — anything dropped here is converted automatically |
| `/watch2` … `/watch5` | rw | Additional watch folders (optional) |
| `/output` | rw | Where converted files are written |

| Port | Purpose |
|---|---|
| `3000` | WebUI over HTTP |
| `3001` | WebUI over HTTPS (self-signed by default) |

<br>

## 5. Configuration

| Variable | Default | Description |
|---|---|---|
| `PUID` / `PGID` | `911` | User and group the container runs as (Unraid: `99` / `100`) |
| `UMASK` | `022` | File-mode mask for everything the container creates |
| `TZ` | `Etc/UTC` | Container timezone |
| `LANG` | `en_US.UTF-8` | Locale, also drives HandBrake's UI language |
| `HANDBRAKE_THEME` | `dark` | `dark` or `light` — see [Dark Mode](#7-dark-mode) |
| `APP_NICENESS` | `0` | `nice` level (0-19) for the GUI and every transcode |
| `KEYBOARD_LAYOUT` | `us` | X keyboard layout loaded at session start |
| `GPU_VENDOR` | `none` | `none` today — see [Hardware Encoding](#8-hardware-encoding) |
| `CUSTOM_USER` / `PASSWORD` | empty | Set both to require a login on the WebUI; empty means no login |
| `CUSTOM_PORT` / `CUSTOM_HTTPS_PORT` | `3000` / `3001` | Internal WebUI ports |

<br>

## 6. Automated Watch-Folder Conversion

Every file dropped into `/watch` (and `/watch2`…`/watch5` when mounted) is
transcoded with the configured preset and written to `/output`. The variable
names match `jlesage/handbrake` so existing template values keep working.

| Variable | Default | Description |
|---|---|---|
| `AUTOMATED_CONVERSION` | `1` | Set to `0` to disable the daemon entirely |
| `AUTOMATED_CONVERSION_PRESET` | `General/Very Fast 1080p30` | HandBrake preset, `category/name` |
| `AUTOMATED_CONVERSION_FORMAT` | `mp4` | Output container: `mp4`, `mkv` or `webm` |
| `AUTOMATED_CONVERSION_KEEP_SOURCE` | `1` | `0` deletes the source after a successful conversion |
| `AUTOMATED_CONVERSION_VIDEO_FILE_EXTENSIONS` | (built-in list) | Space-separated extensions to pick up |
| `AUTOMATED_CONVERSION_WATCH_DIR` | `AUTO` | `AUTO` scans `/watch`…`/watchN`; any other value is used as the single watch folder |
| `AUTOMATED_CONVERSION_MAX_WATCH_FOLDERS` | `5` | How many `/watchN` folders `AUTO` looks for |
| `AUTOMATED_CONVERSION_OUTPUT_DIR` | `/output` | Destination folder |
| `AUTOMATED_CONVERSION_OUTPUT_SUBDIR` | empty | A fixed subfolder, or `SAME_AS_SRC` to mirror the source tree |
| `AUTOMATED_CONVERSION_OVERWRITE_OUTPUT` | `0` | `1` overwrites an existing output file |
| `AUTOMATED_CONVERSION_SOURCE_STABLE_TIME` | `5` | Seconds a file must stop changing before it is picked up |
| `AUTOMATED_CONVERSION_CHECK_INTERVAL` | `5` | Seconds between watch-folder scans |
| `AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS` | empty | Extra `HandBrakeCLI` arguments appended to every job |

How it behaves:

- A file is only converted once it has been **stable** for
  `AUTOMATED_CONVERSION_SOURCE_STABLE_TIME` seconds, so a file still being
  copied in is never touched.
- Output is written as `.<name>.<ext>.partial` and renamed only after
  `HandBrakeCLI` succeeds.
- Processed sources are remembered in
  `/config/handbrake/watch-state/done.list` by path, size and mtime — an
  unchanged source is never converted twice, an edited or re-copied one is.
- A failed job is recorded in `failed.list` and is not retried until the source
  changes. The full `HandBrakeCLI` output for every job is in
  `/config/handbrake-watch.log`.

<br>

## 7. Dark Mode

`HANDBRAKE_THEME=dark` (the default) applies HandBrake's own native GTK dark
mode — the stock Adwaita dark theme that ships inside GTK 4, exactly what
HandBrake uses on any Linux desktop set to dark. Nothing is repainted or
restyled. `HANDBRAKE_THEME=light` switches to the light variant.

One consequence worth knowing: the container sets `GTK_THEME`, which GTK reads
before it looks at any in-app preference. HandBrake's own light/dark toggle in
the UI therefore has no visible effect here — `HANDBRAKE_THEME` is the single
source of truth. Change it in the template and restart the container.

<br>

## 8. Hardware Encoding

**This release ships software encoding only.** `GPU_VENDOR` defaults to `none`;
setting it to `nvidia`, `intel` or `amd` logs a clear warning and still encodes
in software. NVENC, QSV and VCN support are being added in follow-up releases.

The encoders this build actually contains are recorded in
[`docs/handbrake-capabilities.md`](docs/handbrake-capabilities.md) and inside
the image:

```sh
docker exec handbrake cat /usr/local/share/handbrake-cli-help.txt
```

<br>

## 9. Migrating from jlesage/handbrake

- Ports change: `5800`/`5900` become `3000` (HTTP) and `3001` (HTTPS). There is
  no direct VNC port — Selkies is the only access path, by design.
- `USER_ID`/`GROUP_ID` become `PUID`/`PGID` (the LinuxServer convention).
- `DARK_MODE=1` becomes `HANDBRAKE_THEME=dark`, which is already the default.
- All `AUTOMATED_CONVERSION*` variables listed above keep their names and
  defaults, so you can copy those values over unchanged.
- `/config`, `/storage`, `/watch` and `/output` keep their meaning, but the
  `/config` contents are not compatible: start with a fresh appdata folder and
  re-import your custom presets from the GUI.

<br>

## 10. Building Locally

```sh
git clone https://github.com/junkerderprovinz/handbrake.git
cd handbrake
docker build -t handbrake:dev .
docker run -d --name hb -p 3000:3000 -p 3001:3001 handbrake:dev
```

`just check` runs the same lint chain as CI. `just smoke` builds and boots the
image; `just convert-test` drops a generated clip into its watch folder.

<br>

## 11. Troubleshooting

**The WebUI is black on the first start.** The desktop is up before HandBrake
has drawn its window. Wait for `HANDBRAKE IS READY` in `docker logs handbrake`.

**Nothing in `/watch` gets converted.** Check `docker logs handbrake` for
`[handbrake-watch]` lines. The most common cause is a watch or output folder the
container user cannot write — the init log says so explicitly:
`WARNING: watch folder /watch is NOT writable by the container user`. Fix the
share owner on the host (`chown nobody:users /mnt/user/<share>`).

**A conversion failed.** The full `HandBrakeCLI` output is in
`/config/handbrake-watch.log`. The source is recorded in
`/config/handbrake/watch-state/failed.list` and is not retried until the file
changes; delete the line to retry it.

**The UI is light although `HANDBRAKE_THEME=dark`.** Confirm the variable
reached the process:

```sh
docker exec handbrake sh -c 'cat /proc/$(pgrep -x ghb)/environ | tr "\0" "\n" | grep GTK_THEME'
```
It must print `GTK_THEME=Adwaita:dark`.

**Which image am I actually running?**

```sh
docker exec handbrake cat /etc/handbrake-build
```

<br>

## 12. License

This wrapper is AGPL-3.0-only (see [`LICENSE`](LICENSE)). HandBrake itself is
GPL-2.0 and its artwork is CC BY-SA 4.0 — every bundled component and its
licence is listed in [`NOTICE`](NOTICE).

<br>

## 13. Support this project

<p align="center">
  <a href="https://buymeacoffee.com/junkerderprovinz">
    <img src=".github/assets/button-buy-me-a-coffee.svg" alt="Buy me a coffee" width="220">
  </a>
</p>
````

- [ ] **Step 2: Verify every referenced asset exists**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
for f in .github/assets/handbrake-banner.png .github/assets/handbrake-banner-dark.png \
         .github/assets/button-buy-me-a-coffee.svg .github/assets/screenshots/handbrake-1.png \
         LICENSE NOTICE docs/handbrake-capabilities.md; do
  [ -f "$f" ] && echo "OK   $f" || echo "MISS $f"
done
```
Expected: every line starts with `OK`.

- [ ] **Step 3: Commit**

```bash
cd /d/nextcloud/it/github/handbrake
git add README.md
git commit -m "docs: add the README"
```

---

### Task 16: Publish the repo, prove CI, and cut v1.0.0

**Files:**
- Create: `d:\nextcloud\it\github\handbrake\.github\release-notes\v1.0.0.md`
- Test/Verify: both workflows green on `main`, the GHCR package pullable, and the release created from the notes file.

**Interfaces:**
- Consumes: everything above.
- Produces: `ghcr.io/junkerderprovinz/handbrake:1.0.0` / `:1.0` / `:1` / `:latest`, the GitHub release `v1.0.0`, and the baseline that Plans 2-4 branch from.

- [ ] **Step 1: Create the GitHub repository and push**

```bash
cd /d/nextcloud/it/github/handbrake
git remote -v
gh repo create junkerderprovinz/handbrake --public \
  --description "HandBrake for Unraid — the full video transcoder in your browser via Selkies, dark by default, with an automated watch-folder converter" \
  --source . --remote origin --push
```
Expected: the repository is created and `main` is pushed. If `origin` already exists, use `git push -u origin main` instead.

- [ ] **Step 2: Add repository metadata**

```bash
cd /d/nextcloud/it/github/handbrake
gh repo edit junkerderprovinz/handbrake \
  --homepage "https://github.com/junkerderprovinz/handbrake" \
  --add-topic unraid --add-topic docker --add-topic handbrake --add-topic selkies \
  --add-topic transcoding --add-topic video --add-topic ffmpeg --add-topic webui
```

- [ ] **Step 3: Wait for CI and read the smoke-gate output**

```bash
cd /d/nextcloud/it/github/handbrake
gh run list --limit 5
gh run watch "$(gh run list --workflow=build.yml --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
gh run watch "$(gh run list --workflow=lint.yml  --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
```
Expected: both runs conclude `success`. In the build log, both the `amd64` and `arm64` jobs must show:
```
GTK_THEME=Adwaita:dark
ghb stayed up with an unchanged pid
converted file is <n> bytes
✅ smoke gate passed on <arch>
```
If a job fails, fix the cause in the owning task's file, push, and re-run this step. Never disable a gate to get green.

- [ ] **Step 4: Make the GHCR package public and verify a real pull**

Repo visibility and package visibility are separate. Set the package to public in the GHCR UI (`https://github.com/users/junkerderprovinz/packages/container/handbrake/settings`), then prove it from a logged-out client:

```bash
docker logout ghcr.io
docker pull ghcr.io/junkerderprovinz/handbrake:latest
docker run --rm --entrypoint sh ghcr.io/junkerderprovinz/handbrake:latest -c 'HandBrakeCLI --version | head -n1'
```
Expected: the pull succeeds without credentials and the version line prints.

- [ ] **Step 5: Enable the Docker Hub mirror**

Create the `junkerderprovinz/handbrake` repository on Docker Hub, then:

```bash
cd /d/nextcloud/it/github/handbrake
gh variable set DOCKERHUB_USERNAME --body "junkerderprovinz"
gh secret set DOCKERHUB_TOKEN         # paste the push token
gh secret set DOCKERHUB_PASSWORD      # paste the description-edit credential
gh workflow run build.yml
```
Expected: the next build pushes to both registries and the `Sync README to Docker Hub` step runs instead of being skipped.

- [ ] **Step 6: Write the release notes**

`d:\nextcloud\it\github\handbrake\.github\release-notes\v1.0.0.md`:

```markdown
First release. HandBrake's full transcoder GUI in your browser on Unraid, dark from the first start, with a watch folder that converts anything you drop into it.

## ✨ Added

- **HandBrake in the browser.** The complete HandBrake GTK interface on a Selkies web desktop — a hybrid VNC/H.264 pipeline with a real bidirectional clipboard and native file upload, not a noVNC frame. Reachable on port 3000 (HTTP) and 3001 (HTTPS), with no login unless you set `CUSTOM_USER` and `PASSWORD`.
- **Automated watch-folder conversion.** Drop a video into `/watch` and it is transcoded into `/output` with the preset from `AUTOMATED_CONVERSION_PRESET`, without touching the GUI. Up to five watch folders (`/watch` … `/watch5`), configurable output container, extension filter, keep-or-delete source, optional mirrored subdirectories, and a niceness setting so a transcode does not starve the rest of the box. The variable names match `jlesage/handbrake`, so an existing template can be copied over.
- **Atomic output.** Every conversion is written to a hidden `.partial` file and renamed only after HandBrake reports success, so a media scanner never picks up a half-written video. Stopping the container mid-conversion removes the partial file instead of leaving it behind.
- **Conversion bookkeeping.** Processed sources are remembered by path, size and modification time, so an unchanged file is never converted twice while an edited or re-copied one is picked up again. Failures are recorded separately and not retried until the source changes; the full HandBrake output per job lands in `/config/handbrake-watch.log`.
- **Multi-arch images** for amd64 and arm64 on GHCR and Docker Hub, each one gated by a CI smoke test that boots the container, waits for the WebUI, checks that the GUI process stays alive, and really transcodes a generated clip before anything is published.
- **Build provenance** in the image: `docker exec handbrake cat /etc/handbrake-build` reports the exact commit and build date, and `/usr/local/share/handbrake-cli-help.txt` records which encoders this build contains.

## 🎨 Design

- **Dark by default, using HandBrake's own dark mode.** The container ships the native GTK dark theme HandBrake uses on any dark Linux desktop — nothing is repainted or restyled. `HANDBRAKE_THEME=light` switches to the light variant.
- **Clean startup log.** The container prints one ASCII banner and a `HANDBRAKE IS READY` line once the WebUI is serving and the GUI is actually up, and stays quiet after that, so the log ends on the line that matters.
```

- [ ] **Step 7: Sanity-check the notes against the house rules**

Run:
```bash
cd /d/nextcloud/it/github/handbrake
grep -nE '^#[^#]' .github/release-notes/v1.0.0.md && echo "H1 FOUND — remove it" || echo "no H1 heading (correct)"
grep -nE '^## ' .github/release-notes/v1.0.0.md
grep -c 'handbrake' .github/release-notes/v1.0.0.md >/dev/null
```
Expected: `no H1 heading (correct)` and only the two category headings `## ✨ Added` and `## 🎨 Design` (empty categories are omitted on purpose).

- [ ] **Step 8: Commit and push the notes**

```bash
cd /d/nextcloud/it/github/handbrake
git add .github/release-notes/v1.0.0.md
git commit -m "docs: add the v1.0.0 release notes"
git push origin main
```

- [ ] **Step 9: STOP — ask for approval before tagging**

Do not run Step 10 until jdp has explicitly approved cutting `v1.0.0`. Report that everything is green and pushed, and ask.

- [ ] **Step 10: Tag the release (only after approval)**

```bash
cd /d/nextcloud/it/github/handbrake
git fetch origin && git pull --rebase origin main
git tag v1.0.0
git push origin v1.0.0
gh run watch "$(gh run list --workflow=release.yml --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
gh release view v1.0.0
```
Expected: the release title is exactly `v1.0.0`, the body is the notes file, and the build run publishes `:1.0.0`, `:1.0`, `:1` and `:latest`.

- [ ] **Step 11: Verify the published tags**

```bash
docker buildx imagetools inspect ghcr.io/junkerderprovinz/handbrake:1.0.0
```
Expected: a manifest list with `linux/amd64` and `linux/arm64`.

- [ ] **Step 12: Follow-ups outside this repo**

These are house requirements and are not optional:

1. Add the HandBrake entry to the `unraid-apps` feed repo (template XML, icon, category), following the existing `krusader` entry.
2. Update the `junkerderprovinz/junkerderprovinz` profile README with the new repo.
3. Mirror the change into the Obsidian vault: a PascalCase repo note under `02 Projekte`, plus a dated changelog entry.

---

## Self-review checklist

Run this before declaring the plan finished — it is the same list the plan author already walked.

- [ ] No `TBD`, `TODO`, `similar to Task N`, or "add error handling here" anywhere in this document.
- [ ] Script names are identical everywhere they appear: `handbrake-theme.sh`, `handbrake-gpu.sh`, `handbrake-watch.sh`, `print-banner.sh`.
- [ ] Service names are identical everywhere: `init-nologin`, `init-handbrake`, `svc-handbrake-watch`, `svc-handbrake-ready`.
- [ ] The Dockerfile's `chmod +x` list covers exactly the files Tasks 2, 5, 6, 7 and 8 create — no more, no fewer.
- [ ] `Adwaita:dark` is the literal value in `handbrake-theme.sh`, in the CI assertion and in the README.
- [ ] The READY string `HANDBRAKE IS READY` is identical in `svc-handbrake-ready/run`, in the CI grep and in the README.
- [ ] Every spec item in this plan's scope has a task: base image (3), Selkies wiring (3, 4, 5), `ghb` + `HandBrakeCLI` install (3), watch-folder daemon (7), native GTK dark default (5), CI lint (11), boot-smoke gate (12), build/push (12), first release (16).
- [ ] Every spec "confirm at implementation time" item is an executed command with recorded output: packaging channel (3, comment plus the build-time assertion), encoder identifiers (9 Step 3), preset validity (3 and 9 Step 4), container format spelling (9 Step 5), GTK toolkit and dark mechanism (9 Step 6), first-run dialogs (10 Step 6 — HandBrake has no forced first-run dialog; if one appears, it is observed there before release), logo/trademark policy (2 Step 1).
- [ ] Out of scope and deliberately absent: any NVENC/QSV/VCN code, web file manager, web terminal, web notifications, web audio, host clipboard sync, web authentication beyond the base's basic auth, CJK fonts, conversion hooks, configurable staging directory, optical-drive passthrough.

---

## Handoff: what Plans 2, 3 and 4 must reference

**GPU seam (Plans 2 and 3).**
- `rootfs/usr/local/bin/handbrake-gpu.sh <vendor>` — the only file to change. It prints extra `HandBrakeCLI` arguments on stdout and a decision line on stderr, and writes the normalised vendor to `/run/handbrake/gpu-vendor`. Extend `gpu_args_for_vendor()`.
- Env var: `GPU_VENDOR` (unprefixed, values `none|nvidia|intel|amd`, default `none`, declared in the Dockerfile).
- Runtime handoff files: `/run/handbrake/gpu-args` (written by `init-handbrake`, read by `handbrake-watch.sh`) and `/run/handbrake/gpu-vendor`.
- The daemon splices the args as `HB_GPU_ARGS` before the user's `AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS`, so a user can always override the vendor choice.
- Never hardcode an encoder identifier: read it from `/usr/local/share/handbrake-cli-help.txt` inside the image, recorded in `docs/handbrake-capabilities.md`.
- Ubuntu's `handbrake`/`handbrake-cli` packaging builds with `--enable-nvenc` (amd64 and arm64) and `--enable-qsv` (amd64) but does **not** pass `--enable-vce`. Plan 2 should therefore only need runtime libraries plus argument selection, while Plan 3's AMD half likely needs a source build or a different channel. Confirm against `docs/handbrake-capabilities.md` before designing either.

**Theme seeding (any plan touching the UI).**
- `rootfs/usr/local/bin/handbrake-theme.sh <dark|light>`, called once by `init-handbrake`.
- Writes `/run/s6/container_environment/GTK_THEME` (`Adwaita:dark` or `Adwaita`), `/run/s6/container_environment/HANDBRAKE_THEME`, `/config/.profile.d/handbrake-theme.sh` (sourced by `rootfs/defaults/autostart`), and `/config/.config/gtk-{3.0,4.0}/settings.ini`.
- `GTK_THEME` is the mechanism because HandBrake is GTK4 without libadwaita and resets `gtk-application-prefer-dark-theme` at startup. Do not replace it with a settings-file-only approach.

**Watch daemon (Plan 4).**
- `rootfs/usr/local/bin/handbrake-watch.sh`, launched by `rootfs/etc/s6-overlay/s6-rc.d/svc-handbrake-watch/run` as `exec s6-setuidgid abc env HOME=/config ... /usr/local/bin/handbrake-watch.sh`.
- Single `HandBrakeCLI` call site: `hb_run()` — wrap pre/post hooks there.
- Single staging-path helper: `partial_path()` — replace it for a configurable staging directory.
- State: `/config/handbrake/watch-state/done.list` and `failed.list`, keys `sha1(path)|size|mtime`. Job log: `/config/handbrake-watch.log`.
- Already implemented env vars (do not redefine): `AUTOMATED_CONVERSION`, `_PRESET`, `_FORMAT`, `_KEEP_SOURCE`, `_VIDEO_FILE_EXTENSIONS`, `_WATCH_DIR`, `_MAX_WATCH_FOLDERS`, `_OUTPUT_DIR`, `_OUTPUT_SUBDIR`, `_OVERWRITE_OUTPUT`, `_SOURCE_STABLE_TIME`, `_CHECK_INTERVAL`, `_HANDBRAKE_CUSTOM_ARGS`.
- Still free for Plan 4: `_NON_VIDEO_FILE_ACTION`, `_NON_VIDEO_FILE_EXTENSIONS`, `_SOURCE_MIN_DURATION`, `_SOURCE_MAIN_TITLE_DETECTION`, `_NO_GUI_PROGRESS`, `_USE_TRASH`, `_TRASH_DIR`, plus `/config/hooks/`.

**Init structure (all plans).**
- No `/etc/cont-init.d/` is used and none should be added; the numbering scheme is deliberately absent. All init is s6-rc v3 with `init-<topic>` oneshots and `svc-<topic>` longruns.
- A new oneshot needs: `<name>/type`, `<name>/run`, `<name>/up`, `<name>/dependencies.d/init-handbrake`, `user/contents.d/<name>`, and `init-config-end/dependencies.d/<name>`.
- Existing ordering edges: `init-nologin` → `init-nginx`; `init-selkies-config` → `init-handbrake` → `init-config-end`; `init-handbrake` → `svc-handbrake-watch` and `svc-handbrake-ready`.

**CI hooks (all plans).**
- `.github/workflows/build.yml`, step `Smoke test — ${{ matrix.arch }} must boot, stay up and transcode`. Add assertions there. The gate already checks: WebUI up, `GTK_THEME=Adwaita:dark`, `ghb` PID stable for 20s, watch daemon alive, `HANDBRAKE IS READY` in the log, real transcode into `/output`, no leftover `.partial`.
- A GPU plan cannot test hardware encoding in CI (no GPU runner). Assert the *presence* of the vendor libraries and the *selection logic* instead, and verify real hardware encoding on the box.

**Other fixed strings other plans must not change silently.**
- Image name `handbrake`; GHCR `ghcr.io/junkerderprovinz/handbrake`.
- Log prefixes: `[init-handbrake]`, `[handbrake-theme]`, `[handbrake-gpu]`, `[handbrake-watch]`, `[handbrake-autostart]`.
- In-image capability dumps: `/usr/local/share/handbrake-{version,cli-help,preset-list}.txt`.
- Build stamp: `/etc/handbrake-build`.

