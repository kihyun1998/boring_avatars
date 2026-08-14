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

import { execFileSync, execSync } from 'node:child_process';
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { register } from 'node:module';
import { gunzipSync } from 'node:zlib';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

// boring-avatars 2.0.x ships an ESM build whose relative imports have no file
// extension, which Node's resolver rejects — the hook (owned by
// tool/versions, which hit this first) adds the extension back so the real
// published package loads as-is. Registered before any upstream import below;
// inert for the CJS-era packages.
register('../versions/ext-hook.mjs', import.meta.url);

import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '..', '..');
const REFS = resolve(REPO, '..', '.refs', 'boring-avatars');

/**
 * Every upstream version this package supports, and how to reach it.
 *
 * `titleProp` says whether the release has a `title` prop at all. At 1.6.x it
 * does not — `<title>` is unconditional — so there is no second set of renders
 * to take. From 1.7.0 the prop exists and defaults to **off**, and both sides
 * of it have to be in the fixture or half the release is unproven.
 *
 * `crossCheck` names the other releases inside the same selector that *can* be
 * rendered, and `bySourceTree` the ones that cannot. Both exist because
 * "these four versions produce the same thing" is a claim about a measurement,
 * and a claim whose evidence cannot be re-run is one nobody can check.
 */
const SUPPORTED = {
  v1_6_1: {
    tag: 'v1.6.1',
    pkg: 'upstream-1.6.1',
    releases: ['1.6.1', '1.6.2', '1.6.3'],
    titleProp: false,
    // No `crossCheck`: 1.6.2 and 1.6.3 have nothing to cross-check *against*.
    // Their `src/lib` tree is 1.6.1's, byte for byte, so rendering them would
    // be running the same source twice and calling the second run evidence.
    //
    // **Backfilled in #43.** The shipped `0.1.0` selector claimed three
    // releases and its fixture recorded no measurement that they agree — the
    // grouping lived in `tool/versions/group.mjs` and a prose note, neither of
    // which `flutter test` can see. #43's new fixture assertion, written for a
    // four-release selector, went red on the three-release one that was
    // already published.
    bySourceTree: { '1.6.1': 'v1.6.1', '1.6.2': 'v1.6.2', '1.6.3': 'v1.6.3' },
  },
  v1_7_0: {
    tag: 'v1.7.0',
    pkg: 'upstream-1.7.0',
    releases: ['1.7.0', '1.8.0', '1.9.0', '1.10.0'],
    titleProp: true,
    // 1.10.0 renders, and differs from 1.7.0 only in the mask id — a literal
    // at 1.7.0, `React.useId()` from 1.8.0. Rendered and compared here rather
    // than asserted in prose.
    crossCheck: { '1.10.0': 'upstream-1.10.0' },
    // 1.8.0 and 1.9.0 ship no JavaScript on npm at all (`main` points at a
    // `build/index.js` that is not in the tarball — 0 JS files, verified by
    // download), so nothing can render them. Their evidence is that their
    // `src/lib` git tree *is* 1.10.0's, byte for byte.
    bySourceTree: { '1.8.0': 'v1.8.0', '1.9.0': 'v1.9.0', '1.10.0': 'v1.10.0' },
  },
  v1_10_1: {
    tag: 'v1.10.1',
    pkg: 'upstream-1.10.1',
    releases: [
      '1.10.1',
      '1.10.2',
      '1.11.1',
      '1.11.2',
      '2.0.0',
      '2.0.1',
      '2.0.2',
      '2.0.3',
      '2.0.4',
    ],
    titleProp: true,
    // Every covered release renders — this group has no 1.8.0-style empty
    // tarball — so each of the other eight is compared to 1.10.1's render
    // across the full matrix, and `bySourceTree` has nothing to carry. Note
    // 1.11.0 is deliberately absent: it spreads its own props onto the
    // `<svg>` element and is unsupported, not covered.
    //
    // The source trees of these nine are *not* one tree — the destructuring
    // rework and the TypeScript rewrite are real diffs — which is exactly why
    // the evidence here is the render and never the blob hash.
    crossCheck: {
      '1.10.2': 'upstream-1.10.2',
      '1.11.1': 'upstream-1.11.1',
      '1.11.2': 'upstream-1.11.2',
      '2.0.0': 'upstream-2.0.0',
      '2.0.1': 'upstream-2.0.1',
      '2.0.2': 'upstream-2.0.2',
      '2.0.3': 'upstream-2.0.3',
      '2.0.4': 'upstream-2.0.4',
    },
  },
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

async function dumpSvg(pkg, corpus, titleProp) {
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

  /**
   * The same matrix with `title: true` — the other side of 1.7.0's new prop.
   *
   * Without this the fixture would only ever have seen the prop's default, and
   * a port that ignored the argument entirely would pass every assertion in
   * the file. `<title>` carries the **name** as character data, so it is also
   * the one element where an escaping rule can differ; every corpus name is
   * here for that reason, against one palette, since the palette cannot reach
   * a title.
   */
  const titleRenders = {};
  if (titleProp) {
    for (const variant of VARIANTS) {
      for (const name of corpus.names) {
        titleRenders[`${variant}|${name.id}`] = render({
          variant,
          name: name.value,
          colors: corpus.palettes[0].value,
          size: MATRIX_SIZE,
          title: true,
        });
      }
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
    ...(titleProp ? { titleRenders } : {}),
  };
}

/**
 * The measurement behind "these releases are one selector".
 *
 * Two kinds of evidence, because the releases divide into two kinds:
 *
 * * **Rendered.** Every release in `crossCheck` is rendered across the full
 *   matrix, both values of `title`, and compared to the one the fixture was
 *   taken from. The comparison is the same `normalise` the parity tests use,
 *   which is what makes it honest to record a mismatch count of zero: the mask
 *   id really does differ (`mask__marble` at 1.7.0, `:R0:` from 1.8.0), and
 *   `rawIdSamples` records that difference rather than hiding behind the
 *   normalisation that erases it.
 * * **By source tree.** A release whose npm tarball has no JavaScript cannot be
 *   rendered by anything, ever. What can be measured is that its `src/lib` git
 *   tree is identical to one that *was* rendered.
 */
async function dumpGroupProof(spec, corpus) {
  if (!spec.crossCheck && !spec.bySourceTree) return null;

  const base = await import(spec.pkg).then((m) => m.default?.default ?? m.default);
  const renderWith = (Avatar, props) => {
    try {
      return normalise(renderToStaticMarkup(React.createElement(Avatar, props)));
    } catch (e) {
      return `__throws:${e?.constructor?.name ?? 'Error'}`;
    }
  };

  const rendered = {};
  const rawIdSamples = { [spec.releases[0]]: maskIdOf(base, corpus) };
  // Marble's **filter** id, recorded for the same reason as the mask id — but
  // its history is different and the difference is worth a witness: it is the
  // literal `prefix__filter0_f` through 1.10.1 and `filter_${useId}` from
  // 1.10.2, so inside the v1_10_1 group the rendered-from release is the one
  // that still writes a literal. `normalise` erases the divergence in the
  // comparison above; this records it unnormalised so the exclusion is
  // visible rather than implied (the #37/#40 rule).
  const rawFilterIdSamples = { [spec.releases[0]]: filterIdOf(base, corpus) };
  const idPositions = { [spec.releases[0]]: idsByPosition(base, corpus) };
  for (const [release, pkg] of Object.entries(spec.crossCheck ?? {})) {
    const other = await import(pkg).then((m) => m.default?.default ?? m.default);
    let compared = 0;
    const mismatches = [];
    for (const variant of VARIANTS) {
      for (const name of corpus.names) {
        for (const palette of corpus.palettes) {
          for (const title of [false, true]) {
            // `square` crossed too — added in #45. The #59 lesson is that a
            // prop is covered where it varies on a path something else varies
            // on, and until then this loop held `square` at its default: the
            // eight-way sibling equivalence on that axis rested on reading
            // the components' unchanged `rx={square ? …}` text, not on a
            // render. One extra axis turns that argument into a measurement.
            for (const square of [false, true]) {
              const props = {
                variant,
                name: name.value,
                colors: palette.value,
                size: MATRIX_SIZE,
                title,
                square,
              };
              compared++;
              if (renderWith(base, props) !== renderWith(other, props)) {
                mismatches.push(
                  `${variant}|${name.id}|${palette.id}|title=${title}|${square ? 'sq' : 'rd'}`,
                );
              }
            }
          }
        }
      }
    }
    rendered[release] = { compared, mismatches };
    rawIdSamples[release] = maskIdOf(other, corpus);
    rawFilterIdSamples[release] = filterIdOf(other, corpus);
    idPositions[release] = idsByPosition(other, corpus);
  }

  const bySourceTree = {};
  for (const [release, tag] of Object.entries(spec.bySourceTree ?? {})) {
    bySourceTree[release] = execFileSync(
      'git',
      ['-C', REFS, 'rev-parse', `${tag}:src/lib`],
      { encoding: 'utf8' },
    ).trim();
  }

  // **The join between the two kinds of evidence, which is otherwise assumed.**
  // The renders come from the **npm** package; the tree hashes come from the
  // **git** tag. So "1.8.0 is 1.10.0's source" and "1.10.0 renders like 1.7.0"
  // are two true sentences about two different artifacts, and the chain between
  // them has a gap: nothing said the npm build came from that git tree.
  //
  // npm records the commit it was published from. Measured: 1.7.0's `gitHead`
  // is `2f2ac13` and 1.10.0's is `378c2cd`, each equal to its tag's commit —
  // so the artifact that was rendered and the tree that was hashed are the
  // same source. Note the tags are **annotated**, so `rev-parse v1.10.0` gives
  // the tag object and only `^{commit}` gives the commit; comparing the former
  // reports a mismatch that is not one.
  // **Every release the selector claims**, not only the rendered ones. The
  // unrenderable ones are exactly where the JS-file count is the whole
  // argument, so leaving them out would omit the measurement that matters most.
  const npmProvenance = {};
  for (const release of spec.releases) {
    // From the **registry**, not from `node_modules`: npm strips `gitHead` on
    // install, so the copy on disk cannot answer this. A network call at tool
    // time is fine — this harness already installs from npm, and `flutter
    // test` never runs it.
    //
    // `execSync` with one command string, not `execFileSync`: on Windows `npm`
    // is `npm.cmd`, and Node refuses to `execFile` a `.cmd` at all
    // (`spawnSync npm.cmd EINVAL`). `tool/mutate/run.mjs` carries the same
    // note for `flutter`, which is a `.bat` — this is that trap a second time,
    // and the prescription there is this one. Nothing here is caller-supplied.
    const head = execSync(`npm view boring-avatars@${release} gitHead`, {
      encoding: 'utf8',
    }).trim();
    const treeAt = (rev) => {
      try {
        return execFileSync('git', ['-C', REFS, 'rev-parse', `${rev}:src/lib`], {
          encoding: 'utf8',
        }).trim();
      } catch {
        return null; // a commit the reference tree does not have
      }
    };
    // **A release may have no tag at all** — upstream's tags stop at v2.0.2
    // while npm's `latest` is 2.0.4. For those the join runs the other way:
    // the npm-recorded `gitHead` must resolve in the reference tree, which
    // proves the published artifact came from upstream's own history even
    // though nothing was tagged. Measured for 2.0.3 and 2.0.4: both commits
    // exist and share one `src/lib` tree, which is `master`'s.
    const tagCommit = (() => {
      try {
        return execFileSync(
          'git',
          ['-C', REFS, 'rev-parse', `v${release}^{commit}`],
          { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] },
        ).trim();
      } catch {
        return null; // no such tag
      }
    })();
    npmProvenance[release] = {
      npmJsFiles: countJsFilesOnNpm(release),
      npmGitHead: head === '' ? null : head,
      tagCommit,
      // **The trees, not the commits, are what the claim is about** — and the
      // difference is not academic. npm's 1.8.0 was published from `e393aaa`
      // while the tag `v1.8.0` points at `412a61e`: two different commits whose
      // `src/lib` is the same `bd8b225`. Asserting commit equality reported a
      // mismatch that was not one, on the release whose evidence matters most.
      npmHeadTree: head === '' ? null : treeAt(head),
      tagTree: treeAt(`v${release}`),
    };
  }

  return {
    renderedFrom: spec.releases[0],
    rendered,
    bySourceTree,
    rawIdSamples,
    rawFilterIdSamples,
    idPositions,
    npmProvenance,
  };
}

/** Marble's filter id, unnormalised — `null` for a release that writes none. */
const filterIdOf = (Avatar, corpus) =>
  renderToStaticMarkup(
    React.createElement(Avatar, {
      variant: 'marble',
      name: corpus.names[0].value,
      colors: corpus.palettes[0].value,
      size: MATRIX_SIZE,
    }),
  ).match(/<filter id="([^"]*)"/)?.[1] ?? null;

