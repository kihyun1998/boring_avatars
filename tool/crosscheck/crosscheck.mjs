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
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
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
 * Stop after this many renders. For iterating on the harness itself; a capped
 * run is **not** a verification run.
 *
 * It is printed in the summary and written into the report's own header, so a
 * capped run cannot be mistaken for a full one. A tool that quietly checked 20
 * of 800 and said "PASS" is the silent-truncation failure this project keeps
 * writing rules about.
 */
const LIMIT = Number(process.env.CROSSCHECK_LIMIT ?? 0) || Infinity;

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
const oursPath = join(workDir, 'ours.json');
if (!existsSync(oursPath)) {
  // Step one has not been run for this directory. Said plainly, because the
  // raw ENOENT stack this used to throw sends you reading `readFileSync`
  // rather than the two-line usage at the top of this file.
  console.error(`no ours.json in ${workDir} — run step one first:`);
  console.error(`  dart run tool/crosscheck/emit.dart ${workDir}`);
  process.exit(2);
}
const emitted = JSON.parse(readFileSync(oursPath, 'utf8'));
const ours = emitted.renders;
const refused = emitted.refused ?? {};
const agreedRefusals = [];
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

/**
 * The human-readable side of the run: every case, upstream beside ours, plus a
 * live difference panel — open `report.html` in a browser.
 *
 * **Each render is an `<img>` with a data URI, not inline SVG.** Inlining 1600
 * documents into one page puts `mask__ring` in it 400 times, and every
 * `url(#mask__ring)` then resolves to the *first* one — the page would show a
 * picture no browser produces. Rewriting the ids to be unique would defeat the
 * point of this harness, which exists precisely because the byte gate
 * normalises ids away. An `<img>` gives each document its own scope, which is
 * what a browser does with an SVG file anyway.
 *
 * The difference panel stacks the two with `mix-blend-mode: difference` over
 * white: **black means identical**, and anything visible is a disagreement.
 */
