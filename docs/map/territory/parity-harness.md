# parity-harness

## What it is
`tool/parity/` generates the committed fixtures under `test/fixtures/<selector>/`
that pin this package to the real `boring-avatars`: `utilities.json` (layer 1,
the eight utility functions called from the pinned reference tree's git tag) and
`svg.json` (layer 2, every corpus render produced by the real npm package through
`react-dom/server`, plus the per-prop sections and the selector's group proof).
It is a **tool, not a gate**: `flutter test` reads the committed fixtures and
never runs Node, so the suite stays hermetic and a parity change surfaces as a
reviewable `git diff` of a fixture rather than as a silently different
expectation. The harness is permanent — every output state must stay
reproducible on demand.

## Governing decisions
**None.** No ADR governs the harness. The rules it keeps come from maintainer
rulings recorded as events: the fixture-per-output-state ruling (maintainer,
2026-07-29 — carried in [release-and-publishing](release-and-publishing.md),
"Release plan") and the output-grouping ruling that decides which releases a
selector claims (carried in [version-grouping](version-grouping.md)).

## Design model
From the harness's own header and README, checked against the code at HEAD:

- **Two fixtures from two sources, because upstream exposes its layers
  differently.** `utilities.js` exports all eight functions and contains no JSX,
  so `utilities.json` calls the real implementations imported from the git tag
  (`loadUtilities` checks the tag out of the pinned tree). No component exports
  its generator (`generateData` / `generateColors` are module-private in all
  six), so per-variant values are observable only as SVG attributes — byte
  equality on `svg.json` stands in for a per-variant value fixture. The two
  sources can disagree (npm `1.8.0`/`1.9.0` ship no JavaScript), so
  `test/fixtures_test.dart` cross-checks them against each other
  (`'the two fixtures agree, though they come from different sources'`:
  marble's background fill against `colors[hash % range]`).
- **Bar: byte-identical, after normalisation.** `normalise` replaces generated
  ids (`id="…"`, `url(#…)`, `mask="…"`) with `_` on both sides. **`<title>` is
  not normalised** — 1.6.x emits it unconditionally, 1.7.0 gates it behind a
  prop (hidden-state #16; see [version-selectors](version-selectors.md)).
- **A normalisation is a hole in the gate and needs its own assertion beside
  it.** Two of `svg.json`'s sections exist only because the byte sweep erases
  ids on both sides: `maskIdentifiers` (#37 — each variant's raw mask id and
  reference; mutating `mask__ring` → `mask__pixel` or the group's reference to a
  dangling one left the whole suite green before it) and `derivedIdentifiers`
  (#40 — every raw id per name, because `sunset`'s gradient ids are derived from
  the **name** and a wrong whitespace strip would pass the whole sweep). At
  1.6.1 every id is a literal in the JSX, so the exclusion buys nothing there.
- **Every consumer-facing prop needs its own renders, or it is inference — and
  the unit is "the prop varies on a path something else varies on too".** The
  main matrix runs at one `size` (`MATRIX_SIZE = 80`) and `square: false`.
  - `squareRenders` (#37): six variants × two names (`upstream-default`,
    `emoji-zwj`) × five palettes = 60. Until #37 `pixel` shipped with `square`
    asserted only against itself and a golden committed for it.
  - `sizePassthrough`: `<variant>|<name>|<size>|<sq|rd>` — 48 entries at HEAD.
    History (attributed, theflow Step 4): it held `marble` alone from #33 to
    #59; #59 measured that hardcoding `size: 80` on the `ring`, `beam`,
    `pixel`, `sunset` or `bauhaus` arm left **all 677 tests green**; widening it
    per variant with one name/palette/`square` still hid an arm that honoured
    `size` only for one name or dropped it under `square`, so it now varies
    with name and `square` too.
  - `sizePassthroughStrings` (30 entries): the `String` half of `size`'s public
    type (`num | String` since #59), which `corpus.sizes` (a list of ints)
    structurally cannot record. `fixtures_test.dart`
    (`'a string size is a passthrough too, and no \d+ strip sees it'`) **reads**
    the emitted attribute rather than rebuilding it, because React escapes an
    unrecognised value (`a"b` → `a&quot;b`) and a rebuilt expectation would be
    asserting its own copy of the escaper.
  - `titleRenders` (120, `v1_7_0` and `v1_10_1` only): both sides of the
    `title` prop; without it a port ignoring the argument passes everything
    (README step 4).
- **A selector covering several releases must carry evidence for each one**
  (`groupProof`, #43). `SUPPORTED[...]` names `crossCheck` (renderable releases,
  rendered across the full matrix and both `title` values, compared to the
  fixture's release — zero mismatches is the bar) and `bySourceTree`
  (releases nobody can render: their `src/lib` git tree equals a rendered
  one's). `countJsFilesOnNpm` re-runs the "1.8.0 → 0, 1.9.0 → 0, 1.10.0 → 1 JS
  file" measurement that README, CHANGELOG and `version.dart` state;
  `idsByPosition` records `useId`'s position-dependence; `filterIdOf` /
  `maskIdOf` record raw ids. The join between git and npm evidence is checked
  through npm's recorded `gitHead` (1.7.0 → `2f2ac13`, 1.10.0 → `378c2cd`;
  tags are annotated, so only `^{commit}` compares). `fixtures_test.dart`
  (`'a version covering more than one release proves it did'`) refuses a
  selector that names a release without evidence; written for the four-release
  `v1_7_0`, it went red on the already-published `v1_6_1` (backfilled in #43).
- **Refusing is recorded, not crashed on.** An empty palette makes upstream
  `beam` throw; the fixture stores only the constructor name (`__throws`),
  because the message comes from minified internals.
- **Deterministic output.** `stableStringify` sorts keys; running twice must
  produce byte-identical files ("if it does not, that is a bug in the harness").
- **Input bounds:** the corpus (`test/fixtures/corpus.json`: 20 names, 5
  palettes, sizes `[40, 80]`) is fixed and committed; the harness takes one
  argument, a selector name from `SUPPORTED`. Nothing external is unbounded.

## Code
- `tool/parity/dump.mjs` — `SUPPORTED`, `VARIANTS`, `normalise`,
  `stableStringify`, `loadUtilities`, `dumpUtilities`, `MATRIX_SIZE`, `dumpSvg`,
  `dumpGroupProof`, `filterIdOf`, `countJsFilesOnNpm`, `idsByPosition`,
  `maskIdOf`
- `tool/parity/package.json` — one `upstream-<version>` alias per **rendered**
  release: 12 at HEAD (1.6.1, 1.7.0, 1.10.0, 1.10.1, 1.10.2, 1.11.1, 1.11.2,
  2.0.0–2.0.4)
- `tool/parity/probe-title-1-6-1.mjs` — the 1.6.1 `<title>` probe
- `tool/parity/README.md` — setup (sparse clone of the reference tree, **no
  `--depth 1`**: it is checked out by tag), the "adding a version" checklist
- `tool/versions/ext-hook.mjs` — registered by `dump.mjs` so the extension-less
  2.0.x ESM build loads as published (owned by
  [version-grouping](version-grouping.md))
- `test/fixtures/corpus.json`, `test/fixtures/{v1_6_1,v1_7_0,v1_10_1}/{utilities,svg}.json`
- `test/fixtures_test.dart` — the guards on the fixtures themselves (groups
  `corpus` and `fixtures for <selector>`)

## Reference behaviour
- Pinned upstream tree `../.refs/boring-avatars` (`src/lib`, all tags) —
  `utilities.js` at each selector's tag is what `utilities.json` records.
- npm `boring-avatars@<version>` packages, pinned in
  `tool/parity/package-lock.json` — what `svg.json` records.
- "`size` lands on `width`/`height` only": measured across all 480 pairs of an
  earlier full run (`dump.mjs` comment above `MATRIX_SIZE`); `sizePassthrough`
  keeps it falsifiable.

## Cross-cutting invariants
- [frozen-selector-output](../invariant/frozen-selector-output.md) — a fixture
  is the recorded output of a shipped selector; regenerating one that moves is
  the visible form of a violation.
- [selector-coverage-copies](../invariant/selector-coverage-copies.md) —
  `SUPPORTED[...].releases` and the per-state npm aliases are one copy of the
  release → selector → upstream-versions mapping.
- [byte-gates-erase-ids](../invariant/byte-gates-erase-ids.md) — `dump.mjs`'s `normalise` and the raw id sections beside it.

## Blast radius
- [version-selectors](version-selectors.md) — `upstreamReleases` in each fixture
  must equal `BoringAvatarsVersion.upstreamVersions`; a release added to one and
  not the other reddens `fixtures_test.dart`.
- [svg-emission](svg-emission.md) — the parity tests compare the emitter's bytes
  to `svg.json` through the same normalisation; a change to what `normalise`
  erases changes what "byte-identical" means there.
- [variants](../aggregate/variants.md) — every variant's parity test reads these
  fixtures; a corpus change re-baselines all six at once.
- [crosscheck](crosscheck.md) — it reads `corpus.json` and shares the
  `ext-hook` loader; a corpus change changes its 1200-render count.
- [goldens](goldens.md) — a green fixture says nothing about pixels; a layer-2
  change that moves bytes but keeps fixtures green still owes a golden review.

## Known holes / open
- **Corpus-only evidence.** Every claim is over 20 names × 5 palettes; a JS
  semantics difference that no corpus input reaches is invisible (the
  hidden-state list is the hypothesis that picks the inputs).
- `idsByPosition` records `useId`'s position-dependence; it shows "reproduce
  1.8.0 byte-for-byte" is not satisfiable by anything, including 1.8.0. The
  ruling on what to emit instead is in
  [upstream-divergences](../aggregate/upstream-divergences.md) /
  [version-selectors](version-selectors.md).
- theflow's parity-harness paragraph says the harness installs "the real
  upstream package pinned to the tag being ported" and that it "installs one
  upstream per state"; at HEAD it installs every **renderable** covered release
  (12), because `groupProof` renders each one.
