# marble

## What it is

The `marble` variant: upstream's default (an unknown `variant` degrades to it from
v1.3.0 on), drawn as a full-canvas background rect and two literal blob paths,
each blurred by one shared `<filter>`, the second also blended with
`mix-blend-mode: overlay`. It is the only one of the six that reaches for a
filter or a blend mode, so it is the variant that brought the offscreen-layer
machinery into the rasterizer. Its builder is part of the sacred surface: what it
writes is what every user's `marble` avatar looks like.

## Governing decisions

**S-3: reproduce the scale slip** (maintainer, 2026-08-07). It is recorded here as an
event and listed in the [upstream-divergences](../aggregate/upstream-divergences.md)
ledger.

- **Upstream:** `avatar-marble.js:56` @ v1.6.1, unchanged as `avatar-marble.tsx:59` @
  v2.0.0, v2.0.2 and `master` (= npm 2.0.3/2.0.4). Re-read in the pinned tree.
- **What it does:** the first path takes its colour, translation and rotation from
  `properties[1]` and its **scale from `properties[2]`**. The five neighbouring
  reads all say `[1]`, so it looks like a copy-paste slip.
- **What the user was shown:** the five lines of `avatar-marble.js` side by side
  (`properties[1]` for the colour, the two translations and the rotation, then
  `properties[2]` for the scale). The measurement that 11 of the 20 corpus names
  take different values. The derivation that puts it at 3 in 4 for *any* name.
  And **a rendered page**: every corpus name drawn twice, upstream's version
  beside the "corrected" one, with a live difference panel where black means
  identical.
- **The derivation is what made the number safe to act on.** A count over 20
  names is a fact about those 20 names. Here `getUnit(2h, 4)` is `2h mod 4`,
  which is 0 for even `h` and 2 for odd `h`, so element 1's scale is 1.2 or 1.4
  and nothing else, for every name that will ever exist. Element 2's `3h mod 4`
  cycles through all four values. The two differ whenever `h` is odd, and again
  when `h ≡ 2 (mod 4)`: 1/2 + 1/4. A synthetic sweep of two million hashes gave
  exactly 1,500,000 (maintainer batch, 2026-08-07). The in-repo test
  re-derives it over 4,000 hashes → 3,000 (re-verified, `marble_parity_test.dart`).

  | option | what a caller gets | what it costs |
  |---|---|---|
  | reproduce it | upstream's avatar, byte for byte | the port carries a copy-paste slip |
  | correct it | an avatar nobody has ever seen | 3 names in 4 change identity; a divergence row; `tool/crosscheck` reports 110 ruled cases against a bar of **0** pixels; permanent divergence from every upstream version, 2.0.4 included |

- **What they chose:** reproduce it: *"그대로 재현으로 가자."*
- **Why this is not S-1** ([sunset](sunset.md)): S-1 repaired `sunset` because
  upstream's own output was **a blank avatar**, a defect the user could see. Here
  both versions are perfectly good avatars, and the only argument for changing
  anything is a guess about the author's *intent*. "Fix the bug" does not carry
  over from one case to the other. The two rulings going opposite ways is the
  ledger working as intended, not a contradiction.
- **It is theirs to reverse.** This is a product judgement about fidelity versus
  intent. A later argument that the slip is obviously unintended does **not**
  reopen it. Only the user does.
- **What it costs.** Nothing at layer 2: the fixture *is* upstream's output, so
  reproducing the slip is what makes the 100 renders byte-identical. The cost is
  that `marble.dart` has to carry an explanation, and `marble_parity_test.dart`
  has to pin the odd read directly. Otherwise the next reader "fixes" it, and
  the byte sweep tells them they broke something without telling them why.

Adjacent, not governing: [ADR-0001](../../adr/0001-what-a-colour-declaration-means.md)
decides what an absent `fill` paints. It does not decide what `marble` writes.
`CLAUDE.md`'s "Layer 1 is frozen on publish" makes this file sacred, but it is
an identity statement, not a decision about `marble`.

## Design model

From the source and its doc-comments, plus the dated measurements below.

- **Three elements are generated, and all three are read, but not evenly.**
  Element 0 contributes a colour (the background) and nothing else. Its
  translation, rotation and scale are computed and never used. Element 1 places
  the first blob, and element 2 places the second. **Both** blobs are scaled by
  `properties[2].scale` (S-3 above). The split is visible at the call site:
  `_placement(placement, scaleFrom)` takes the two elements as separate
  parameters.