function buildReport(rows) {
  const dataUri = (svg) =>
    `data:image/svg+xml;base64,${Buffer.from(svg, 'utf8').toString('base64')}`;
  const escape = (s) =>
    s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

  // Differences first — a report you have to scroll 790 agreeing cases to
  // reach the interesting ten is a report nobody reads to the end.
  const sorted = [...rows].sort(
    (a, b) => b.differing - a.differing || a.key.localeCompare(b.key),
  );

  const card = (r) => {
    const state = r.differing === 0 ? 'same' : r.expected ? 'ruled' : 'bad';
    const label =
      r.differing === 0
        ? 'identical'
        : `${r.differing.toLocaleString()} px differ · worst ${r.worst} at ${r.at}`;
    return `<figure class="card ${state}">
  <figcaption>
    <code>${escape(r.key)}</code>
    <span class="badge">${label}</span>
    <span class="note">upstream paints ${r.opaqueA.toLocaleString()} px · ours ${r.opaqueB.toLocaleString()}${
      r.bytesEqual ? ' · bytes identical' : ' · bytes differ'
    }</span>
  </figcaption>
  <div class="panes">
    <div><span>upstream</span><img src="${dataUri(r.theirsSvg)}" alt=""></div>
    <div><span>ours</span><img src="${dataUri(r.oursSvg)}" alt=""></div>
    <div class="diff"><span>difference</span><div class="stack">
      <div class="layer"><img src="${dataUri(r.theirsSvg)}" alt=""></div>
      <div class="layer"><img src="${dataUri(r.oursSvg)}" alt=""></div>
    </div></div>
  </div>
</figure>`;
  };

  const counts = {
    same: rows.filter((r) => r.differing === 0).length,
    ruled: rows.filter((r) => r.differing > 0 && r.expected).length,
    bad: rows.filter((r) => r.differing > 0 && !r.expected).length,
  };

  return `<!doctype html><meta charset="utf-8">
<title>boring_avatars — upstream vs ours</title>
<style>
  :root { color-scheme: light dark; --bg:#fff; --fg:#111; --line:#d8d8d8; --muted:#666; }
  @media (prefers-color-scheme: dark) {
    :root { --bg:#161616; --fg:#eee; --line:#333; --muted:#999; }
  }
  body { margin:0; padding:24px; background:var(--bg); color:var(--fg);
         font:14px/1.5 ui-sans-serif, system-ui, sans-serif; }
  h1 { font-size:18px; margin:0 0 4px; }
  .summary { color:var(--muted); margin-bottom:4px; }
  .warn { color:#b45309; font-weight:600; margin:12px 0; }
  .legend { color:var(--muted); margin-bottom:16px; }
  .filters { position:sticky; top:0; background:var(--bg); padding:12px 0;
             border-bottom:1px solid var(--line); margin-bottom:16px; z-index:1; }
  button { font:inherit; padding:6px 12px; margin-right:8px; cursor:pointer;
           border:1px solid var(--line); border-radius:6px;
           background:transparent; color:inherit; }
  button[aria-pressed="true"] { background:var(--fg); color:var(--bg); }
  .grid { display:grid; gap:16px;
          grid-template-columns:repeat(auto-fill, minmax(340px, 1fr)); }
  .card { margin:0; border:1px solid var(--line); border-radius:8px;
          padding:10px; content-visibility:auto;
          contain-intrinsic-size:auto 200px; }
  .card.bad { border-color:#dc2626; border-width:2px; }
  .card.ruled { border-color:#d97706; }
  figcaption { display:flex; flex-wrap:wrap; gap:6px; align-items:baseline;
               margin-bottom:8px; }
  code { font:12px ui-monospace, monospace; }
  .badge { font-size:11px; padding:1px 6px; border-radius:999px;
           border:1px solid var(--line); }
  .bad .badge { background:#dc2626; color:#fff; border-color:#dc2626; }
  .ruled .badge { background:#d97706; color:#fff; border-color:#d97706; }
  .note { font-size:11px; color:var(--muted); width:100%; }
  .panes { display:grid; grid-template-columns:repeat(3, 1fr); gap:8px; }
  .panes > div { text-align:center; }
  .panes span { display:block; font-size:11px; color:var(--muted);
                margin-bottom:4px; }
  /* A checkerboard, so a transparent render is visibly transparent rather
     than looking like a white one — the S-1 cases are exactly that. */
  .panes img, .stack { width:100%; aspect-ratio:1; border-radius:4px;
    background-color:#fff;
    background-image:linear-gradient(45deg,#e8e8e8 25%,transparent 25%),
      linear-gradient(-45deg,#e8e8e8 25%,transparent 25%),
      linear-gradient(45deg,transparent 75%,#e8e8e8 75%),
      linear-gradient(-45deg,transparent 75%,#e8e8e8 75%);
    background-size:12px 12px;
    background-position:0 0,0 6px,6px -6px,-6px 0; }
  /* Black, not white. Over white, two *transparent* renders — an empty palette
     agreeing with an empty palette — composite to white, so the one legend the
     page has ("black means identical") would have a visible counter-example on
     every empty-palette card. Over black all three cases agree: both blank is
     black, two identical drawings difference to black, and one-sided content
     shows. Caught by looking at the page rather than at the code. */
  .stack { position:relative; background:#000; background-image:none; }
  /* Each render is flattened onto opaque black **before** the difference is
     taken. Blending the two transparent images directly does not work: a blend
     mode is applied and then re-interpolated by the source alpha, so at an
     antialiased edge with alpha a the result is a·(1−a)·c rather than zero —
     every mask rim grew a faint coloured ring on cards the numbers called
     identical. The page's one legend would then have a counter-example on most
     of its cards. Found by looking at the page, not at the code. */
  .layer { position:absolute; inset:0; background:#000; }
  .layer:last-child { mix-blend-mode:difference; }
  .stack img { position:absolute; inset:0; width:100%; height:100%;
               background:none; border-radius:0; }
  body.only-diff .card.same { display:none; }
  body.only-bad .card:not(.bad) { display:none; }
</style>
<h1>boring_avatars — upstream's own render vs ours, in the same browser</h1>
<p class="summary">${rows.length} renders at ${SIZE}px ·
  <strong>${counts.same}</strong> pixel-identical ·
  ${counts.ruled} ruled divergence${counts.ruled === 1 ? '' : 's'} (S-1) ·
  <strong>${counts.bad}</strong> unruled</p>
${
  rows.length < total
    ? `<p class="warn">⚠ CAPPED at CROSSCHECK_LIMIT=${LIMIT} —
       ${total - rows.length} of ${total} renders were never made. A run for
       iterating on the harness, not a verification run.</p>`
    : ''
}
${
  uncovered.length
    ? `<p class="warn">⚠ NOT COVERED: ${uncovered.join(', ')} — upstream
       dispatches ${emitted.upstreamVariants.length} variants at 1.6.1 and this
       package has ported ${emitted.portedVariants.length}. Unmeasured, not
       passing (#38, #41).</p>`
    : ''
}
<p class="legend">The <em>difference</em> panel stacks the two with
  <code>mix-blend-mode: difference</code>: <strong>black means identical</strong>.
  Each render is its own document (a data-URI image) — inlining them would put
  the same <code>id</code> in the page hundreds of times and every
  <code>url(#…)</code> would resolve to the first one.</p>
<div class="filters">
  <button aria-pressed="true" data-mode="">all ${rows.length}</button>
  <button aria-pressed="false" data-mode="only-diff">differing ${
    counts.ruled + counts.bad
  }</button>
  <button aria-pressed="false" data-mode="only-bad">unruled ${counts.bad}</button>
</div>
<div class="grid">
${sorted.map(card).join('\n')}
</div>
<script>
  document.querySelectorAll('.filters button').forEach((b) => {
    b.addEventListener('click', () => {
      document.body.className = b.dataset.mode;
      document.querySelectorAll('.filters button').forEach((o) =>
        o.setAttribute('aria-pressed', String(o === b)));
    });
  });
</script>
`;
}

const variants = [...new Set(Object.keys(ours).map((k) => k.split('|')[0]))];
const browser = await chromium.launch({ channel: 'chrome' });
const page = await browser.newPage({
  viewport: { width: SIZE, height: SIZE },
  deviceScaleFactor: 1,
});

/**
 * Loads one document and returns its decoded pixels.
 *
 * `setContent`, not a temp file and a `file://` navigation. The first version
 * wrote 1600 HTML files and navigated to each; one run died on a navigation
 * that never resolved and the next run of the same code passed, which is the
 * signature of the filesystem rather than the document. Nothing here needs a
 * file to exist, so the failure mode is removed rather than retried.
 */
async function render(svg) {
  await page.setContent(wrap(svg), { waitUntil: 'load' });
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
      if (checked >= LIMIT) continue;
      const key = `${variant}|${n.id}|${p.id}|${square ? 'sq' : 'rd'}`;
      const oursSvg = ours[key];
      const weRefused = refused[key];
      if (!oursSvg && !weRefused) {
        throw new Error(`emit.dart produced nothing for ${key}`);
      }

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
        // **Both sides refusing is agreement, and it is the strongest form of
        // it.** Upstream produces no document for an empty palette under
        // `beam`, so there is nothing to render and nothing to diff — the only
        // comparable fact is *that* it refused, and this port refuses too
        // (the user's ruling of 2026-08-06, in the divergence ledger).
        //
        // Counted separately from `identical` rather than folded into it: a
        // pixel comparison never happened, and a harness that reported 800
        // identical renders when 40 of them were two exceptions would be
        // claiming evidence it does not have.
        if (weRefused) {
          agreedRefusals.push(key);
          checked++;
          continue;
        }
        unexpected.push(
          `${key}: upstream threw ${e?.constructor?.name ?? 'Error'} — no ` +
            `picture to compare`,
        );
        checked++;
        continue;
      }

      // Upstream produced a document and we did not. That is a real
      // divergence — the port refuses an input the reference renders — and it
      // has to be news rather than a silent skip.
      if (weRefused) {
        unexpected.push(
          `${key}: this port refused (${weRefused}) but upstream rendered a ` +
            `document — the refusal is wider than upstream's`,
        );
        checked++;
        continue;
      }

      const a = await render(theirsSvg);
      const b = await render(oursSvg);
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
      rows.push({
        key,
        ...result,
        expected,
        bytesEqual: theirsSvg === oursSvg,
        theirsSvg,
        oursSvg,
      });
      }
    }
  }
  process.stderr.write(`  ${variant} done\n`);
}

