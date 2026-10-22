# Frozen selector output

## The fact
Once a `BoringAvatarsVersion` value has shipped on pub.dev, the layer-1 values
and the SVG bytes it produces for any input never change. The raster bytes are
**pinned, not frozen**: the goldens hold them at 0 diff, but a rasterizer
correction is allowed to move them by a deliberate golden regeneration, because
an edge pixel off by 1/255 can be fixed later at no cost to anyone. Support grows only by adding
a selector value, never by editing what a shipped one draws. Checkable:
`test/fixtures/<selector>/svg.json` and `utilities.json` are regenerated from the
real npm package on every release and must come back byte-identical, and the
goldens under `test/goldens/` must not move.

Shipped selectors are a query, not a list kept here:
`curl -s https://pub.dev/api/packages/boring_avatars` names the published
versions, and `CLAUDE.md` principle 3 maps each release to its selector.

## Why it is cross-cutting
The bytes for one selector come from several places that do not call each other
or share one source of truth:

- the JS-semantics primitives and upstream utilities (`lib/src/js/`), which turn
  a name into numbers;
- the six variant builders (`lib/src/variants/`), which turn the numbers into
  values and a scene;
- the dispatch's `_Drawing` switch in `lib/src/avatar.dart`, which decides which
  picture a selector gets;
- the scene's number and text serialisation (`jsNum`, `escapeSvgText`) and the
  emitter, which decide the bytes.

Any of them can change a shipped selector's output on its own. A rasterizer
edit is different: it can move an edge pixel by ±1/255, which is invisible and
can be fixed later at no cost. A layer-1 edit draws a *different avatar*, and
once it is published it cannot be corrected without changing the profile
picture of every user of every app that depends on the package. **The test is
reversibility, not difficulty**: a three-line `getUnit` is sacred and a
thousand-line rasterizer is not (`CLAUDE.md`, "Layer 1 is frozen on publish").

## Territories it holds in
- [js-semantics](../territory/js-semantics.md) — `jsMod`, `jsNum`, `toSigned32`, `jsSubstr`
- [upstream-utilities](../territory/upstream-utilities.md) — `jsHashCode`, `jsGetUnit`, `jsGetRandomColor`, `jsGetContrast`
- [version-selectors](../territory/version-selectors.md) — `BoringAvatarsVersion`, `_Drawing`, and `upstreamVersions`, whose literal lists `api_surface_test.dart` pins so that a shipped selector never gains or loses a release
- [variant-dispatch](../territory/variant-dispatch.md) — `buildAvatarScene`
- [marble](../territory/marble.md), [beam](../territory/beam.md), [pixel](../territory/pixel.md), [sunset](../territory/sunset.md), [ring](../territory/ring.md), [bauhaus](../territory/bauhaus.md) — each `build<Name>Scene` and its value generator
- [scene-model](../territory/scene-model.md) — `SvgAttribute`'s number formatting and escaping
- [svg-emission](../territory/svg-emission.md) — `emitSvg`
- [parity-harness](../territory/parity-harness.md) — the fixtures that prove it
- [goldens](../territory/goldens.md) — the raster half of the proof
- [release-and-publishing](../territory/release-and-publishing.md) — every release re-proves it
- [public-svg-surface](../territory/public-svg-surface.md) — the `version` argument has no default, so a caller's effective selector cannot move under them
- [crosscheck](../territory/crosscheck.md), [mutation-harness](../territory/mutation-harness.md) — further proof that the frozen output still matches upstream and that the tests guarding it can fail

**Pinned, not frozen.** These territories link here because their output is
compared byte-exactly by the goldens, not because it is sacred. A change in them
regenerates goldens deliberately and is not a completeness-pass trigger:
[scene-reading](../territory/scene-reading.md),
[path-geometry](../territory/path-geometry.md),
[transforms](../territory/transforms.md),
[coverage](../territory/coverage.md),
[compositing-and-masks](../territory/compositing-and-masks.md),
[filters](../territory/filters.md),
[colour-declarations](../territory/colour-declarations.md),
[banded-rasterisation](../territory/banded-rasterisation.md) (bands must not
move a byte), [widget-lifecycle](../territory/widget-lifecycle.md),
[example-app](../territory/example-app.md) and
[readme-gallery](../territory/readme-gallery.md) (both draw through the same
path).

## What a violation looks like
A user's avatar changes after they upgrade the package, with the `version`
argument they pinned unchanged. In the repo: a `git diff` of
`test/fixtures/<shipped selector>/` after the parity harness re-runs, or a
golden that moves. Nothing else shows it, because a browser renders either
version of the bytes as a perfectly good avatar.

## Discovery history
- The rule is the package's identity from #1: `CLAUDE.md` principle 3 and
  "Layer 1 is frozen on publish".
- The completeness pass becomes unconditional for `lib/src/js/**`,
  `lib/src/variants/**`, and any change to a published selector's layer-1
  output. That third trigger named no selector and was vacuous until `0.1.0`
  shipped `v1_6_1` on 2026-08-12. It covers every shipped selector since
  (theflow.md Step 5, retired; the pub.dev query above lists them).
  `lib/src/raster/**` and `lib/src/widget/**` fall back to the normal
  enumeration-risk judgement. The "lens" referred to is the adversarial
  completeness pass: one is bought for these paths whatever the diff looks like.
- `0.2.0` (2026-08-13) is the first release that had to *prove* the freeze
  rather than state it. While `v1_7_0` was being added, `v1_6_1`'s 600
  committed renders were regenerated from the real npm package. They came back
  byte-identical, and the golden PNGs were untouched (measured, theflow.md
  @ 0593e28).
- The rule carries over into the release plan: every release re-proves the
  additive invariant, so a user pinned to `v1_6_1` must not see an avatar move
  because `0.3.0` touched `pixel`
  ([release-and-publishing](../territory/release-and-publishing.md)).

## Where it will recur
If a change touches a file under `lib/src/js/` or `lib/src/variants/`, or
anything that formats a number or string into the SVG, or the `_Drawing`
switch, it is subject to this. Run the parity harness for **every shipped
selector**, not only the one being worked on, and read the fixture diff. A new
upstream output state becomes a new selector value and a new `_Drawing` arm,
never an edit to an existing arm.
