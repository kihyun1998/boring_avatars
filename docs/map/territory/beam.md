# beam

## What it is

The `beam` variant is a face on a rotated, scaled, rounded card, drawn on a
**36-unit** canvas: a background rect, a card `<rect>` with a
`translate rotate scale` transform, and a `<g transform>` holding a mouth (a
stroked cubic or a filled arc) and two eye rects. It is the variant that brought
`scale`, group transforms, strokes on a path, round caps and the first F.6.6
radius correction that actually fires. It is also the only one of the six that
**throws** on an empty palette, which ruling S-2 keeps.

## Governing decisions

**S-2 — reproduce the failure, as a Dart-idiomatic exception** (maintainer,
2026-08-06). It is recorded here as an event and listed in the
[upstream-divergences](../aggregate/upstream-divergences.md) ledger.

- **Upstream:** `avatar-beam.js:9,17` and `utilities.js:42` @ v1.6.1. Re-read
  in the pinned tree, the same chain stands at `avatar-beam.tsx:18` and
  `utilities.ts:42` @ v2.0.x. The `v1_7_0` and `v1_10_1` fixtures each record
  the 20 empty-palette `beam` renders as `{"__throws":"TypeError"}`, so all three
  selectors carry the throw (re-verified).
- **What it does:** with an empty palette, `getRandomColor` returns `undefined`,
  and `getContrast` then calls `.slice(0, 1)` on it. That is a `TypeError`, and
  no document is produced at all. `beam` is the only one of the six that does
  this; the other five drop an attribute and render. Measured: 20 of 20 names
  throw, against 0 of 100 for the rest (hidden-state #8).
- **What the user was shown (2026-08-06):** the failing upstream chain
  (`getRandomColor(hash, [], 0)` → `colors[NaN]` → `undefined` →
  `getContrast(undefined)` → `.slice` → `TypeError`). They were also shown the
  measurement that it is 20 of 20 names for `beam` and 0 of 100 for the other
  five, and the fixture entry `{"__throws": "TypeError"}` that records it. And
  they were shown **three** options, with what each costs:

  | option | what a caller gets | what it costs |
  |---|---|---|
  | throw, as an ordinary Dart exception | a failure naming the palette | the exception *type* differs from a JS `TypeError` |
  | throw, imitating upstream's message | a failure quoting `.slice` | worse for a Dart caller, and the cause is hidden |
  | degrade like the other five | a **fully transparent** 36×36 image | requires inventing a face colour upstream never produces |

  The artifact had to show the third row rather than assert it. Degrading does
  not give "an avatar without a card". It gives *nothing at all*: `getContrast`
  has no defined answer for `undefined`, so the face colour has no degraded
  value, and dropping the attribute leaves the eyes and mouth unpainted too. And
  because upstream emits **no bytes** for this input, "byte-identical" means
  nothing here either way. Every non-throwing output diverges by construction,
  and throwing is the only thing that matches.
- **What they chose:** throw, as a Dart-idiomatic exception:
  `ArgumentError.value(colors, 'colors', …)`.
- **It is theirs to reverse.** This is a product judgement about an API's
  shape, not a derivation. A later argument that the port should degrade for
  robustness does **not** reopen it. Only the user does.
- **What it costs.** A caller who passes `colors: []` gets an exception from
  `beam` and an image from the other five. That asymmetry is upstream's, and it
  is recorded in hidden-state #8. `beam_parity_test.dart` asserts both halves:
  the throw for the empty palette (its message must name the palette), and a
  normal render for a one-colour palette. A guard that rejected every short
  palette would therefore not pass.
- **Why S-4 went the other way** (throwing on a non-size `size`, where upstream
  degrades): upstream itself failed here, so reproducing the failure was the
  only thing that matched. S-4 asked "do we reproduce a coercion". This asked
  "do we reproduce a crash". See
  [upstream-divergences](../aggregate/upstream-divergences.md).

Adjacent, not governing: [ADR-0001](../../adr/0001-what-a-colour-declaration-means.md).
It decides that `fill="none"` and `stroke="none"` are SVG's own "no paint"
keyword, which `beam` is the variant to write.

## Design model

From the source and its doc-comments, plus dated measurements.

- **Its drawing space is 36** (`avatar-beam.js:4`, `const SIZE = 36`, re-read at
  v1.6.1 and at v2.0.x line 5). `size` reaches only `width`/`height`. The
  goldens are rasterised at 36, and one rasterised at 80 would be a different
  picture that still looked plausible. Hidden-state #26 said "the other five are
  80" until #38 measured it (2026-08-06). The fact had sat in the source line and
  in all 80 non-throwing fixture renders the whole time.
  War story: [`lessons.md` — "A row nobody can act on yet is a row nobody checks (#38)"](../../agents/lessons.md#a-row-nobody-can-act-on-yet-is-a-row-nobody-checks-38).
- **Two fields are corrected conditionally, and the correction does not mirror
  the test.** `preTranslateX < 5 ? preTranslateX + SIZE / 9 : preTranslateX`
  nudges small values up by 4. The face follows the card only above
  `SIZE / 6` (= 6), and then by *half* as much. Below that threshold it takes an
  unrelated `getUnit` with different ranges (8, 7) and digit indices.
  `SIZE / 9`, `/ 6` and `/ 12` are exactly 4, 6 and 3 in float64, so the
  integer arithmetic matches. Pinned at the boundary no corpus name reaches
  ("the two ternary thresholds").
- **`wrapperScale` is a float division**: `1 + getUnit(n, 3) / 10` gives 1, 1.1
  or 1.2. Integer division would give 1 for every name.
- **`backgroundColor`'s `!` is safe by derivation.** The empty-palette guard is
  the only way `range` can be 0, and `jsMod` of a non-negative `hashCode` stays in
  bounds. It is safe for as long as `hashCode` stays `Math.abs`'d.
- **The mouth is two different elements.** Open, it is a stroked cubic
  (`d stroke fill stroke-linecap`, with `fill="none"` and
  `stroke-linecap="round"`, no `stroke-width` so §11.4's initial 1 applies).
  Closed, it is a filled arc (`d fill`). The two share no attributes.
- **The eyes are ellipses.** `1.5 × 2` with `rx="1"`, each eye written with
  `stroke="none"`.
- **Attribute order is the call site's** (hidden-state #18). The card writes
  `x y width height transform fill rx`, and the eyes write
  `x y width height rx stroke fill`. Both are `<rect>`.

Hidden-state rows, variant half only (mechanisms in the linked raster
territories):

| Row | What `beam` writes | Live / inert here | How it was established |
|---|---|---|---|
| #8 empty palette | `getContrast(undefined)` | **throws**: `ArgumentError`, per S-2 | 20/20 names, v1.6.1 fixture |
| #10 F.6.6 radius correction | closed mouth `a1,0.75 0 0,0 10,0` | **live: the first input in the package that fires it.** λ = 25, so both radii scale ×5 to 5 and 3.75, and the filled half-ellipse is **29.45** where an uncorrected one would be **1.18**. The two are a factor of 25 apart, so no tolerance can confuse them. Every arc `ring` writes has λ exactly 1. | `beam_raster_test.dart`, "a closed mouth adds the arc F.6.6 had to correct" — [path-geometry](path-geometry.md) |
| #21 `rx`/`ry` clamp | eyes `1.5 × 2`, `rx="1"` | **live since #38.** `ry` takes 1 too, then `rx` clamps to 0.75 and `ry` stays 1. Each is exactly half its own side, so the straight edges vanish. Two ellipses come to 4.712 px², two clamped circles would be 3.534, and two plain rects 6.0, so arithmetic decides it. The *mask* half of the row stays inert. | "the three readings of the eye are far apart" — [path-geometry](path-geometry.md) |
| #24 abutting shapes | background, card on it, face on the card | inert, contrary to #24's prediction before #38. Every pair overlaps or is disjoint. | #38 |
| #28 F.6.5 negative radicand | closed mouth runs `(13, y)`–`(23, y)` | inert: a horizontal chord gives a radicand of exactly zero, even after F.6.6 scales the radii | #38 |
| #30 container attributes | `<g transform>` around the face | live. `_collectShapes` composes `parent · own`, and the mask's child rect has its own allow-list. | #38 — [scene-reading](scene-reading.md) |
| #31 `none` as a third state | `<path fill="none">` on 44 of 80 non-throwing renders, `<rect stroke="none">` 160 times | live. Before #69, `none` was only *accidentally* right. | fixture count, re-verified |
| #33 mask per group | background and card both reach the mask edge | live. The crosscheck's 0-pixel bar over 160 `beam` cases would fail on a per-shape reading. | #38 — [compositing-and-masks](compositing-and-masks.md) |
| #45 transform order | card `translate rotate scale`; group `translate rotate` | live: all 80 non-throwing renders carry a transform (re-verified). #38 extended the row one level out, so an ancestor `<g>` composes as `parent · own`. Pinned by a case where the two orders differ *on canvas* (the obvious construction put the reversed order off-canvas, where it could not fail). | "a group transform composes with the element's, in that order" — [transforms](transforms.md) |
| #47 stroke "paint nothing" cases | an open-mouth cubic with a round cap | the round-cap / zero-length half became reachable through the `c` command `beam` introduced (§11.4's own example is `M 40,40 c 0,0 0,0 0,0`). `beam`'s real mouth `c2 1 4 1 6 0` is never zero-length. | #38 — [path-geometry](path-geometry.md) |

- **A stroke outline is round-joined, not mitered.** That matches a browser
  stroking the true curve. Mitering the flattened chords would land 1.7e-5 user
  units away at `beam`'s mouth, four orders below the coverage bar.
  Mechanism: [path-geometry](path-geometry.md).

## Code

- `lib/src/variants/beam.dart`: `BeamProperties`, `beamProperties` (holds the
  S-2 `ArgumentError`), `_wrapperTransform`, `_faceTransform`, `buildBeamScene`,
  `_eye`, `_size` (36)
- `lib/src/avatar.dart`: `buildAvatarScene` dispatches `beam` with no
  per-drawing knob. `boringAvatarSvg`'s doc states the throw.
- `test/beam_parity_test.dart`: the byte sweep ("exactly one palette of the five
  is the throwing one"), "the drawing space is 36", the ternary thresholds,
  branch coverage, "an empty palette fails, and only for beam"
- `test/beam_raster_test.dart`: `scale` parsing, shape areas, the mouth and eye
  arithmetic, group-transform composition, refusals (rect stroke that would
  paint, an unknown `stroke-linecap`, attributes on the mask's rect), goldens
  ("and they are rasterised at 36, not 80")
- `test/support/golden_cases.dart`: `beam-clara-default` (open mouth, rx 6,
  scale 1.2), `beam-alice-default` (closed mouth, circle card, 1.1),
  `beam-empty-name` (identity transforms), `beam-clara-square`. There is
  deliberately no empty-palette golden.

## Reference behaviour

- Pinned upstream: `../.refs/boring-avatars` @ v1.6.1
  `src/lib/components/avatar-beam.js` + `src/lib/utilities.js`, and @ v2.0.x
  `.tsx` / `utilities.ts`.
- Fixtures: [`test/fixtures/v1_6_1/svg.json`](../../../test/fixtures/v1_6_1/svg.json):
  100 `beam` renders, of which 20 are `{"__throws":"TypeError"}`.
- [crosscheck](crosscheck.md): 40 renders per selector run where both sides
  produce no document (`beam` × empty palette), per
  [`docs/fidelity.md`](../../fidelity.md).

## Cross-cutting invariants

- [frozen-selector-output](../invariant/frozen-selector-output.md): `beam.dart` is sacred surface, and the throw is part of the contract
- [variant-design-size](../invariant/variant-design-size.md): **36**, the smallest of the six
- [scene-attribute-vocabulary](../invariant/scene-attribute-vocabulary.md): `stroke`, `stroke-linecap`, `<g transform>`, `fill="none"`, `stroke="none"`
- [root-fill-none](../invariant/root-fill-none.md): written here too, but `beam`'s empty palette throws before it could matter
- [libm-transcendentals](../invariant/libm-transcendentals.md): two rotations, the mouth arc, round caps and joins

## Blast radius

- [path-geometry](path-geometry.md): the F.6.6 correction, the stroked cubic, round
  caps and the §9.2 `rx`/`ry` clamp were all built for and first fired by this
  builder. A different mouth or eye shape lands on that arithmetic.
- [transforms](transforms.md): `scale` and the nested `<g>` composition order. A
  new function or a deeper nesting is parsed there.
- [scene-reading](scene-reading.md): a `<rect>` stroke that would paint is refused
  there (only `stroke="none"` is accepted on a rect), and `<g>` attributes are
  allow-listed.
- [colour-declarations](colour-declarations.md): `fill="none"` and `stroke="none"`
  have to stay the "no paint" state, not "unreadable".
- [upstream-utilities](upstream-utilities.md): `jsGetContrast` takes the card
  colour. Its behaviour on a non-hex palette entry decides the face colour.
- [goldens](goldens.md): four images at 36×36. Generating at any other size
  silently changes the reference.
- [crosscheck](crosscheck.md): the 40 both-empty cases depend on the throw. A
  degrade here would turn them into unexplained differences.
- [widget-lifecycle](widget-lifecycle.md): the widget has to surface `beam`'s
  `ArgumentError` for an empty palette rather than show a blank.
- [readme-gallery](readme-gallery.md): the gallery draws through this builder.

## Known holes / open

- **`bauhaus_raster_test.dart`'s "an absent stroke-width throws — the default
  arrives with beam" has a wrong comment.** It names "`beam`'s stroked
  `<rect>`" as the element that omits `stroke-width`. `beam`'s rects all carry
  `stroke="none"`. The stroked element that omits `stroke-width` is the
  open-mouth `<path>`.
- **The exception type is a Dart decision, not upstream's.** A caller catching a
  JS-style `TypeError` would miss it. This was accepted under S-2.
