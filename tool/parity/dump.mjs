// Generates the parity fixtures for one supported upstream version.
//
//   node dump.mjs v1_6_1
//
// Two fixtures come out, because upstream exposes its two layers very
// differently:
//
//   utilities.json — imported straight from the pinned reference tree.
//                    utilities.js exports all eight functions and contains no
//                    JSX, so the real implementations can be called directly.
//
//   svg.json       — rendered from the real npm package through
//                    react-dom/server. The per-variant generators are NOT
//                    exported by any component, so their values are only
//                    observable as the attributes they end up in. Byte equality
//                    on this output therefore stands in for a per-variant value
//                    fixture — every value that reaches the drawing is in here.
//
// Both are written under test/fixtures/<version>/ and committed. flutter test
// reads those files and never runs this script.

import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '..', '..');
const REFS = resolve(REPO, '..', '.refs', 'boring-avatars');

/** Every upstream version this package supports, and how to reach it. */
const SUPPORTED = {
  v1_6_1: { tag: 'v1.6.1', pkg: 'upstream-1.6.1', releases: ['1.6.1', '1.6.2', '1.6.3'] },
};

const VARIANTS = ['marble', 'beam', 'pixel', 'sunset', 'ring', 'bauhaus'];

/**
 * Ids upstream generates per render — React's useId, or a hand-rolled
 * `prefix__` — are internal references, not drawing. They are normalised away.
 *
 * `<title>` is deliberately NOT normalised: 1.6.1 emits it unconditionally and
 * 1.7.0 gates it behind a prop, which is a real difference between the versions
 * we have to reproduce.
 */
const normalise = (svg) =>
  svg
    .replace(/id="[^"]*"/g, 'id="_"')
    .replace(/url\(#[^)]*\)/g, 'url(#_)')
    .replace(/mask="[^"]*"/g, 'mask="_"')
    .replace(/(gradient_paint\d_linear_)\S+?"/g, '$1_"');

/** Deterministic JSON — keys sorted, so two runs cannot differ by ordering. */
const stableStringify = (value) => {
  const walk = (v) => {
    if (Array.isArray(v)) return v.map(walk);
    if (v && typeof v === 'object') {
      return Object.fromEntries(Object.keys(v).sort().map((k) => [k, walk(v[k])]));
    }
    return v;
  };
  return `${JSON.stringify(walk(value), null, 2)}\n`;
};

/** Checks the reference tree out at `tag` and imports its utilities module. */
async function loadUtilities(tag) {
  execFileSync('git', ['-C', REFS, 'checkout', '--quiet', tag], { stdio: 'inherit' });
  const source = readFileSync(join(REFS, 'src', 'lib', 'utilities.js'), 'utf8');
  // The reference tree has no "type": "module", so the file has to be handed to
  // Node under an extension that forces ESM.
  const tmp = join(HERE, `.utilities.${tag.replace(/[^\w.]/g, '_')}.mjs`);
  writeFileSync(tmp, source);
  try {
    return await import(pathToFileURL(tmp).href);
  } finally {
    rmSync(tmp, { force: true });
  }
}

function dumpUtilities(u, corpus) {
  const out = { hashCode: {}, getContrast: {}, derived: {} };

  for (const { id, value } of corpus.names) {
    out.hashCode[id] = u.hashCode(value);
  }

  // getContrast is fed every colour in every palette, plus the two extremes.
  const colours = new Set(['#000000', '#FFFFFF', '#808080', '#7F7F7F']);
  for (const p of corpus.palettes) for (const c of p.value) colours.add(c);
  for (const c of [...colours].sort()) out.getContrast[c] = u.getContrast(c);

  // The remaining helpers are pure functions of a hash, so they are sampled
  // across every corpus name at the ranges the variants actually use.
  for (const { id, value } of corpus.names) {
    const n = u.hashCode(value);
    const row = { getModulus: {}, getDigit: {}, getBoolean: {}, getUnit: {}, getRandomColor: {} };
    for (const max of [2, 3, 5, 8, 10, 360, 64]) row.getModulus[max] = u.getModulus(n, max);
    for (const ntn of [0, 1, 2, 3, 4]) {
      row.getDigit[ntn] = u.getDigit(n, ntn);
      row.getBoolean[ntn] = u.getBoolean(n, ntn);
    }
    for (const range of [3, 5, 8, 10, 360]) {
      row.getUnit[`${range}`] = u.getUnit(n, range);
      for (const index of [1, 2, 3]) {
        row.getUnit[`${range},${index}`] = u.getUnit(n, range, index);
      }
    }
    for (const p of corpus.palettes) {
      row.getRandomColor[p.id] = u.getRandomColor(n, p.value, p.value.length);
    }
    out.derived[id] = row;
  }

  return out;
}

/**
 * The full matrix renders at one size only.
 *
 * `size` is a pure passthrough: it lands on the `<svg>` element's width and
 * height and nothing else, because the viewBox is a per-variant constant.
 * Measured, not assumed — across all 480 pairs in an earlier full run, every
 * 40-vs-80 pair differed in exactly those two attributes and nowhere else.
 * Carrying the dimension would have doubled the fixture for no coverage.
 *
 * `sizePassthrough` below keeps that claim honest: if a future version ever
 * lets size reach the drawing, it breaks there.
 */
const MATRIX_SIZE = 80;

async function dumpSvg(pkg, corpus) {
  const mod = await import(pkg);
  const Avatar = mod.default?.default ?? mod.default;
  // Some inputs make upstream throw rather than degrade — an empty palette
  // feeds `undefined` into beam's getContrast, which calls .slice on it. That
  // is upstream behaviour too, so the fixture records it instead of the run
  // dying. Only the error's constructor name is stored: the message comes from
  // minified internals and is not stable across reinstalls.
  const render = (props) => {
    try {
      return normalise(renderToStaticMarkup(React.createElement(Avatar, props)));
    } catch (e) {
      return { __throws: e?.constructor?.name ?? 'Error' };
    }
  };

  const renders = {};
  for (const variant of VARIANTS) {
    for (const name of corpus.names) {
      for (const palette of corpus.palettes) {
        renders[`${variant}|${name.id}|${palette.id}`] = render({
          variant,
          name: name.value,
          colors: palette.value,
          size: MATRIX_SIZE,
        });
      }
    }
  }

  const sizePassthrough = {};
  for (const size of corpus.sizes) {
    sizePassthrough[`${size}`] = render({
      variant: 'marble',
      name: corpus.names[0].value,
      colors: corpus.palettes[0].value,
      size,
    });
  }

  return { matrixSize: MATRIX_SIZE, renders, sizePassthrough };
}

const version = process.argv[2];
const spec = SUPPORTED[version];
if (!spec) {
  console.error(
    `usage: node dump.mjs <version>\nsupported: ${Object.keys(SUPPORTED).join(', ')}`,
  );
  process.exit(2);
}

const corpus = JSON.parse(readFileSync(join(REPO, 'test', 'fixtures', 'corpus.json'), 'utf8'));
const outDir = join(REPO, 'test', 'fixtures', version);
mkdirSync(outDir, { recursive: true });

const utilities = await loadUtilities(spec.tag);
writeFileSync(
  join(outDir, 'utilities.json'),
  stableStringify({ upstreamReleases: spec.releases, tag: spec.tag, ...dumpUtilities(utilities, corpus) }),
);

writeFileSync(
  join(outDir, 'svg.json'),
  stableStringify({ upstreamReleases: spec.releases, ...(await dumpSvg(spec.pkg, corpus)) }),
);

console.log(`wrote test/fixtures/${version}/{utilities,svg}.json from upstream ${spec.tag}`);
