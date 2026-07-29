// Renders upstream's own React output and ours in the SAME browser, and
// compares the pixels.
//
//   dart run tool/crosscheck/emit.dart <work-dir>
//   node tool/crosscheck/crosscheck.mjs <work-dir>
//
// ## Why this is the strong comparison, and what it is not
//
// `tool/parity` compares the two SVG **strings**, and it normalises `id="…"`,
// `url(#…)` and `mask="…"` away on both sides — right for the ids `useId`
// generates from 1.8.0, and a hole at 1.6.1 where every id is a literal. A port
// that named its gradients anything at all passes all 600 renders.
//
// `tool/calibrate` compares pixels, but it feeds Chrome **our** document, so
// anything inside that same hole is invisible there too. That is not an
// oversight: a harness that rebuilt the SVG independently could pass while the
// two backends disagreed about what to draw. The consequence is that no
// existing check renders what *upstream* actually emits.
//
// This one does. Both documents go through one browser, so the browser's own
// approximation error — circles up to 0.13 px inside true geometry, shallow
// rotated edges up to 30/255 out (hidden-state #27) — applies identically to
// each and **cancels**. The bar is therefore **0 differing pixels**, with no
// tolerance to negotiate and nothing to relax when Chrome updates. It is the
// one bar in this project that a browser change cannot break.
//
// What it cannot see: anything both documents get wrong the same way. It says
// "upstream and this port draw the same picture", never "the picture is right".
//
// A TOOL, not a gate. `flutter test` never runs it — it needs npm, a browser
// and a network install.
import { inflateSync } from 'node:zlib';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { chromium } from 'playwright-core';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '..', '..');

const workDir = process.argv[2];
if (!workDir) {
  console.error('usage: node tool/crosscheck/crosscheck.mjs <work-dir>');
  process.exit(2);
}
mkdirSync(workDir, { recursive: true });

/** The size both sides render at — must match `emit.dart`'s `renderSize`. */
const SIZE = 320;

/**
 * Names where this port **deliberately** differs from upstream, per variant.
 *
 * `sunset` builds its gradient id from the caller's name and references it as
 * `url(#…)`. For a name containing `'`, `"`, `(`, `)`, `\` or `%` the reference
 * is not a valid CSS url token, so upstream's own avatar renders **blank** —
 * reproduced in Chrome, every pixel `0,0,0,0`. The user ruled on 2026-07-29 to
 * repair it (divergence ledger, S-1), so a difference here is the ruling
 * working, not a regression.
 *
 * Listed by name rather than detected, exactly as `sunset_parity_test.dart`
 * does: the set can only grow by someone editing this line, so a repair that
 * started firing on a name nobody intended shows up as a failure.
 */
const EXPECTED_DIVERGENCE = { sunset: new Set(['punctuation']) };

// --- upstream, rendered fresh -----------------------------------------------
//
// Not read from `test/fixtures/`: those entries are stored normalised, and
// `mask="_"` has lost its `url()` wrapper, so a fixture entry handed to a
// browser would render unmasked. The whole point here is the unnormalised
// document.

const upstreamModule = await import('upstream-1.6.1');
const Avatar = upstreamModule.default?.default ?? upstreamModule.default;

const corpus = JSON.parse(
  readFileSync(join(REPO, 'test/fixtures/corpus.json'), 'utf8'),
);
const emitted = JSON.parse(readFileSync(join(workDir, 'ours.json'), 'utf8'));
const ours = emitted.renders;
const uncovered = emitted.upstreamVariants.filter(
  (v) => !emitted.portedVariants.includes(v),
);
if (emitted.size !== SIZE) {
  throw new Error(
    `emit.dart rendered at ${emitted.size} and this compares at ${SIZE}; the ` +
      `two must agree or the screenshots are of different drawings`,
  );
}