- **`scale` lands exactly on its literal.** `1.2 + getUnit(n, 4) / 10` takes four
  values, and each is bit-identical to the double `1.2`, `1.3`, `1.4` or `1.5`
  (measured in Node and in Dart; pinned by `marble_parity_test.dart`, "the sum
  lands exactly on the literal"). So no `1.3000000000000003` can be emitted.
  This holds **as long as the range stays `SIZE / 20`**.
- **`rotate` can be negative.** `getUnit(…, 360, 1)` passes an index, so it can
  negate, giving -359 to 359. `scale` passes no index, so it never negates.
- **The two blobs share a filter reference, not a filter.** One
  `<filter id="prefix__filter0_f">` sits in `<defs>`, and each path is blurred
  independently with its own filter region. The chain is `feFlood` (opacity 0),
  then `feBlend` (SourceGraphic over it), then `feGaussianBlur stdDeviation=7`.
  The first two are no-ops, and the rasterizer *checks* that they are rather
  than assuming it. Mechanism: [filters](filters.md).
- **`style="mix-blend-mode:overlay"` is React's object prop serialised.** It is the
  only inline style in the package, and it sits on the second path only.
- **`color-interpolation-filters="sRGB"` is declared.** The SVG default
  (`linearRGB`) is refused by the rasterizer rather than implemented.
- **The filter region has no `x/y/width/height`, so it takes the spec's
  -10%/120% defaults.** Under `userSpaceOnUse` these resolve against the
  viewport to `(-8, -8, 96, 96)`, and then sit in the *referencing element's*
  space, so the blob's own `transform` moves, scales and rotates the region
  (hidden-state #11; mechanism in [filters](filters.md)). The variant-specific
  half: the region is **live only for `square: true`**. With the disc mask, the
  region cuts nothing the mask has not already cut (pinned by "marble's own region
  does not cut anything", round mask only). Under `square`, Chrome clipped
  `marble-clara-square` by 23 pixels where the port, still reading the region in
  viewport space, clipped none. That was the measurement that found the
  inconsistency (#41, 2026-08-07). The `marble-clara-square` golden now pins the
  region's `y`/`height`. `x`/`width` land off-canvas for every real name, so a
  constructed translate pins them ("each of the four default percentages is
  pinned").
- **The blur sigma is in the element's user space.** `stdDeviation="7"` under
  `scale(1.2)` is 8.4 device pixels, and under 1.3 it is 9.1. Taking the 7
  literally measured 27/255 against Chrome, and scaling it measured 1/255 (#41,
  2026-08-07). The roster puts the three-box approximation's odd branch
  (Clara, d=17) and even branch (empty name / Alice, d=16) on opposite sides of
  the goldens.
- **The offscreen layer is bigger than the canvas.** Once `scale(1.3)` applies,
  the second blob reaches x ≈ 89 on an 80-wide target, and a blur of sigma 8.4
  pulls that back about 25 px into view. Rasterising only `[0, width)` would
  quietly get the edge wrong. Mechanism: [compositing-and-masks](compositing-and-masks.md).
- **An empty palette draws nothing.** All three `fill`s are dropped, and nothing
  falls back to black. That is safe only because of the root `fill="none"`
  (hidden-state #8; see [variants](../aggregate/variants.md)). There is
  deliberately no empty-palette golden, because freezing a blank as correct is
  the failure #40 found in [sunset](sunset.md). The blank is asserted as
  behaviour instead.

Hidden-state rows, variant half only (each row's mechanism lives in the linked
raster territory):

| Row | What `marble` writes | Live / inert here | How it was established |
|---|---|---|---|
| #11 filter region | no region attributes, `userSpaceOnUse` | live under `square` only | Chrome, #41 (2026-08-07) |
| #23 rounding per shape | a filtered shape → one float layer, composited once | the layer rounds once, not per shape; the remaining interior disagreements with Chrome are exactly 1/255 on ≤ 5 of 6400 pixels | Chrome, #41 |
| #24 abutting shapes | full-canvas background + two blurred blobs | inert: every pair overlaps or is disjoint, and two arbitrarily rotated polygons share no edge | #41 |
| #28 F.6.5 negative radicand | `M L H v h l z`, no arc | inert, for a stronger reason than `ring`/`beam`: no arcs at all | 18 distinct `d` strings over 600 renders, #41 |
| #33 mask per group | background rect under shapes crossing the mask edge | live | theflow.md row #33 (no `marble`-specific test; see Known holes) |
| #34 `z` mid-path | both `d`s end in `z` | inert | 600 renders, #41 |
| #42 calibration interior | a blur: every pixel differs from its neighbour | `_isEdge` files 100% of `marble` as edge, so "interior 0" means *nothing to classify*, never agreement; the only interior mismatches come where `overlay` saturates flat (Alice's black/white palette) | #41; [calibration](calibration.md) |
| #45 transform order | `translate rotate scale` on both paths | live (one of three variants with a `transform`; all 100 non-empty `marble` renders carry one, re-verified) | fixture count |

## Code

- `lib/src/variants/marble.dart`: `MarbleElement`, `marbleProperties`,
  `_placement`, `buildMarbleScene`, `_blobA` / `_blobB` (the literal `d`
  strings), `_size` (80), `_elements` (3)
- `lib/src/avatar.dart`: `buildAvatarScene` dispatches `marble` with no
  per-drawing knob. The same builder serves all three selectors.
- `test/marble_parity_test.dart`: the byte sweep, the identifier groups, "both
  paths are scaled by properties[2], not by their own element" (the S-3 pin), "the
  five generated numbers that reach no attribute", "an empty palette degrades"
- `test/marble_raster_test.dart`: the three-box blur, sigma in element space,
  the oversize layer, overlay, the filter region, refusals, and the goldens
- `test/support/golden_cases.dart`: `marble-clara-default`, `marble-alice-pair`,
  `marble-empty-name`, `marble-clara-square`
- `tool/mutate/cases/41-marble.json`: mutation patterns typed against
  `marble.dart`'s text

## Reference behaviour

- Pinned upstream: `../.refs/boring-avatars` @ v1.6.1
  `src/lib/components/avatar-marble.js`, and @ v2.0.x `avatar-marble.tsx`. The
  S-3 line is still present at `master`.
- Fixtures: [`test/fixtures/v1_6_1/svg.json`](../../../test/fixtures/v1_6_1/svg.json)
  (100 renders + square), and the `v1_7_0` / `v1_10_1` fixtures through the
  [version-selectors](version-selectors.md) sweeps.
- The filter id is the literal `prefix__filter0_f` through 1.10.1. It is derived
  from `useId()` from 1.10.2 on, and the mask id from 1.8.0 on. These are not
  reproducible by anyone ([`docs/fidelity.md`](../../fidelity.md), "The three
  things that are not reproduced", item 3). The port emits the literals at every
  selector.
- [`docs/fidelity.md`](../../fidelity.md), "Upstream's own bugs are reproduced,
  not corrected": the user-facing statement of S-3.

## Cross-cutting invariants

- [frozen-selector-output](../invariant/frozen-selector-output.md): `marble.dart` is sacred surface
- [variant-design-size](../invariant/variant-design-size.md): 80
- [scene-attribute-vocabulary](../invariant/scene-attribute-vocabulary.md): `filter`, `style`, the filter primitives' attributes, `color-interpolation-filters`
- [root-fill-none](../invariant/root-fill-none.md): the empty palette's three dropped fills
- [libm-transcendentals](../invariant/libm-transcendentals.md): `rotate(…)` with a nonzero angle, and the rounded mask's arcs
- [byte-gates-erase-ids](../invariant/byte-gates-erase-ids.md) — the `prefix__filter0_f` id is normalised away and asserted raw only on `v1_10_1`.

## Blast radius

- [filters](filters.md): the chain is validated as a whole and reduced to one
  sigma. A change to the primitives, their attributes or their order is refused
  there, not drawn.
- [compositing-and-masks](compositing-and-masks.md): the oversize float layer and
  the `overlay` blend both assume the shapes stay within the reach they were
  sized for. A larger scale or translate range pulls more off-canvas ink back
  into view.
- [transforms](transforms.md): `scale` and the `rotate(a cx cy)` expansion are
  parsed back from the string this builder writes. A new function (`matrix`,
  `skew`) throws there.
- [scene-reading](scene-reading.md): every attribute written here must be on an
  allow-list, or the render throws `UnsupportedSceneError`.
- [goldens](goldens.md): four committed images freeze this builder's output.
- [parity-harness](parity-harness.md): the fixtures normalise `id`/`url(#…)`.
  The literal-id claim stands on the identifier groups, not on the byte sweep.
- [crosscheck](crosscheck.md): reproducing S-3 is what keeps `marble` at a
  0-pixel bar. "Fixing" it would put 3 names in 4 into the ruled column.
- [calibration](calibration.md): its interior statistic is vacuous for a blurred
  variant, so a regression here does not show there.
- [mutation-harness](mutation-harness.md): `41-marble.json` patterns match this
  file's text. An edit that moves a matched line turns a kill into `NO MATCH`.
- [variant-dispatch](variant-dispatch.md): `marble` is the degrade target for an
  unknown variant name, including the S-5 prototype-key strings.
- [readme-gallery](readme-gallery.md): the gallery draws through this builder.

## Known holes / open

- **Hidden-state #33 is called live for `marble`** (the background and a blob
  both reach the mask edge), but no test measures it on `marble`. The pin is
  `bauhaus_raster_test.dart`'s constructed case, plus the 0-pixel crosscheck.
- **A stale test comment.** `marble_raster_test.dart`, "clips the output — a
  region that cuts really does cut", says the region is "inert for `marble`:
  its region is (-8, -8, 96, 96) and the mask is 0…80". That is the
  viewport-space reading #41 corrected. Under `square` the transformed region
  does cut, which is why `marble-clara-square` pins `y`/`height`.
- **`marble.dart`'s library doc points at "the divergence ledger in
  `docs/agents/theflow.md`"**. That pointer dangles once theflow.md is deleted.
  The ledger is now [upstream-divergences](../aggregate/upstream-divergences.md).
- **The scale literal claim holds only for the `SIZE / 20` range.** A future
  upstream that widened it would need the bit patterns re-measured.
