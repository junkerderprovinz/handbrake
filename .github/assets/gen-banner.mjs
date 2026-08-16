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
// read from the source so the artwork itself is never touched. The source is
// Inkscape-exported and uses several prefixed attributes inside the body
// (inkscape:, sodipodi:, rdf:, cc:, dc: - editor metadata plus a
// sodipodi:namedview block), so the wrapper tag must carry over every
// xmlns:* declaration the original root had, not just the default SVG
// namespace, or resvg rejects the re-serialised tag as an unknown prefix.
const logoSrc = readFileSync(join(__dir, "handbrake-logo.svg"), "utf8")
  .replace(/<\?xml[^>]*\?>\s*/, "");
const origSvgTagMatch = logoSrc.match(/<svg[\s\S]*?>/);
const origSvgTag = origSvgTagMatch ? origSvgTagMatch[0] : "<svg>";
const xmlnsDecls = [...origSvgTag.matchAll(/\sxmlns(:[\w-]+)?="[^"]*"/g)].map((m) => m[0]);
if (!xmlnsDecls.some((d) => /^\s*xmlns="/.test(d))) {
  xmlnsDecls.unshift(' xmlns="http://www.w3.org/2000/svg"');
}
// The source has no viewBox at all (only width/height="1024"), which is valid
// SVG (per spec the coordinate system then matches width/height 1:1) but must
// be reconstructed explicitly here, since the wrapper below replaces the
// original width/height with the render size and needs an actual viewBox to
// map the artwork's own 1024x1024 space into it. A generic small fallback
// here would silently clip the artwork to a corner instead of scaling it.
const vbMatch = logoSrc.match(/viewBox="([^"]+)"/);
const srcWidthMatch = origSvgTag.match(/[^-]width="(\d+(?:\.\d+)?)"/);
const srcHeightMatch = origSvgTag.match(/[^-]height="(\d+(?:\.\d+)?)"/);
const viewBox = vbMatch
  ? vbMatch[1]
  : srcWidthMatch && srcHeightMatch
    ? `0 0 ${srcWidthMatch[1]} ${srcHeightMatch[1]}`
    : "0 0 128 128";
const logo = logoSrc.replace(
  /<svg[\s\S]*?>/,
  `<svg x="${LX.toFixed(1)}" y="${LY.toFixed(1)}" width="${LW}" height="${LH}" viewBox="${viewBox}"${xmlnsDecls.join("")}>`,
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
