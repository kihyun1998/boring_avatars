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

  // The remaining helpers are pure functions of a hash. The ranges below are
  // the exact union the six components pass at v1.6.1, derived from their call
  // sites — an earlier list claimed to be that union and was not, omitting 4
  // (marble's SIZE/20), 7 (beam), and 20–23 (bauhaus's SIZE/2 - (i+17)).
  //
  //   bauhaus  getUnit(h*(i+1), 20..23, 1|2)   getUnit(h*(i+1), 360)
  //   marble   getUnit(h*(i+1), 8, 1|2)        getUnit(h*(i+1), 4)
  //            getUnit(h*(i+1), 360, 1)
  //   beam     getUnit(h, 10, 1|2|3)  getUnit(h, 3|5|7|8|360)
  //
  // getModulus is not dumped: no component imports it, and this package does
  // not port it. Dumping it made the fixture disagree with that judgement.
  const RANGES = [3, 4, 5, 7, 8, 10, 20, 21, 22, 23, 360];
  for (const { id, value } of corpus.names) {
    const n = u.hashCode(value);
    const row = { getDigit: {}, getBoolean: {}, getUnit: {}, getRandomColor: {} };
    for (const ntn of [0, 1, 2, 3, 4]) {
      row.getDigit[ntn] = u.getDigit(n, ntn);
      row.getBoolean[ntn] = u.getBoolean(n, ntn);
    }
    // bauhaus and marble pass h*(i+1), not h — so the fixture has to carry the
    // multiples too, or nothing ever puts a value above 2^31 through getUnit
    // and getDigit.
    for (const multiple of [1, 2, 3, 4]) {
      const m = n * multiple;
      if (multiple > 1) {
        for (const ntn of [0, 1, 2, 3, 4]) {
          row.getDigit[`${ntn}@${multiple}`] = u.getDigit(m, ntn);
          row.getBoolean[`${ntn}@${multiple}`] = u.getBoolean(m, ntn);
        }
      }
      for (const range of RANGES) {
        const suffix = multiple > 1 ? `@${multiple}` : '';
        row.getUnit[`${range}${suffix}`] = u.getUnit(m, range);
        // index 0 is included deliberately. Upstream gates the negation on
        // `if (index && …)`, and JavaScript treats 0 as falsy — so 0 must
        // behave like "no index". No caller passes it today, which is exactly
        // why a port gets it wrong silently unless the fixture covers it.
        for (const index of [0, 1, 2, 3]) {
          row.getUnit[`${range},${index}${suffix}`] = u.getUnit(m, range, index);
        }
      }
    }
    // The number reaching getRandomColor is never just the hash. Upstream
    // passes `h` (beam's wrapper), `h + i` (bauhaus, marble, ring, sunset),
    // `h + 13` (beam's background) and — in pixel — `h % i` for i = 0..63.
    // That last form includes **i = 0**, where `h % 0` is NaN and the colour
    // comes back undefined on every render, for every name and palette.
    const numbers = {
      'h': n,
      'h+1': n + 1, 'h+2': n + 2, 'h+3': n + 3, 'h+4': n + 4,
      'h+13': n + 13,
      'h%0': n % 0, 'h%1': n % 1, 'h%2': n % 2, 'h%63': n % 63,
    };
    for (const p of corpus.palettes) {
      for (const [label, num] of Object.entries(numbers)) {
        // An empty palette — and the `h % 0` NaN — make this undefined, and
        // JSON.stringify drops undefined-valued keys entirely, which would
        // make "upstream returned nothing" indistinguishable from "the dump
        // forgot this case". Coerce to null so the absence is recorded.
        const key = label === 'h' ? p.id : `${p.id}|${label}`;
        row.getRandomColor[key] = u.getRandomColor(num, p.value, p.value.length) ?? null;
      }
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

  /**
   * `square: true` — the prop that *removes* the mask's corner radius.
   *
   * The full matrix runs at `square: false` only, so until #37 nothing in this
   * fixture had ever seen the other value: the port's `square` handling was
   * asserted for self-consistency ("rx is absent when true") and a golden was
   * committed for it, but neither had been compared to upstream. That is the
   * "golden that agrees with itself" trap with an extra step.
   *
   * Two names and every palette per variant, rather than the full matrix.
   * `square` reaches exactly one attribute and cannot interact with the hash —
   * which is the claim these renders test rather than assume, since a second
   * name and the degenerate palettes would expose it if it did.
   */
  const squareNames = ['upstream-default', 'emoji-zwj'];
  const squareRenders = {};
  for (const variant of VARIANTS) {
    for (const name of corpus.names.filter((n) => squareNames.includes(n.id))) {
      for (const palette of corpus.palettes) {
        squareRenders[`${variant}|${name.id}|${palette.id}`] = render({
          variant,
          name: name.value,
          colors: palette.value,
          size: MATRIX_SIZE,
          square: true,
        });
      }
    }
  }

  /**
   * The **raw** id each variant gives its mask, and the raw reference to it.
   *
   * `normalise` erases both, on our side and the fixture's — so "byte for byte"
   * silently excluded them, and mutating `mask__ring` to `mask__pixel` or the
   * group's `url(#…)` to a dangling reference left the whole suite green. That
   * exclusion is right for the *generated* ids of 1.8.0 onward, and buys
   * nothing at 1.6.1 where every id is a literal in the JSX. Recorded
   * unnormalised so the literals can be asserted.
   */
  const maskIdentifiers = {};
  for (const variant of VARIANTS) {
    const raw = renderToStaticMarkup(
      React.createElement(Avatar, {
        variant,
        name: corpus.names[0].value,
        colors: corpus.palettes[0].value,
        size: MATRIX_SIZE,
      }),
    );
    maskIdentifiers[variant] = {
      ids: [...raw.matchAll(/<mask id="([^"]*)"/g)].map((m) => m[1]),
      references: [...raw.matchAll(/ mask="url\(#([^)]*)\)"/g)].map((m) => m[1]),
    };
  }

  /**
   * Every `id` and `url(#…)` a variant emits, unnormalised, **per name**.
   *
   * `maskIdentifiers` above covers the mask, whose id is a per-variant literal.
   * `sunset` is the case that needs more: its gradient ids are derived from the
   * *name* — `'gradient_paint0_linear_' + props.name.replace(/\s/g, '')` — and
   * `normalise` erases them on both sides, so the byte comparison cannot see
   * them at all. A port that skipped the whitespace strip, or used a different
   * whitespace class, would pass the entire parity sweep.
   *
   * Every name in the corpus, because that is the input the derivation reads.
   */
  const derivedIdentifiers = {};
  for (const variant of VARIANTS) {
    const perName = {};
    for (const name of corpus.names) {
      const raw = renderToStaticMarkup(
        React.createElement(Avatar, {
          variant,
          name: name.value,
          colors: corpus.palettes[0].value,
          size: MATRIX_SIZE,
        }),
      );
      perName[name.id] = {
        ids: [...raw.matchAll(/ id="([^"]*)"/g)].map((m) => m[1]),
        references: [...raw.matchAll(/url\(#([^)]*)\)/g)].map((m) => m[1]),
      };
    }
    derivedIdentifiers[variant] = perName;
  }

  /**
   * `size`, for every variant — and crossed with a second axis, because one
   * axis was not enough twice running.
   *
   * The section covered `marble` alone from #33 to #59: a prop compared to
   * upstream on one variant and to nothing on the other five, which is the
   * hole `square` had until #37. It went unnoticed while `size` was an
   * argument to six separate builders and became reachable the moment #59 put
   * a dispatch in front of them — five of six arms could then drop the
   * caller's `size` with the whole suite green.
   *
   * Widening it per variant closed that and left the *next* one open, which
   * the #59 completeness pass then measured: with one name, one palette and
   * `square: false`, an arm honouring `size` only for `Clara Barton`, or
   * dropping it whenever `square` is set, still passed all 677 tests. So the
   * unit is not "the prop varies per variant" — it is "per variant, on a path
   * where something else varies too".
   *
   * Two names (one of them the empty string, whose hash is 0) × two sizes ×
   * both `square` values. The palette stays at one: `size` cannot interact
   * with the palette without first interacting with the hash, which the two
   * names already test.
   */
  const sizeNames = ['upstream-default', 'empty'];
  const sizePassthrough = {};
  for (const variant of VARIANTS) {
    for (const name of corpus.names.filter((n) => sizeNames.includes(n.id))) {
      for (const size of corpus.sizes) {
        for (const square of [false, true]) {
          const key = `${variant}|${name.id}|${size}|${square ? 'sq' : 'rd'}`;
          sizePassthrough[key] = render({
            variant,
            name: name.value,
            colors: corpus.palettes[0].value,
            size,
            square,
          });
        }
      }
    }
  }

  /**
   * `size` as a **string** — the other half of the public parameter's type.
   *
   * `corpus.sizes` is a list of integers, so no section here could ever record
   * what upstream does with `'100%'`. Until #59's completeness pass that half
   * was covered by a *throwaway probe*, deleted after it ran, and by a test
   * comparing the package to its own 80-render on `marble` — which is this
   * repo's own "a fixture that regenerates itself is not a proof" trap with
   * the fixture left out entirely, and a claim whose evidence cannot be re-run
   * is one nobody can check.
   *
   * React writes an unrecognised attribute value through the same escaping as
   * any other, so `'a"b'` is here too: it is the case where the passthrough
   * and the serialisation meet.
   */
  const sizeStrings = ['100%', '2rem', '40px', '80', 'a"b'];
  const sizePassthroughStrings = {};
  for (const variant of VARIANTS) {
    for (const size of sizeStrings) {
      sizePassthroughStrings[`${variant}|${size}`] = render({
        variant,
        name: corpus.names[0].value,
        colors: corpus.palettes[0].value,
        size,
      });
    }
  }

  return {
    matrixSize: MATRIX_SIZE,
    renders,
    squareRenders,
    maskIdentifiers,
    derivedIdentifiers,
    sizePassthrough,
    sizePassthroughStrings,
  };
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
