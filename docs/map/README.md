# Territory map

<!-- grill-map build stamp: 024bd2d -->
<!-- grill-map synced at: 0593e28 (2026-10-06) -->

The territory map. A comment's why, trap and measured value go to a note here.
Notes are added as they come up, or all at once with `grill-map`, which also
reads hand-written notes as leads and keeps their paths.

## The two questions

- **If I touch this, what else moves?** Open the territory note for the code
  you are changing and walk its `## Blast radius`. Then open every invariant
  under its `## Cross-cutting invariants`: an invariant lists the other sites
  that hold the same fact without calling each other.
- **What decision is this shape derived from?** Read `## Governing decisions`
  in the territory note. A maintainer's ruling there is an *event*: what they
  were shown, what they chose, their words, the cost, and that it is theirs to
  reverse. A later argument does not reopen it; only the maintainer does.

## How to read it

- `## Blast radius` is a checklist. An edge with nothing to do for your change
  is a correct outcome.
- A `**None.**` is itself the answer: no record governs, nothing was compared,
  nothing is known open.
- Every claim carries its evidence (a symbol, a test, an ADR, a commit) or its
  source and date, e.g. `(maintainer, 2026-07-29)` or `(measured #41,
  2026-08-07)`. A claim citing `theflow.md @ 0593e28` came from the retired
  bindings file and can be read there in git history.
- Conventions: identical section headings in every note, symbols not line
  numbers, plain relative links, a fact linked rather than restated.
- **What it cannot answer:** source files, tests, issues and tools are text
  inside notes, not nodes. To find which note covers a file, search the folder
  for the file name.

## Scope, and what absence means

This map covers everything in `lib/`, the proof tooling under `tool/` and
`test/`, `example/`, the upstream watcher, and how a release is made. A
territory appears when something in the repo commits to it: code, a decision
record, or a tool. An area with no note has nothing behind it yet.

Out of scope, by ruling rather than omission: upstream releases before 1.6.1,
npm-only versions, and `1.11.0`
([version-selectors](territory/version-selectors.md)). Per-incident war stories
live in [`docs/agents/lessons.md`](../agents/lessons.md), and notes link to
them rather than copying them.

## What the orientation found

`boring_avatars` reproduces the npm package's avatar from a name, in three
layers with declared seams:
1. **name → numbers**: [js-semantics](territory/js-semantics.md),
   [upstream-utilities](territory/upstream-utilities.md), the six variants;
2. **numbers → a scene**: [scene-model](territory/scene-model.md),
   serialised by [svg-emission](territory/svg-emission.md);
3. **scene → pixels**: the rasterizer territories.

On top of these sit two public surfaces,
[public-svg-surface](territory/public-svg-surface.md) and the widget
([widget-lifecycle](territory/widget-lifecycle.md),
[pixel-placement](territory/pixel-placement.md)). Three selectors cover nine
in-scope upstream releases ([version-selectors](territory/version-selectors.md)).

The tooling is as large as the library. It exists because "bit-exact" is a
claim about measurement, and every measurement is kept re-runnable
([aggregate/proof-harnesses](aggregate/proof-harnesses.md)).

**The largest gaps.**
- The widget's asynchronous half ships unproven by ruling: four behaviours have
  no test ([widget-lifecycle](territory/widget-lifecycle.md)).
- The byte-identity promise has never been measured across two platforms
  ([invariant/libm-transcendentals](invariant/libm-transcendentals.md)).
- Two defects were found while writing this map and are unreachable from any
  variant today:
  - the gradient extrapolates below its first stop instead of padding
    ([compositing-and-masks](territory/compositing-and-masks.md));
  - a dead branch in `strokePathOutline`
    ([path-geometry](territory/path-geometry.md)).
- No GitHub issue is open; the backlog lives in the notes'
  `## Known holes / open`.

## Territories

Layer 1 and the public seam
- [js-semantics](territory/js-semantics.md)
- [upstream-utilities](territory/upstream-utilities.md)
- [variant-dispatch](territory/variant-dispatch.md)
- [version-selectors](territory/version-selectors.md)
- [public-svg-surface](territory/public-svg-surface.md)

The variants ([aggregate/variants](aggregate/variants.md))
- [marble](territory/marble.md)
- [beam](territory/beam.md)
- [pixel](territory/pixel.md)
- [sunset](territory/sunset.md)
- [ring](territory/ring.md)
- [bauhaus](territory/bauhaus.md)

Layer 2: scene and SVG
- [scene-model](territory/scene-model.md)
- [svg-emission](territory/svg-emission.md)

Layer 3: the rasterizer
- [scene-reading](territory/scene-reading.md)
- [path-geometry](territory/path-geometry.md)
- [transforms](territory/transforms.md)
- [coverage](territory/coverage.md)
- [compositing-and-masks](territory/compositing-and-masks.md)
- [filters](territory/filters.md)
- [colour-declarations](territory/colour-declarations.md)
- [banded-rasterisation](territory/banded-rasterisation.md)

The widget
- [widget-lifecycle](territory/widget-lifecycle.md)
- [pixel-placement](territory/pixel-placement.md)

Proof, release and the quiet areas ([aggregate/proof-harnesses](aggregate/proof-harnesses.md))
- [parity-harness](territory/parity-harness.md)
- [crosscheck](territory/crosscheck.md)
- [calibration](territory/calibration.md)
- [goldens](territory/goldens.md)
- [mutation-harness](territory/mutation-harness.md)
- [version-grouping](territory/version-grouping.md)
- [upstream-watch](territory/upstream-watch.md)
- [release-and-publishing](territory/release-and-publishing.md)
- [gates](territory/gates.md)
- [example-app](territory/example-app.md)
- [readme-gallery](territory/readme-gallery.md)
- [milestones-sync](territory/milestones-sync.md)

## Aggregates

- [variants](aggregate/variants.md)
- [upstream-divergences](aggregate/upstream-divergences.md): the S-1…S-5 ledger
- [proof-harnesses](aggregate/proof-harnesses.md)

## Cross-cutting invariants

- [frozen-selector-output](invariant/frozen-selector-output.md)
- [variant-design-size](invariant/variant-design-size.md)
- [scene-attribute-vocabulary](invariant/scene-attribute-vocabulary.md)
- [root-fill-none](invariant/root-fill-none.md)
- [libm-transcendentals](invariant/libm-transcendentals.md)
- [selector-coverage-copies](invariant/selector-coverage-copies.md)
- [physical-pixel-rounding](invariant/physical-pixel-rounding.md)
- [byte-gates-erase-ids](invariant/byte-gates-erase-ids.md)
- [version-required-everywhere](invariant/version-required-everywhere.md)
- [sunset-url-character-list](invariant/sunset-url-character-list.md)
- [construction-time-length-scaling](invariant/construction-time-length-scaling.md)
