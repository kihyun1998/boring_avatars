# scene-model

## What it is
Layer 2: the backend-neutral description of what an avatar draws — a tree of
`SvgNode`s, each an `SvgElement`, an **ordered** list of `SvgAttribute`s,
children, and (for `<title>` only) text. Every variant builder produces one;
two readers consume it — [svg-emission](svg-emission.md), which serialises it
to upstream's bytes, and [scene-reading](scene-reading.md), which turns it into
pixels. The seam exists so geometry lives in **one** place: two emitters
deriving it independently is the divergence seed `CLAUDE.md` names. Internal —
deliberately not exported ([public-svg-surface](public-svg-surface.md)).

## Governing decisions
**None.** No ADR or maintainer ruling decides the model's shape; it is fixed by
`CLAUDE.md`'s three-layer identity ("the `scene` seam exists so the SVG emitter
and the rasterizer share one copy of the geometry") and by measurement of
upstream's output. [ADR-0001](../../adr/0001-what-a-colour-declaration-means.md)
sits adjacent and does not govern: it decides what a colour value in the scene
*means* to the rasterizer, not how the scene carries it.

## Design model
From the source and the fixture measurements in its doc-comment (no record).

- **Attributes are an ordered list, not named fields** (hidden-state #18). React
  emits props in the order the JSX author wrote them **at each call site**, so
  one element takes several orders across the fixture: `circle` is
  `cx cy r fill` in `ring` and `cx cy fill r transform` in `bauhaus`; `rect`
  and `path` take five or more (`rect` `x y width height rx stroke fill` for
  `beam`'s eyes, `x y width height transform fill rx` for its wrapper; `path`
  `d fill`, `fill d`, `d stroke fill stroke-linecap`). A canonical order per
  element would be silently wrong on every render whose order differs — a
  browser does not care, so only bytes catch it. The node keeps its call
  site's order; the rasterizer reads by name (`SvgNode.attribute`), so order is
  invisible to it.
- **Attribute names are stored as emitted** (hidden-state #19, attribute half).
  React hyphenates some props and not others — `maskType` → `mask-type`,
  `stopColor` → `stop-color`, but `maskUnits`, `stdDeviation` stay — and the
  split is **a list, not a rule**, so callers pass the emitted spelling and the
  translation is never re-derived. Element names keep camel case
  (`linearGradient`, `feGaussianBlur`): `SvgElement.tag` is the enum name.
- **A value is a `num` or a `String`** (an `assert`, compiled out of release —
  which is why the public seam validates `size` itself). Numbers are formatted
  at emit time by `jsNum` ([js-semantics](js-semantics.md); hidden-state #7);
  strings by `escapeSvgText`.
- **`escapeSvgText` is React's `escapeTextForBrowser`**: `&`, `>`, `<`, `"`,
  and `'` → **`&#x27;`** (not `&apos;`) — measured, `O'Brien-Smith, Jr.`
  renders as `O&#x27;Brien-Smith, Jr.` upstream. Tabs, newlines and non-ASCII
  pass through. Applied identically to attribute values and `<title>` text.
- **`SvgElement` is closed**: the fifteen elements the six variants emit,
  enumerated from the rendered fixture rather than the components (`svg`,
  `title`, `mask`, `g`, `rect`, `circle`, `line`, `path`, `defs`,
  `linearGradient`, `stop`, `filter`, `feFlood`, `feBlend`, `feGaussianBlur`).
  A new element is a compile-visible change to both readers.

Input bound: the model holds whatever a builder writes. Caller strings reach it
unbounded — the name (in `<title>`, and in `sunset`'s ids), palette entries (in
`fill`/`stop-color`), a `String` size.

## Code
- `lib/src/scene/scene.dart — SvgElement`, `SvgElement.tag`
- `lib/src/scene/scene.dart — SvgAttribute` (`name`, `value`, `formattedValue`)
- `lib/src/scene/scene.dart — SvgNode` (`element`, `attributes`, `children`,
  `text`, `attribute`)
- `lib/src/scene/scene.dart — escapeSvgText`
- Producers: the six `build*Scene` functions in `lib/src/variants/`
  ([variants](../aggregate/variants.md)); dispatcher `lib/src/avatar.dart —
  buildAvatarScene`.
- Tests: `test/svg_emitter_test.dart` — group `the traps this layer has, pinned
  individually` (`attribute order is the node's, not a canonical one`, `text
  escaping matches React, apostrophe included`, `tabs, newlines and non-ASCII
  pass through untouched`, `an element name is never hyphenated, though an
  attribute may be`), group `the scene is readable by name, so the rasterizer
  ignores order`.

## Reference behaviour
- `test/fixtures/v1_6_1/svg.json` → `renders` — what React's
  `renderToStaticMarkup` emitted at upstream 1.6.1; `svg_emitter_test.dart`
  parses every document into this model and requires it back unchanged, which
  proves the model is expressive enough to hold all of upstream's output.
- React's `escapeTextForBrowser` behaviour — measured through the fixture's
  `punctuation` corpus name.

## Cross-cutting invariants
- [scene-attribute-vocabulary](../invariant/scene-attribute-vocabulary.md) —
  what builders write into these nodes must be what `scene_raster.dart`'s
  allow-lists accept.
- [root-fill-none](../invariant/root-fill-none.md) — the root node's
  `fill="none"` is what makes an absent `fill` lower in the tree paint nothing.
- [frozen-selector-output](../invariant/frozen-selector-output.md) — every
  shipped document is this model serialised.

## Blast radius
- [svg-emission](svg-emission.md) — serialises attribute order, names and
  escaping exactly as stored; any change in what a node carries is a byte change.
- [scene-reading](scene-reading.md) — reads by name against per-element
  allow-lists; a new attribute or element a builder writes throws there
  (or, if allow-listed without being applied, draws the wrong picture silently).
- [variants](../aggregate/variants.md) — every builder writes this model and
  owns its call-site attribute order; changing a constructor's shape touches
  all six.
- [public-svg-surface](public-svg-surface.md) — the model must stay off the
  barrel; a stray re-export publishes every element and ordering rule.

## Known holes / open
- Nothing rejects a duplicate attribute name on one node: `attribute` returns
  the first, while the emitter writes both — the two readers would disagree.
  No builder does this today.
- The `num | String` check is an `assert`; in a release build a builder that
  stored another type would fail inside `formattedValue` as a cast.
