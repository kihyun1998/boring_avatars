# Aggregate — proof harnesses

**This note owns no detail.** Five ways this package proves it matches the
reference, one per layer and question, each with its own bar.

| Concept | Note |
|---|---|
| Layer 1 values and layer 2 bytes, recorded from the real upstream into committed fixtures | [parity-harness](../territory/parity-harness.md) |
| Layer 2 *picture*: upstream's own document vs ours through one browser, bar 0 px | [crosscheck](../territory/crosscheck.md) |
| Layer 3 against a real Chrome raster, a three-part scoped bar | [calibration](../territory/calibration.md) |
| Layer 3 regression: our raster vs committed raw RGBA, 0 diff | [goldens](../territory/goldens.md) |
| Whether the tests behind all of the above can fail | [mutation-harness](../territory/mutation-harness.md) |

## Why they sit together
Each one covers a hole the others leave by construction, and none of them knows
the others exist: the byte gate normalises ids on both sides; calibration feeds
Chrome *our* document; goldens compare the rasterizer only to itself; the
browser picture cannot see a shared mistake; and none of the four can say
whether its own assertions can go red — that is the mutation harness's question.

## Proof method per layer — which layer, what bar, gate or tool

| Layer | Real proof | Bar | Run by |
|---|---|---|---|
| 1 data — utilities | `tool/parity` calls the real `utilities.js` from the pinned tag → `test/fixtures/<sel>/utilities.json` | exact, no tolerance | **gate** (fixture read by `flutter test`); generation is a tool |
| 1 data — per-variant values | **not directly observable** — no component exports its generator; proved transitively through layer 2, where every value reaching the drawing is an attribute | via layer 2 | — |
| 2 scene — bytes | our SVG vs `svg.json` rendered from the real npm package via `react-dom/server` | byte-identical, excluding generated ids; `<title>` **not** excluded; ids asserted raw in `maskIdentifiers` / `derivedIdentifiers` | **gate** (fixture); generation is a tool |
| 2 scene — picture | `tool/crosscheck`: upstream's React output and ours in one Chrome | **0 differing pixels** | tool — npm, browser, network |
| 3 raster — regression | our rasterizer vs `test/goldens/*.rgba` | 0 diff, no exceptions | **gate**, every `flutter test` |
| 3 raster — parity calibration | our rasterizer vs headless Chrome on the same document | interior ≤1/255; curve-free control seam-exact, edge ≤3/255; curves/shallow edges reported ungated (settled 2026-08-11) | tool — manual, when the rasterizer changes |
| widget | `ui.Image` bytes from `rasterAvatarImage` inside `runAsync`, **not** through `pumpWidget`, against the goldens | as layer 3 | **gate** ([widget-lifecycle](../territory/widget-lifecycle.md) owns why `pumpWidget` was measured shut) |
| test trust | literal mutants; `killed`/`SURVIVED`/`NO MATCH`/`NO TESTS`/`BASELINE RED` | every mutant killed | `--check` is a **gate**; the run is a tool |

Only the committed artefacts — fixtures and goldens — are read by `flutter
test`; every harness that needs Node, a browser or the network is a tool, which
keeps the gate hermetic and makes a parity change a reviewable `git diff`.

## Traps shared by all five
- **A fixture that regenerates itself is not a proof.** Harnesses write;
  tests only read. A run that can rewrite the expectation it just failed
  against is tautological.
- **The two fixtures come from two different sources and can disagree.**
  `utilities.json` from the git tag, `svg.json` from npm — and npm
  `1.8.0`/`1.9.0` shipped no JavaScript. `fixtures_test.dart` cross-checks them
  (marble's background fill against `colors[hash % range]`).
- **A measurement can point at the wrong element.** The first `<rect>` in a
  marble render is the *mask's*, not the background — reading it made 71 of 80
  cross-checks look like failures until the probe was corrected. When a check
  fails wholesale, suspect the check.
- **Antialiasing coverage cannot be self-checked** — comparing our rasterizer
  to our own supersampled reference measures our arithmetic twice. Chrome is an
  outside opinion, **but for curves the weaker one**: a disc's area is πr²
  whoever computes it, so summing coverage over a flattened circle
  (`raster_path_test.dart`) is an outside opinion needing no browser, and it
  established that Chrome is the less accurate of the two (hidden-state #27).
- **A straight-alpha comparison misreads itself** (hidden-state #29): the same
  pixel differs by 3 or by 240 depending on representation. Premultiply first.
- **A green data-layer test says nothing about pixels**, and vice versa. Each
  seam needs its own fixture; layer 1 passing while layer 2 drifts yields a
  correct-numbers, wrong-picture avatar.
- **A normalisation is a hole in the gate** and needs its own assertion beside
  it ([parity-harness](../territory/parity-harness.md)).
- **A tool that silently covers less reads as coverage**: crosscheck names
  uncovered variants and capped runs; calibration's interior 0 can mean "nothing
  to classify"; `--check` clean is not "mutants die".