/**
 * How many JavaScript files a release's npm tarball actually contains.
 *
 * **This number is the reason 1.8.0 and 1.9.0 have no rendered evidence**, and
 * it is stated in README, CHANGELOG and `version.dart` — public claims, all of
 * them, and until #43's review they rested on a throwaway probe that had been
 * deleted. A claim whose evidence cannot be re-run is one nobody can check.
 *
 * Measured: 1.8.0 → 0, 1.9.0 → 0, 1.10.0 → 1. `main` points at
 * `build/index.js`, which for the first two is simply not in the package, so
 * nothing has ever been able to import them.
 */
function countJsFilesOnNpm(release) {
  const dest = join(HERE, '.pack');
  mkdirSync(dest, { recursive: true });
  try {
    // `execSync` with a command string for the same reason as `npm view`
    // above: on Windows `npm` is `npm.cmd` and `execFile` refuses it outright.
    const name = execSync(
      `npm pack boring-avatars@${release} --pack-destination "${dest}" --silent`,
      { encoding: 'utf8' },
    )
      .trim()
      .split('\n')
      .pop();
    // Listed with `zlib` and a 512-byte header walk rather than by shelling
    // out to `tar`. Git's GNU `tar` reads a Windows path as a *remote host*
    // (`D:\…` → "Cannot connect to D"), and which `tar` is on PATH varies by
    // machine — a portability trap in a harness whose whole point is that its
    // measurements can be re-run anywhere.
    const raw = gunzipSync(readFileSync(join(dest, name)));
    let offset = 0;
    let count = 0;
    while (offset + 512 <= raw.length) {
      const path = raw.toString('utf8', offset, offset + 100).replace(/\0.*$/, '');
      if (path === '') break; // two zero blocks end the archive
      const size = parseInt(
        raw.toString('utf8', offset + 124, offset + 136).replace(/[\0 ]/g, ''),
        8,
      );
      if (/\.(js|mjs|cjs)$/.test(path)) count++;
      offset += 512 + Math.ceil((size || 0) / 512) * 512;
    }
    return count;
  } finally {
    rmSync(dest, { recursive: true, force: true });
  }
}

