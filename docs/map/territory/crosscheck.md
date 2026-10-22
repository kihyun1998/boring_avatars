# crosscheck

## What it is
`tool/crosscheck/` renders **upstream's own React output** and this package's
SVG in the **same browser** and compares the screenshots, at a bar of **0
differing pixels**. It is the only check that renders what upstream actually
emits: the byte gate ([parity-harness](parity-harness.md)) normalises ids away
on both sides, and [calibration](calibration.md) hands Chrome *our* document by
design. It says "upstream and this port draw the same picture", never "the
picture is right". A tool, not a gate — it needs npm, a browser and a network
install, so `flutter test` never runs it. Run it when a variant lands or the
emitter changes.

## Governing decisions
**None.** No ADR. It enforces one ruling it does not own: S-1 (maintainer,
2026-07-29 — repair `sunset`'s blank render for names whose `url(#…)` is not a
valid CSS url token), recorded in
[upstream-divergences](../aggregate/upstream-divergences.md). S-2 (both sides
refuse `beam` × the empty palette) is counted here, owned there.

## Design model
From the two entry scripts' headers, checked against the code at HEAD:

- **Why the bar can be zero.** Both documents go through one browser, so the
  browser's own approximation error — circles up to 0.13 px inside true
  geometry, shallow rotated edges up to 30/255 out (hidden-state #27, see
  [calibration](calibration.md)) — applies identically to each and cancels.
  Nothing to relax when Chrome updates: it is the only bar in the project a
  browser change cannot break.
