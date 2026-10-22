# calibration

## What it is
`tool/calibrate/` is the layer-3 **parity calibration**: this package's
rasterizer against a real headless-Chrome render of the **same SVG document**
(our emitter's output). It is the outside opinion on the pixels, run
**manually** when the rasterizer changes — not per commit, and not by
`flutter test`. The regression gate for pixels is [goldens](goldens.md); this
is the comparison that says how far those pixels are from what a browser draws,
scoped to what each of its statistics can actually measure.

## Governing decisions
**None.** No ADR. The bar is governed by a maintainer-directed event recorded
below ("The calibration bar, re-scoped"). Adjacent:
[ADR-0001](../../adr/0001-what-a-colour-declaration-means.md) decides what a
colour declaration means — the `-named`/`-invalid`/`-colour4`/`-translucent`
cases exercise it end to end but the ADR governs the parser, not this harness.

## Design model
**Why the raster gate is split.** A 0-diff gate against Chrome fails when
*Chrome* updates while our code is untouched — and the house rule forbids
lowering a threshold to clear a red build, so it would deadlock. The committed
golden is deterministic and stays 0-diff forever; the Chrome comparison proves
upstream parity and is run deliberately (`render.mjs` header).

**Chrome is fed our document** (`compare.dart` first pass writes `scenes.json`
from `emitSvg`). A harness that rebuilt the SVG independently could pass while
the two backends disagreed about what to draw. Consequence: anything wrong in
our *document* is invisible here — that is [crosscheck](crosscheck.md)'s job.

**Compare premultiplied** (hidden-state #29). Both buffers store straight
alpha, so a pixel we cover 3/255 carries the full undiluted colour while
Chrome's uncovered pixel carries zero: a 3/255 disagreement reads as a delta of
**240** straight. The same trap bites any self-comparison — #23's drift
measured 16 straight, 2 premultiplied (attributed).

**Interior vs edge — `_isEdge`.** A pixel is "edge" when its 3×3 neighbourhood
in Chrome's render is not uniform. A good proxy for antialiasing on flat fills;
**defeated** (hidden-state #42) by:
- a gradient — every `sunset` gradient pixel is edge, so its interior count is
  vacuous (interior empty, not agreeing);
- any shape thinner than three pixels — deleting `bauhaus`'s stroked `<line>`
  outright leaves interior mismatches at **0** on all three of its cases (#39,
  reproduced); worst edge moves 71 → 174–255, but with a baseline of 71 no
  threshold separates a missing shape from Chrome's own error;
- a blur — `_isEdge` files 100% of `marble` as edge; its only interior pixels
  are where `overlay` saturates a region flat, an accident of the palette.
`flutter test` killed every wrong picture tried through this harness; the
Chrome run killed none (#37, #39 — attributed). Read interior 0 as "the solid
regions agree", never "the picture is right".

**The seam counters** (#83, hidden-state #24's shape). Where two abutting tiles
differ in colour, Chrome's 3×3 is non-uniform whatever it does at the seam, so
the pixel is edge and its delta hides beside the mask's 71. `compare.dart`
counts **"opaque in Chrome, translucent here"** (`seams`) directly, lists the
first 12 by position, and prints partial-pixel counts on **both** sides
(`partialOurs`, `partialTheirs`) — a zero seam count means either "the seam
exists and Chrome conflates identically" or "there is no seam", and only the
second pair separates them.

**Device scale.** Every row above `pixel-clara-100` rendered at the variant's
own viewBox side — the one target where hidden-state #24 is inert (scale
exactly 1, `pixel`'s tiles on pixel boundaries, no two shapes meeting inside a
pixel). Rendering at another side costs nothing structural because `size`
reaches `width`/`height` only; both sides still receive the same document. 100
is the number hidden-state #24 nominated; 210 is an 80-logical avatar at the
2.625 ratio #58's derivation names.

**The bar — three parts** (implemented in `compare.dart` `main`; the FAIL path
was watched firing before it was recorded — attributed):
1. every interior residue ≤ **1/255** (today's residues are the
   compositing-rounding class, #23/#29);
2. the curve-free control `_controlCase = 'pixel-clara-square-100'` has **0**
   seams and worst edge ≤ **3/255** — 3 is that case's measured value kept as a
   regression tripwire, not a derived constant;
3. everything on a curve or shallow edge is **reported, ungated**, with
   hidden-state #27 as the named reason.
Tightening is always legitimate; loosening any of the three is a new ruling.

**Input bounds:** a fixed in-code case list (`_cases`, 26 entries); one
argument, the work directory.

## Code
- `tool/calibrate/compare.dart` — `_cases`, `_default`, `_named`, `_invalid`,
  `_colour4`, `_translucent`, `main` (two passes: writes `scenes.json`, then
  compares; seam and partial counters; the three-part bar; exit 1 on FAIL),
  `_controlCase`, `_isEdge`
- `tool/calibrate/render.mjs` — `CHROME` (resolved per platform:
  `darwin`/`win32`/else `google-chrome`, `CHROME` env overrides — the
  hardcoded Windows path stranded the first macOS run at #45), `decodePng`;
  drives Chrome `--headless --force-device-scale-factor=1
  --default-background-color=00000000` through an HTML wrapper with zero
  margins, writes `<case>.rgba`
- `test/support/golden.dart` — `expectMatchesChromeRender` (see Known holes)

## Reference behaviour
Hidden-state rows carried here (measured; the rows themselves lived in
theflow's hidden-state list):

- **#27 — Chrome's curves are inset, its shallow straight edges outset.**
  `<circle r=20>` loses 1.69 px² (0.0135 px inward), `r=23` 11.95 (0.083 px),
  `r=40` 32.03 (0.127 px); a `<path>` half-disc r=38 loses 17.32 (0.145 px). An
  axis-aligned `<rect>` is exact at integer edges and within 0.003 px at
  fractional ones; a **rotated** one errs outward: against exact coverage
  (Sutherland–Hodgman clip + shoelace) Chrome overstates a 4°-from-horizontal
  edge by **30.6/255** and a 22° one by 19, exact at 0° (#39). Ours is within
  **0.03/255** of exact on every shape `bauhaus` draws. So the old ≤1/255 edge
  bar measured the reference's error on a curve. The exact-coverage fact itself
  is [coverage](coverage.md)'s; the disc-area check in `raster_path_test.dart`
  is what established Chrome is the less accurate of the two.
- **#41 — Chrome dithers a gradient but does not approximate it.** Within
  0.987 of exact sRGB interpolation, varying across x; an exact interpolation
  rounded to nearest lands ≤1/255 from Chrome across all 4548 `sunset`
  gradient pixels (58.6% exact, 41.4% off by one). The bar is *met* for
  gradients, where for a curve it cannot be — one threshold was measuring two
  unrelated things. (Also in `_isEdge`'s doc-comment.)
- **Blur**: SVG 1.1 §15.17 specifies the three-box algorithm exactly; on a step
  edge our kernel and Chrome's agree to **0–1/255** for sigma 3–12; above ~12
  Chrome stops following it (31/255 at sigma 20, 65 at 30 — Skia downsamples);
  `marble`'s sigma is 8.4–9.1 device px. (`compare.dart` comment also records
  0/255 at sigma 56 measured separately — the two numbers disagree; see Known
  holes.)

**The calibration table** (premultiplied; "Last run" is the issue whose run
produced the row — attributed, none re-runnable without Chrome):

| Case | Interior mismatches | Worst edge delta | Last run |
|---|---|---|---|
| `pixel-clara-default` | **0** | 71/255 | #39 |
| `ring-clara-default` | **0** | 66/255 | #39 |
| `ring-alice-pair` | **0** | 101/255 | #39 |
| `ring-clara-square` | **0** | 66/255 | #39 |
| `sunset-clara-default` | **0** | 71/255 | #39 |
| `sunset-empty-palette` | **0** | 71/255 | #39 |
| `bauhaus-clara-default` | **0** | 71/255 | #39 |
| `bauhaus-alice-pair` | **0** | 71/255 | #39 |
| `bauhaus-empty-name` | **0** | 71/255 | #39 |
| `marble-empty-name` | **0** | 71/255 | #41 |
| `marble-clara-default` | 2 | 71/255 | #41 |
| `marble-alice-pair` | 5 | 71/255 | #41 |
| `marble-clara-square` | 2 | **9/255** | #41 |
| `pixel-clara-second-index` | **0** | 71/255 | #45 |
| `pixel-clara-100` | 0 | 53/255 | #83 |
| `pixel-clara-square-100` | **0** | **3/255** | #83 |
| `pixel-clara-210` | 0 | 63/255 | #83 |
| `ring-clara-101` | 0 | 52/255 | #83 |
| `bauhaus-translucent` | 417, **all 1/255** | 71/255 | #62 |
| `sunset-translucent` | **0** | 52/255 | #62 |
| `bauhaus-named` | **0** | 71/255 | #63 |
| `sunset-named` | **0** | 71/255 | #63 |
| `bauhaus-invalid` | **0** | 71/255 | #64 |
| `sunset-invalid` | **0** | 71/255 | #64 |
| `bauhaus-colour4` | **0** | 71/255 | #95 |
| `sunset-colour4` | **0** | 71/255 | #95 |

The table's 26 rows are exactly `_cases`' 26 keys at HEAD (re-verified).

- **`bauhaus-translucent` is why bar 1 is "≤1/255" and not "zero count".** Its
  417 residues are all exactly 1/255, the alpha channel agrees at every one, so
  the alpha product is not wrong. The likely mechanism — we store straight
  alpha and divide back out per shape while a browser composites premultiplied
  — is **inferred from the shape of the disagreement, not measured**; a
  candidate, not a finding. `sunset-translucent` at interior 0 is the contrast:
  its colour arrives through a gradient sampled once per pixel, not composited
  in layers. The interior column gained a **worst delta** in #62: 417 pixels
  out by 1 and 417 out by 40 are different findings.
- **`pixel-clara-square-100` carries #24's ruling.** The only curve-free case:
  **784 partial pixels on each side, zero** seams, worst edge **3/255** (#83).
  The ruling itself is [coverage](coverage.md)'s / [pixel](pixel.md)'s.
- **`marble`'s rows read differently.** Its interior mismatches (2–5 of 6400)
  are all 1/255 and appear only where `overlay` saturates flat. `marble-clara-square`'s
  9/255 against everyone's 71 identifies the 71 — same value, same pixel (71, 15),
  on five other rows — as **the mask's own corner curve**, not the drawing;
  dropping the radius removes it. It read **5/255 before the filter region was
  corrected**, and that smaller number was the clip being absent; a hard
  pixel-centre clip gave 11, antialiasing the boundary with the shared
  integrator gave 9; Chrome's own clip on that render moves 23 pixels by up to
  6. A calibration number going *down* is not evidence until you know the
  capability was running. (Filter-region mechanics: [filters](filters.md).)
- **Interior 0 holds for every solid region**, which proves arc sweep
  directions, paint order and the nine-slot colour map; edge deltas are all on
  curves or shallow rotated straight edges.
- **`bauhaus` split by boundary.** `bauhaus-empty-name` (hash 0, every
  transform the identity) has **zero** disagreement outside the two curves; the
  rotated cases disagree only on shallow straight edges, where ours is within
  0.03/255 of exact coverage and Chrome up to 30.6 away. Ours is the correct
  one.

### The calibration bar, re-scoped — the settlement, as an event
**Directed by the maintainer on 2026-08-11** (*"1번 판정 정리하고 pana
돌려보자"*), **settled as a derivation** from measurements already recorded —
so it falls to a better derivation; the *direction to settle* was theirs. A
later argument against the numbers reopens the derivation on its merits; only
the maintainer reopens whether the bar should have been re-scoped at all.

- **What it replaced:** "interior 0, edge ≤1/255", written in #33 and **never
  met by any run that ever existed** (first executed #37) — so no regression can
  hide under changing it, which is what the never-lower-a-threshold rule
  protects.
- **What it rests on:** unmeetable in principle for half the shapes (#27 —
  on a curve the bar measured Chrome's error); every statistic that *can* be
  exact was already at its floor (gradients ≤1/255 #41, blur 0–1/255, every
  interior residue exactly 1/255, the #83 control seams 0 / edge 3/255); and
  twice-measured (#37, #39) the gate role was never here.
- **What it costs:** curves and shallow edges carry no gated number at all; a
  regression that only moves curved edges is caught by [goldens](goldens.md),
  not here.

## Cross-cutting invariants
- [variant-design-size](../invariant/variant-design-size.md) — the cases render
  at each variant's viewBox side (80, `ring` 90) unless a case names another;
  device scale 1 is what hid #24 until #83.
- [scene-attribute-vocabulary](../invariant/scene-attribute-vocabulary.md) — the
  colour cases feed Chrome and `rasterizeScene` the same attributes; a value
  the emitter writes that the rasterizer's allow-list ignores shows here as a
  missing shape.
- [libm-transcendentals](../invariant/libm-transcendentals.md) — every recorded
  row was measured on one machine per run; nothing here measures cross-platform
  byte identity.

## Blast radius
- [coverage](coverage.md) — the edge and seam statistics are measurements of the
  coverage integrator; a coverage change moves bar 2's tripwire first.
- [compositing-and-masks](compositing-and-masks.md) — bar 1's 1/255 residues
  are the compositing-rounding class; a change to straight-vs-premultiplied
  storage is what would move them.
- [filters](filters.md) — `marble`'s rows depend on the blur and filter region;
  the "number went down" trap lives there.
- [colour-declarations](colour-declarations.md) — the `-translucent`, `-named`,
  `-invalid`, `-colour4` cases are that territory's end-to-end evidence.
- [goldens](goldens.md) — the split: if calibration ever became per-commit, the
  deadlock above returns.

## Known holes / open
- **`beam` is absent from `_cases`** — `compare.dart` imports no `beam`
  builder, and no row above names it. Its pixels are compared to a browser only
  through [crosscheck](crosscheck.md) (picture parity with upstream), never
  against Chrome's raster directly. Not recorded as a decision anywhere found.
- **`bauhaus-translucent`'s mechanism** — straight-alpha division vs
  premultiplied compositing — is inferred, not measured.
- **Blur at large sigma**: theflow records 31/255 at sigma 20 and 65 at sigma
  30 (Skia downsampling); a `compare.dart` comment above `marble-empty-name`
  records "0/255 at sigma 56 device px". The two cannot both describe the same
  Chrome; unresolved.
- **A partial reference set exits 0 with no verdict** (`missing > 0` →
  `return`): the first pass and a run with some `.rgba` files missing look the
  same to a script reading the exit status.
- **`expectMatchesChromeRender` in `test/support/golden.dart` encodes the
  superseded bar** ("interior exact, edges within one level", `edgeTolerance =
  1`) and is called only by `golden_contract_test.dart`'s synthetic images;
  the real calibration bar lives in `compare.dart`. Its library doc still says
  "Nothing calls these yet" and "PNGs committed to this repo" (goldens are raw
  `.rgba`).
- Every recorded row is one machine's run (Windows or macOS, per issue); no row
  says which.