/**
 * The same avatar's mask id at four positions in a render tree.
 *
 * **This is the measurement that decides what "reproduce 1.8.0" can even
 * mean.** From 1.8.0 the id comes from `React.useId()`, whose value is the
 * component's *path in the render tree* — so the identical name, palette and
 * variant come out `:R0:` alone, `:R3:` as a third child, `:R2:` after a
 * `<span>`, and **two of the same avatar in one document get two different
 * ids**. There is therefore no single byte sequence that *is* 1.8.0's output
 * for an avatar, and "byte-for-byte with 1.8.0" is not a claim anything could
 * satisfy — including 1.8.0 itself.
 *
 * Recorded rather than argued, because the grouping decision (2026-07-29) was
 * taken before this number existed.
 */
function idsByPosition(Avatar, corpus) {
  const one = () =>
    React.createElement(Avatar, {
      variant: 'marble',
      name: corpus.names[0].value,
      colors: corpus.palettes[0].value,
      size: MATRIX_SIZE,
    });
  const idsIn = (tree) =>
    [...renderToStaticMarkup(tree).matchAll(/<mask id="([^"]*)"/g)].map((m) => m[1]);
  const span = () => React.createElement('span');
  return {
    alone: idsIn(one()),
    thirdChild: idsIn(React.createElement('div', null, span(), span(), one())),
    afterSpan: idsIn(React.createElement('div', null, span(), one())),
    twiceInOneDocument: idsIn(React.createElement('div', null, one(), one())),
  };
}

/** The mask id a release actually writes, unnormalised — the thing that differs. */
const maskIdOf = (Avatar, corpus) =>
  renderToStaticMarkup(
    React.createElement(Avatar, {
      variant: 'marble',
      name: corpus.names[0].value,
      colors: corpus.palettes[0].value,
      size: MATRIX_SIZE,
    }),
  ).match(/<mask id="([^"]*)"/)[1];

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

const groupProof = await dumpGroupProof(spec, corpus);

writeFileSync(
  join(outDir, 'svg.json'),
  stableStringify({
    upstreamReleases: spec.releases,
    ...(await dumpSvg(spec.pkg, corpus, spec.titleProp)),
    ...(groupProof ? { groupProof } : {}),
  }),
);

console.log(`wrote test/fixtures/${version}/{utilities,svg}.json from upstream ${spec.tag}`);