- **Why it exists — demonstrated, not argued** (attributed, theflow Step 4):
  pointing `ring`'s `<g mask="url(#…)">` at a mask that does not exist leaves
  every per-name byte test green (the group's `maskIdentifiers` assertion, added
  in #37, is what catches it there), while this harness reports **22 468
  differing pixels**. That assertion exists only because someone anticipated
  *which* identifier mattered; this catches the class without knowing.
- **Upstream is re-rendered from npm, never read from `test/fixtures/`** —
  fixture entries are stored normalised and `mask="_"` has lost its `url()`
  wrapper, so one handed to a browser renders unmasked. `emit.dart` likewise
  emits **unnormalised** SVG.
- **One source for what is compared.** `emit.dart` writes the selector into
  `ours.json` (`'selector'`, `'upstreamReleases'`, `'size'`) and
  `crosscheck.mjs` picks the upstream package from there — never passed twice.
  Same rule as the `size` check (`emitted.size !== SIZE` throws): two halves
  told separately what they compare can print a pass about nothing.
- **Which upstream release each selector is compared against is a judgement,
  not a lookup** (`UPSTREAM_FOR`): `v1_6_1` → 1.6.1; `v1_7_0` → **1.10.0**, not
  1.7.0 (the four releases differ only in the mask id, and 1.7.0 is the one the
  port already matches byte for byte — comparing it would be tautological);
  `v1_10_1` → **2.0.4** (the fixture comes from 1.10.1; 2.0.4 is npm `latest`,
  the TypeScript-era ESM build, tag-less — the covered release resting on the
  most argument and the least byte identity).
- **Builds through the package's dispatch** (`build` → `buildAvatarScene`), not
  a private copy of it — since #59; a private mapping could disagree with the
  shipped one while this printed a pass. `title: null` on our side and no
  `title` prop upstream: a picture comparison, `<title>` paints nothing.
- **Matrix**: 6 variants × 20 names × 5 palettes × `square` on/off = 1200 at
  `renderSize = 320` (4× the natural 80, so a sub-pixel geometry difference
  becomes four pixels wide). `square` is in this matrix and not in the
  fixture's main matrix — the #37 lesson applied.
- **Outcomes are counted separately, on purpose.** S-1 names are listed
  explicitly (`EXPECTED_DIVERGENCE = { sunset: {'punctuation'} }`), and the run
  **fails if such a difference disappears** — the ruled repair stopped firing.
  S-2 refusals (`refused` in `ours.json`; upstream throws too) are reported as
  "agreed refusals", **not** counted as pixel-identical: no pixels were
  compared, and a harness reporting 990 identical when 40 were two exceptions
  would claim evidence it does not have. Asymmetric refusals are failures.
- **Roster guard.** `emit.dart` lists `lib/src/variants/` and exits 1 if a
  variant gains a file without gaining a line in `portedVariants`. Fired on
  `beam` in #38 and on `marble` in #41 (attributed) — "twice now, which is the
  whole argument for keeping it". It also prints `NOT COVERED: …` for any
  upstream variant not ported (none at HEAD).
- **`report.html` is for human eyes**: upstream / ours / a live
  `mix-blend-mode: difference` panel, black = identical, differences sorted
  first. Two traps were only found by opening it, both with the numbers at 0
  while the picture disagreed: the difference stack needs an **opaque black**
  backdrop (over white two agreeing transparent renders come out white), and
  each render must be flattened onto that backdrop **before** the blend (a blend
  mode is re-interpolated by source alpha, so every antialiased rim grew a faint
  ring on byte-identical cards). A visual gate has to be looked at, the same way
  a numeric one has to be watched failing.
- **`CROSSCHECK_LIMIT=<n>`** caps the run for iterating on the harness; a capped
  run says so in the summary, in the `PASS (CAPPED — not a verification run)`
  line and in the report header.
- **Run it alone.** The #45 run's first attempt shared the machine with fixture
  regeneration and `flutter test`; Playwright timed out taking a screenshot.
  Re-run alone, everything passed (attributed, theflow Step 4).
- **Input bounds:** fixed corpus; `CROSSCHECK_LIMIT` only shrinks the run.
  Browser: the **system Chrome** via `playwright-core`
  (`chromium.launch({ channel: 'chrome' })`) — nothing downloads a browser and
  no path is hardcoded.

## Code
- `tool/crosscheck/emit.dart` — `upstreamVariants`, `portedVariants`,
  `renderSize`, `build`, `main` (roster guard, `refused`, writes `ours.json`)
- `tool/crosscheck/crosscheck.mjs` — `LIMIT` (`CROSSCHECK_LIMIT`),
  `EXPECTED_DIVERGENCE`, `UPSTREAM_FOR`, `SIZE`, the PNG decoder, `compare`,
  `buildReport`; writes `report.json`, `report.html`, `DIFF-*.svg`
- `tool/crosscheck/package.json` — `playwright-core`, `upstream-1.6.1`,
  `upstream-1.10.0`, `upstream-2.0.4`
- `tool/versions/ext-hook.mjs` — registered for the 2.0.x ESM build

## Reference behaviour
Measured runs (none re-runnable from the repo without a browser; attributed):

| Run | Selector vs upstream | Checked | Pixel-identical | Agreed refusals (S-2) | Ruled (S-1) | Unruled |
|---|---|---|---|---|---|---|
| #41, 2026-08-07 — first full roster | `v1_6_1` vs 1.6.1 | 1200 | 1150 | 40 (`beam` × empty palette, both `square`) | 10 (`sunset` × `punctuation`, both `square`, five palettes) | 0 |
| 2026-08-13 (#43's ruling) | `v1_7_0` vs 1.10.0 | 1200 | 1150 | 40 | 10 | 0 |
| #45, 2026-08-14 — the #50 sweep | each of `v1_6_1` vs 1.6.1, `v1_7_0` vs 1.10.0, `v1_10_1` vs 2.0.4 | 1200 each | 1150 each | 40 each | 10 each | 0, worst unruled delta 0/255 |

- #41: `marble`'s 200 renders all pixel-identical, including the blur, the
  `overlay` blend and the filter region — the reason
  [calibration](calibration.md)'s failure to reach ≤1/255 on `marble` is not
  evidence of a wrong picture.
- #45: the seventh combination #50 counts — `pixel`'s second colour index — is
  the `v1_10_1` run's 200 `pixel` cases, all identical to 2.0.4's own render.

## Cross-cutting invariants
- [frozen-selector-output](../invariant/frozen-selector-output.md) — the
  per-selector run is how a release re-proves the earlier selectors still draw
  what their upstream draws.
- [variant-design-size](../invariant/variant-design-size.md) — both documents
  carry their own `viewBox` at `width`/`height` 320, so the browser scales each
  by the variant's own side.
- [selector-coverage-copies](../invariant/selector-coverage-copies.md) —
  `UPSTREAM_FOR` and the npm aliases are a per-selector copy of the mapping.
- [byte-gates-erase-ids](../invariant/byte-gates-erase-ids.md) — the one comparison that keeps ids, rendering unnormalised documents.

## Blast radius
- [variant-dispatch](variant-dispatch.md) — `build` goes through
  `buildAvatarScene`; a dispatch change is what this compares, and a variant
  file added without a roster line stops the run.
- [svg-emission](svg-emission.md) — what is screenshot is `emitSvg`'s output
  unnormalised; an id or reference the emitter writes wrong shows up here and
  nowhere else.
- [sunset](sunset.md) — the S-1 list is keyed by corpus name id; a corpus
  rename or a widened repair changes which differences are "ruled".
- [version-selectors](version-selectors.md) — a new selector needs an
  `UPSTREAM_FOR` entry and an npm alias, chosen by the "least byte identity"
  judgement, or `crosscheck.mjs` cannot run it.
- [parity-harness](parity-harness.md) — shares `corpus.json`; a corpus change
  changes the 1200.

## Known holes / open
- **Cannot see a shared mistake**: anything both documents get wrong the same
  way.
- **Never run against 1.7.0 or 1.10.1 directly** — by the judgement above; the
  byte fixture covers them.
- **Size is one value (320).** A size-dependent picture difference at another
  scale is out of frame (bytes for other sizes are covered by
  `sizePassthrough`).
- No measured run is recorded after 2026-08-14; a run is owed whenever a
  variant or the emitter changes, and nothing schedules it.