/** Decodes a non-interlaced 8-bit PNG to straight RGBA bytes. */
function decodePng(buffer) {
  if (buffer.readUInt32BE(0) !== 0x89504e47) throw new Error('not a PNG');
  let offset = 8;
  let width = 0;
  let height = 0;
  let bitDepth = 0;
  let colourType = 0;
  const idat = [];

  while (offset < buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString('ascii', offset + 4, offset + 8);
    const data = buffer.subarray(offset + 8, offset + 8 + length);
    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8];
      colourType = data[9];
      if (data[12] !== 0) throw new Error('interlaced PNG is not supported');
    } else if (type === 'IDAT') {
      idat.push(data);
    } else if (type === 'IEND') {
      break;
    }
    offset += length + 12;
  }
  if (bitDepth !== 8 || (colourType !== 6 && colourType !== 2)) {
    throw new Error(`unsupported PNG: depth ${bitDepth} colour ${colourType}`);
  }

  const channels = colourType === 6 ? 4 : 3;
  const raw = inflateSync(Buffer.concat(idat));
  const stride = width * channels;
  const out = Buffer.alloc(width * height * 4);
  let previous = Buffer.alloc(stride);

  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const line = Buffer.from(
      raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1)),
    );
    for (let i = 0; i < stride; i++) {
      const a = i >= channels ? line[i - channels] : 0;
      const b = previous[i];
      const c = i >= channels ? previous[i - channels] : 0;
      switch (filter) {
        case 0:
          break;
        case 1:
          line[i] = (line[i] + a) & 0xff;
          break;
        case 2:
          line[i] = (line[i] + b) & 0xff;
          break;
        case 3:
          line[i] = (line[i] + ((a + b) >> 1)) & 0xff;
          break;
        case 4: {
          const p = a + b - c;
          const pa = Math.abs(p - a);
          const pb = Math.abs(p - b);
          const pc = Math.abs(p - c);
          const pred = pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
          line[i] = (line[i] + pred) & 0xff;
          break;
        }
        default:
          throw new Error(`unknown PNG filter ${filter}`);
      }
    }
    for (let x = 0; x < width; x++) {
      out[(y * width + x) * 4 + 0] = line[x * channels + 0];
      out[(y * width + x) * 4 + 1] = line[x * channels + 1];
      out[(y * width + x) * 4 + 2] = line[x * channels + 2];
      out[(y * width + x) * 4 + 3] =
        channels === 4 ? line[x * channels + 3] : 255;
    }
    previous = line;
  }
  return { width, height, bytes: out };
}

/** An HTML wrapper with no UA margins and no scrollbar — the page IS the SVG. */
const wrap = (svg) =>
  `<!doctype html><meta charset="utf-8"><style>
html,body{margin:0;padding:0;background:transparent;overflow:hidden}
svg{display:block}
</style>${svg}`;

/** How many pixels differ, and by how much, comparing **premultiplied**. */
function compare(a, b) {
  if (a.width !== b.width || a.height !== b.height) {
    return { differing: -1, worst: 255, at: 'size', opaqueA: 0, opaqueB: 0 };
  }
  let differing = 0;
  let worst = 0;
  let at = null;
  let opaqueA = 0;
  let opaqueB = 0;
  for (let i = 0; i < a.bytes.length; i += 4) {
    if (a.bytes[i + 3] > 0) opaqueA++;
    if (b.bytes[i + 3] > 0) opaqueB++;
    let pixelWorst = 0;
    for (let c = 0; c < 3; c++) {
      // Straight RGB is meaningless where alpha is small — a pixel covered
      // 3/255 carries its full undiluted colour (hidden-state #29). Compare
      // premultiplied or a 3/255 disagreement reads as a delta of 240.
      const pa = Math.round((a.bytes[i + c] * a.bytes[i + 3]) / 255);
      const pb = Math.round((b.bytes[i + c] * b.bytes[i + 3]) / 255);
      pixelWorst = Math.max(pixelWorst, Math.abs(pa - pb));
    }
    pixelWorst = Math.max(pixelWorst, Math.abs(a.bytes[i + 3] - b.bytes[i + 3]));
    if (pixelWorst > 0) {
      differing++;
      if (pixelWorst > worst) {
        worst = pixelWorst;
        const p = i / 4;
        at = `(${p % a.width}, ${Math.floor(p / a.width)})`;
      }
    }
  }
  return { differing, worst, at, opaqueA, opaqueB };
}

const variants = [...new Set(Object.keys(ours).map((k) => k.split('|')[0]))];
const browser = await chromium.launch({ channel: 'chrome' });
const page = await browser.newPage({
  viewport: { width: SIZE, height: SIZE },
  deviceScaleFactor: 1,
});

/** Loads one document and returns its decoded pixels. */
async function render(svg, tag) {
  const file = join(workDir, `${tag}.html`);
  writeFileSync(file, wrap(svg));
  await page.goto(`file://${file.replace(/\\/g, '/')}`);
  const png = await page.screenshot({ omitBackground: true });
  return decodePng(png);
}

