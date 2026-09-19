/**
 * Generates the text-free support-thread banner, handbrake-banner-logo.svg/.png:
 * 1600x500 on white with only the official HandBrake logo. SUPPORT_THREAD.html
 * uses it in place of the full handbrake-banner.svg.
 *
 * Embeds the same official logo verbatim (CC BY-SA 4.0, see NOTICE) as
 * gen-banner.mjs, centred on the canvas instead of beside the text.
 *
 * Deps: `npm i -g @resvg/resvg-js`.
 * Run:  node .github/assets/gen-banner-logo.mjs
 */
import { readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { execSync } from "node:child_process";

const require = createRequire(import.meta.url);
const gRoot = execSync("npm root -g").toString().trim();
const { Resvg } = require(`${gRoot}/@resvg/resvg-js`);

const __dir = dirname(fileURLToPath(import.meta.url));

const W = 1600, H = 500;
const LH = 380; // logo height, centred (house banner logo standard)
const LW = LH; // square logo

// Same wrapper as in gen-banner.mjs: it keeps every xmlns:* declaration of the
// Inkscape export, or resvg rejects the prefixed attributes.
const logoSrc = readFileSync(join(__dir, "handbrake-logo.svg"), "utf8")
  .replace(/<\?xml[^>]*\?>\s*/, "");
const origSvgTagMatch = logoSrc.match(/<svg[\s\S]*?>/);
const origSvgTag = origSvgTagMatch ? origSvgTagMatch[0] : "<svg>";
const xmlnsDecls = [...origSvgTag.matchAll(/\sxmlns(:[\w-]+)?="[^"]*"/g)].map((m) => m[0]);
if (!xmlnsDecls.some((d) => /^\s*xmlns="/.test(d))) {
  xmlnsDecls.unshift(' xmlns="http://www.w3.org/2000/svg"');
}
// The source has width/height="1024" and no viewBox, and the wrapper needs one
// to scale the artwork to the render size.
const vbMatch = logoSrc.match(/viewBox="([^"]+)"/);
const srcWidthMatch = origSvgTag.match(/[^-]width="(\d+(?:\.\d+)?)"/);
const srcHeightMatch = origSvgTag.match(/[^-]height="(\d+(?:\.\d+)?)"/);
const viewBox = vbMatch
  ? vbMatch[1]
  : srcWidthMatch && srcHeightMatch
    ? `0 0 ${srcWidthMatch[1]} ${srcHeightMatch[1]}`
    : "0 0 128 128";
const LX = (W - LW) / 2, LY = (H - LH) / 2;
const logo = logoSrc.replace(
  /<svg[\s\S]*?>/,
  `<svg x="${LX.toFixed(1)}" y="${LY.toFixed(1)}" width="${LW}" height="${LH}" viewBox="${viewBox}"${xmlnsDecls.join("")}>`,
);

const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" role="img" aria-label="HandBrake">
  <rect width="${W}" height="${H}" fill="#ffffff"/>
  ${logo}
</svg>
`;
writeFileSync(join(__dir, "handbrake-banner-logo.svg"), svg);
const png = new Resvg(svg, { fitTo: { mode: "width", value: W }, background: "#ffffff" }).render().asPng();
writeFileSync(join(__dir, "handbrake-banner-logo.png"), png);
console.log("wrote handbrake-banner-logo.svg + .png");
