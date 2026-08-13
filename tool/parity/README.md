# Parity harness

Generates the fixtures that pin this package to the real `boring-avatars`.

**This is a tool, not a gate.** `flutter test` reads the committed fixtures and
never runs Node — so the test suite needs no network, no npm state, and no
working reference tree. What the gate actually catches is a *fixture* changing:
regenerating produces a reviewable `git diff`, and a parity break shows up there
instead of being absorbed into a silently-adjusted expectation.

## One-time setup

The reference tree lives outside the repo, next to it, so nothing needs
gitignoring:

```bash
mkdir -p ../../../.refs && cd ../../../.refs
git clone --filter=blob:none --sparse https://github.com/boringdesigners/boring-avatars boring-avatars
cd boring-avatars && git sparse-checkout set src/lib && git fetch --tags
```

**Do not use `--depth 1`.** Unlike the other `.refs` trees in this workspace,
this one is checked out by tag, so every tag has to be present.

Then, in this directory:

```bash
npm install
```

## Generating

```bash
node dump.mjs v1_6_1
```

Writes `test/fixtures/v1_6_1/utilities.json` and `.../svg.json`. Running it
twice produces byte-identical files; if it does not, that is a bug in the
harness, not noise to be tolerated.

## Adding a version

Each release of this package supports one more upstream version. To add one:

1. Add the dependency to `package.json` under an `upstream-<version>` alias, so
   the exact build is pinned in the lockfile rather than resolved at run time.
2. Add an entry to `SUPPORTED` in `dump.mjs` — its tag, its alias, and every
   upstream release the state covers.
3. **Say how each of those releases is measured.** A selector covering more than
   one release makes a claim about all of them, and `fixtures_test.dart` will
   refuse a selector that carries no evidence for one it names. Two kinds:
   - `crossCheck` — releases that can be rendered. Each is rendered across the
     full matrix, both values of `title`, and compared to the one the fixture
     was taken from. Zero mismatches is the bar.
   - `bySourceTree` — releases that **cannot** be rendered by anybody. 1.8.0 and
     1.9.0 shipped npm tarballs with no JavaScript in them at all; their only
     possible evidence is that their `src/lib` git tree is a rendered one's.
4. Set `titleProp` if the release has one (1.7.0 onward). Without it the fixture
   only ever sees the prop's default, and a port ignoring the argument entirely
   would pass every assertion in the file.
5. Run `node dump.mjs <version>` and commit the fixtures.

Step 3 was added in #43 and immediately went red on the **already published**
`v1_6_1`, which claimed three releases and carried a measurement of one. See
`docs/agents/lessons.md`.

## Why two fixtures from two sources

Upstream exposes its two layers very differently, and the split is forced:

- **`utilities.json`** is imported directly from the pinned reference tree.
  `utilities.js` exports all eight functions and contains no JSX, so the real
  implementations can be called with real inputs.
- **`svg.json`** is rendered from the npm package through `react-dom/server`.
  **No component exports its generator** — `generateData` / `generateColors` are
  module-private in all six — so per-variant values are only observable as the
  attributes they end up in. Byte equality on this output stands in for a
  per-variant value fixture: every value that reaches the drawing is in there.

Because those are two independent sources, they can disagree — npm `1.8.0` and
`1.9.0` shipped no JavaScript at all. `test/fixtures_test.dart` cross-checks them
against each other rather than trusting that they match.

## Normalisation

Generated ids (`useId`, `prefix__…`) are internal references, not drawing, and
are normalised to `_`.

`<title>` is **not** normalised. 1.6.x emits it unconditionally with no prop to
suppress it, and 1.7.0 puts it behind one — a real difference between versions
that the fixtures have to carry.

## Size

The matrix renders at one size. `size` lands on the `<svg>` element's `width`
and `height` and nowhere else — measured across all 480 pairs of an earlier
full run, not assumed. `sizePassthrough` in the fixture keeps that claim
falsifiable.
