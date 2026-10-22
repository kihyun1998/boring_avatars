# goldens

## What it is
The layer-3 **regression gate**: this package's rasterizer output compared
byte for byte against images committed under `test/goldens/`, on every
`flutter test`. Raw RGBA, not PNG — no encoder in the loop, so a decoder change
cannot move a golden. Bar: **0 diff, no exceptions**. Both sides are this
package's own deterministic output, so any difference is a change we made.
Distinct from [calibration](calibration.md) (against Chrome, manual).

## Governing decisions
**None.** No ADR. The split from calibration is derived (a 0-diff gate against
Chrome would deadlock on a Chrome update); see [calibration](calibration.md).

## Design model
From `test/support/golden_cases.dart`, `test/golden_contract_test.dart` and
`tool/golden/generate.dart`, re-verified at HEAD:

- **A fixture that regenerates itself is not a proof.** `generate.dart` writes;
  tests only read. Run the generator deliberately when the rasterizer changes
  and review the diff.
- **One roster, three consumers.** `goldenCases` is shared by the generator,
  each variant's raster test (`goldenCasesFor('<variant>')`, filtering by
  `<variant>-` prefix) and `golden_contract_test.dart`. They used to be three
  lists nothing compared; measured before the shared file (#39): dropping a
  stray `.rgba` into `test/goldens/` left **all 469 tests green**.
- **Roster checks, both directions** (`'the roster is the same in all three
  places'`): the directory holds exactly the declared cases; every case is
  claimed by exactly one variant prefix — a hand-kept fourth list of variant
  names, deliberately not derived, which fired on `marble` in #41; the roster
  is non-empty (else both checks are vacuous).
- **The bars are proved on synthetic images** (`'the regression bar allows
  nothing'` and siblings): a harness nobody has watched fail is not a harness.
- **What is shared is the case list, not the bytes**: each test builds and
  rasterises the scene, then compares.
- **Per-variant size**: a scene is rasterised at its own viewBox side — `ring`
  90, `beam` 36, the rest 80.
- **A golden that agrees with itself proves nothing** (#36, lessons.md): a
  golden is a regression lock on a state verified elsewhere (`sunset`'s raster
  test checks the gradient *formula* first, then "goldens lock the verified
  state"). `pixel`'s `square` had a golden but no upstream comparison until
  #37 — see [parity-harness](parity-harness.md).
- **Coverage of the roster**: 24 files at HEAD — pixel 5 (incl.
  `pixel-clara-second-index`), ring 3, sunset 4 (incl. `sunset-hangul`),
  bauhaus 4, beam 4, marble 4. No `beam` empty-palette golden: `beam` throws
  there. `pixel-clara-square` arrived only in #80 (the widget's "six variants ×
  both square states" proof had a cell it could not reach).
- **Other readers of the roster**: `raster_scale_test.dart` and
  `widget_test.dart` (the `clara-*` cases, asserted on `rasterAvatarImage`'s
  bytes — see [widget-lifecycle](widget-lifecycle.md)).

## Code
- `test/support/golden_cases.dart` — `goldenDefaultPalette`, `goldenCases`,
  `goldenCasesFor`
- `test/support/golden.dart` — `RgbaImage`, `expectGoldenIdentical`,
  `expectMatchesChromeRender`
- `test/golden_contract_test.dart` — the bar proofs and the roster group
- `tool/golden/generate.dart` — `main` (writes `test/goldens/<case>.rgba` via
  `rasterizeScene`)
- `test/{pixel,ring,sunset,bauhaus,beam,marble}_raster_test.dart` — each
  variant's golden group
- `test/goldens/*.rgba`

## Reference behaviour
**None.** Goldens compare the rasterizer to itself over time by design; the
outside opinions are [calibration](calibration.md) (Chrome) and
[crosscheck](crosscheck.md) (upstream's picture).

## Cross-cutting invariants
- [frozen-selector-output](../invariant/frozen-selector-output.md) — the raster half of the proof; goldens pin raster bytes, which are pinned rather than frozen.
- [variant-design-size](../invariant/variant-design-size.md) — each golden's
  side is its variant's viewBox side; a case at another side would not be 1:1.
- [scene-attribute-vocabulary](../invariant/scene-attribute-vocabulary.md) —
  the goldens are what catches a variant writing an attribute the rasterizer
  drops, *for the inputs in the roster*.
- [libm-transcendentals](../invariant/libm-transcendentals.md) — a golden is
  bytes from one machine's libm; a platform whose `cos`/`sin` differ in the
  last ulp could fail it with no code change. Unmeasured.
- [byte-gates-erase-ids](../invariant/byte-gates-erase-ids.md) — pixels carry no ids.

## Blast radius
- [coverage](coverage.md), [compositing-and-masks](compositing-and-masks.md),
  [filters](filters.md), [path-geometry](path-geometry.md),
  [transforms](transforms.md) — any intended pixel change in the rasterizer
  reddens goldens; regenerate deliberately and review the diff, never to clear
  a red run.
- [variants](../aggregate/variants.md) — a variant builder change that moves a
  scene moves its golden; a new variant needs its prefix in the hand-kept list.
- [readme-gallery](readme-gallery.md) — the same rasterizer draws
  `docs/images/`; a golden regeneration that moves visible pixels makes the
  gallery stale, and nothing says so.
- [widget-lifecycle](widget-lifecycle.md) — the widget bar is "as layer 3",
  read against these files.

## Known holes / open
- **Id-blind**: a golden is pixels; it says nothing about the SVG's ids (the
  #45 lens measured a port renaming ids only for a new selector passing every
  gate including goldens — attributed, theflow "The states in scope").
- **Roster-scoped**: only 24 inputs; a defect on an input no case draws is
  invisible.
- `test/support/golden.dart`'s library doc is stale: "compares … against PNGs
  committed to this repo" (they are `.rgba`) and "Nothing calls these yet"
  (six raster tests call `expectGoldenIdentical`).
- theflow Step 7's gate block comment says `flutter test` "includes fixture +
  golden PNG gates" — the goldens are raw RGBA.