const rows = [];
let checked = 0;
let identical = 0;
const unexpected = [];
const expectedSeen = [];

for (const variant of variants) {
  for (const n of corpus.names) {
    for (const p of corpus.palettes) {
      for (const square of [false, true]) {
      const key = `${variant}|${n.id}|${p.id}|${square ? 'sq' : 'rd'}`;
      const oursSvg = ours[key];
      if (!oursSvg) throw new Error(`emit.dart produced nothing for ${key}`);

      // Upstream, rendered fresh and unnormalised.
      //
      // Some inputs make upstream throw rather than degrade — `beam` hands an
      // empty palette's `undefined` to `getContrast`, which calls `.slice` on
      // it. None of the four ported variants does, so a throw here is news
      // rather than something to swallow.
      let theirsSvg;
      try {
        theirsSvg = renderToStaticMarkup(
          React.createElement(Avatar, {
            variant,
            name: n.value,
            colors: p.value,
            size: SIZE,
            square,
          }),
        );
      } catch (e) {
        unexpected.push(
          `${key}: upstream threw ${e?.constructor?.name ?? 'Error'} — no ` +
            `picture to compare`,
        );
        checked++;
        continue;
      }

      const a = await render(theirsSvg, 'upstream');
      const b = await render(oursSvg, 'ours');
      const result = compare(a, b);
      checked++;

      const expected = EXPECTED_DIVERGENCE[variant]?.has(n.id) ?? false;
      if (result.differing === 0) {
        identical++;
        if (expected) {
          unexpected.push(
            `${key}: listed as a ruled divergence (S-1) but the pixels agree ` +
              `— the repair is no longer firing`,
          );
        }
      } else if (expected) {
        expectedSeen.push({ key, ...result, bytesEqual: theirsSvg === oursSvg });
      } else {
        unexpected.push(
          `${key}: ${result.differing} px differ, worst ${result.worst} at ` +
            `${result.at} (upstream ${result.opaqueA} painted px, ours ` +
            `${result.opaqueB})`,
        );
        writeFileSync(join(workDir, `DIFF-${key.replace(/\|/g, '_')}.upstream.svg`), theirsSvg);
        writeFileSync(join(workDir, `DIFF-${key.replace(/\|/g, '_')}.ours.svg`), oursSvg);
      }
      rows.push({ key, ...result, expected });
      }
    }
  }
  process.stderr.write(`  ${variant} done\n`);
}

await browser.close();

writeFileSync(
  join(workDir, 'report.json'),
  `${JSON.stringify(rows, null, 2)}\n`,
);

console.log('');
console.log(
  `checked ${checked} renders at size ${SIZE} — ` +
    `${variants.length} variants × ${corpus.names.length} names × ` +
    `${corpus.palettes.length} palettes × 2 (square on and off)`,
);
console.log(`${identical} pixel-identical`);

// Named, not omitted. A harness that ran four of six and printed a pass reads
// as "everything agrees" — the two absent names have to be in its own output.
console.log('');
if (uncovered.length === 0) {
  console.log('coverage: all six upstream variants');
} else {
  console.log(
    `⚠ NOT COVERED: ${uncovered.join(', ')} — upstream dispatches ` +
      `${emitted.upstreamVariants.length} variants at 1.6.1 and this package ` +
      `has ported ${emitted.portedVariants.length}. There is no scene of ours ` +
      `to compare, so these are unmeasured rather than passing (#38, #41).`,
  );
}

console.log('');
console.log('ruled divergences (divergence ledger S-1):');
if (expectedSeen.length === 0) {
  console.log('  none seen');
}
for (const d of expectedSeen) {
  console.log(
    `  ${d.key}: ${d.differing} px differ — upstream paints ${d.opaqueA}, ` +
      `ours ${d.opaqueB}${d.opaqueA === 0 ? '  (upstream is BLANK, as ruled)' : ''}`,
  );
}

console.log('');
if (unexpected.length === 0) {
  console.log(
    `PASS — every unruled render of the ${variants.length} ported variants is ` +
      `pixel-identical to upstream's own output.` +
      (uncovered.length === 0 ? '' : ` ${uncovered.join(' and ')} untested.`),
  );
} else {
  console.log(`FAIL — ${unexpected.length} unruled differences:`);
  for (const u of unexpected) console.log(`  ${u}`);
  process.exitCode = 1;
}
