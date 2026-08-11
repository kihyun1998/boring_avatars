// Generates scenes.json for tool/calibrate/render.mjs: one row of 8x8 swatches.
//
//   node tool/colour4/gen.mjs <work-dir>
//   CHROME=... node tool/calibrate/render.mjs <work-dir>
//   node tool/colour4/read.mjs <work-dir>
//
// The strip is the pixel half of #95's two-source measurement (the other half
// is sys.mjs, which resolves the system colours through getComputedStyle).
// The first two swatches are controls: a known colour and a known refusal, so
// a misaligned read shows immediately. NOTE the probe SVG deliberately has no
// root fill="none", so a refused fill inherits *black* — the refusal baseline
// is the `zzz` control's value, not transparency (ADR-0001 R2(b) live).
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const outDir = process.argv[2];
if (!outDir) {
  console.error('usage: node tool/colour4/gen.mjs <work-dir>');
  process.exit(2);
}
mkdirSync(outDir, { recursive: true });

const values = [
  // controls — a known colour and a known nothing, so misalignment shows
  '#FF0000',
  'zzz',
  // hwb
  'hwb(120 0% 0%)',
  'hwb(120 30% 20%)',
  'hwb(0.25turn 10% 10%)',
  'hwb(120 60% 60%)', // w+b>=100 -> achromatic 60/120
  'hwb(120 30% 20% / 0.5)',
  'hwb(120, 30%, 20%)', // no legacy comma form in the spec — expect refusal
  'hwb(-240 30% 20%)', // hue wrap
  // lab
  'lab(50% 40 59.5)',
  'lab(50 40 59.5)', // L as number == L as percent
  'lab(29.2345% 39.3825 20.0664)',
  'lab(100 0 0)',
  'lab(0 0 0)',
  'lab(50% 50% -50%)', // a/b percentages -> ±125
  'lab(50% 100 0)', // far out of sRGB gamut — clip vs map discriminator
  'lab(50% 40 59.5 / 30%)',
  // lch
  'lch(52.2% 72.2 50)',
  'lch(29.2345% 44.2 27)',
  'lch(52.2% 72.2 50deg)',
  'lch(52.2% 72.2 0.139turn)',
  'lch(50% 150 0)', // out of gamut
  'lch(50% 50% 50)', // C percent -> 150
  // oklab
  'oklab(0.7 0.1 0.1)',
  'oklab(70% 0.1 0.1)',
  'oklab(1 0 0)',
  'oklab(70% 25% -25%)', // a/b percent -> ±0.4
  // oklch
  'oklch(0.7 0.15 200)',
  'oklch(70% 0.15 200)',
  'oklch(0.7 0.35 30)', // out of gamut
  'oklch(0.7 37.5% 30)', // C percent -> 0.4
  'oklch(0.628 0.2577 29.23)', // ~sRGB red
  // color()
  'color(srgb 1 0 0)',
  'color(srgb 0.5 0.25 0.75)',
  'color(srgb 2 0 0)', // above range
  'color(srgb -0.5 0.5 0.5)', // below range
  'color(srgb 50% 25% 75%)', // percentages
  'color(srgb-linear 0.5 0.5 0.5)',
  'color(display-p3 1 0 0)', // out of sRGB — the sharpest clip-vs-map case
  'color(display-p3 0 1 0)',
  'color(a98-rgb 1 0 0)',
  'color(prophoto-rgb 1 0 0)',
  'color(rec2020 1 0 0)',
  'color(xyz 0.2 0.3 0.4)',
  'color(xyz-d50 0.2 0.3 0.4)',
  'color(xyz-d65 0.2 0.3 0.4)',
  'color(srgb 1 0 0 / 0.5)',
  // system colours — Color 4 §6.2, values are UA discretion: measurement is spec
  'canvas',
  'canvastext',
  'linktext',
  'visitedtext',
  'activetext',
  'buttonface',
  'buttontext',
  'buttonborder',
  'field',
  'fieldtext',
  'highlight',
  'highlighttext',
  'selecteditem',
  'selecteditemtext',
  'mark',
  'marktext',
  'graytext',
  'accentcolor',
  'accentcolortext',
  // deprecated system colours — does Chrome still accept them?
  'activeborder',
  'windowtext',
  'threedface',
  // none components — scope note for the ticket
  'lab(none 0 0)',
  'hsl(none 100% 50%)',
  'rgb(none 0 0)',
  'oklch(none none none)',
  // the #95 completeness pass's discriminators, confirmed on the reference
  // Chrome before the fixes were frozen
  'lab(50 1e300 0)', // huge components clamp, not crash
  'lab(50 1e300 -1e300)',
  'color(srgb 1e308 0 0)',
  'hwb(120 30% 20% 10%)', // a bare 4th component is not an alpha
  'lab(50 40 59.5 30)',
  'color(srgb 1 0 0 0)',
  'rgb(255 0 0 0.5)',
  'rgb(100% 0 0)', // modern form: per-component number|percentage
  'rgb(255 0% 0)',
  'hsl(120 50 50)',
  'hsl(120, 50, 50)', // legacy comma form keeps its stricter grammar
  'rgb(255. 0 0)', // a CSS number token needs a digit after the dot
  'lab(50. 40 59.5)',
];

const W = 8;
const size = values.length * W;
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
let rects = '';
values.forEach((v, i) => {
  rects += `<rect x="${i * W}" y="0" width="${W}" height="8" fill="${esc(v)}"></rect>`;
});
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="8" viewBox="0 0 ${size} 8">${rects}</svg>`;
writeFileSync(join(outDir, 'scenes.json'), JSON.stringify({ c4: { svg, size } }));
// render.mjs sizes the window square (size x size); the strip is 8 tall at y<8.
writeFileSync(join(outDir, 'values.json'), JSON.stringify(values));
console.log(`${values.length} swatches, width ${size}`);