await browser.close();

// Declared before the report is built: `buildReport` prints the cap warning
// and a `const` is not hoisted, so reading `total` from inside it while it is
// still below would be a ReferenceError rather than a missing warning.
const total =
  variants.length * corpus.names.length * corpus.palettes.length * 2;
const capped = checked < total;

writeFileSync(
  join(workDir, 'report.json'),
  `${JSON.stringify(rows, null, 2)}\n`,
);
writeFileSync(join(workDir, 'report.html'), buildReport(rows));

console.log('');
console.log(
  `checked ${checked} renders at size ${SIZE} — ` +
    `${variants.length} variants × ${corpus.names.length} names × ` +
    `${corpus.palettes.length} palettes × 2 (square on and off) = ${total}`,
);
console.log(`${identical} pixel-identical`);
if (capped) {
  console.log('');
  console.log(
    `⚠ CAPPED at CROSSCHECK_LIMIT=${LIMIT} — ${total - checked} of ${total} ` +
      `renders were never made. This is a run for iterating on the harness, ` +
      `not a verification run.`,
  );
}

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
if (agreedRefusals.length === 0) {
  console.log('agreed refusals: none — every input produced two documents');
} else {
  const byVariant = {};
  for (const k of agreedRefusals) {
    const v = k.split('|')[0];
    byVariant[v] = (byVariant[v] ?? 0) + 1;
  }
  console.log(
    `agreed refusals: ${agreedRefusals.length} — both upstream and this port ` +
      `produced no document (${Object.entries(byVariant)
        .map(([v, n]) => `${v} ${n}`)
        .join(', ')}). Not counted as pixel-identical: no pixels were ` +
      `compared.`,
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
    `${capped ? 'PASS (CAPPED — not a verification run)' : 'PASS'} — every ` +
      `unruled render checked of the ${variants.length} ported variants is ` +
      `pixel-identical to upstream's own output.` +
      (uncovered.length === 0 ? '' : ` ${uncovered.join(' and ')} untested.`),
  );
} else {
  console.log(`FAIL — ${unexpected.length} unruled differences:`);
  for (const u of unexpected) console.log(`  ${u}`);
  process.exitCode = 1;
}

console.log('');
console.log(`look at it:  ${join(workDir, 'report.html')}`);
