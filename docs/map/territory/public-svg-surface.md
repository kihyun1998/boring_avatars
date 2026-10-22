# public-svg-surface

## What it is
What a pub.dev dependent imports: the barrel `lib/boring_avatars.dart` and the
SVG entry point `boringAvatarSvg`. The barrel exports four names —
`boringAvatarSvg`, `BoringAvatar` (the widget, owned by
[widget-lifecycle](widget-lifecycle.md)), `BoringAvatarsVariant` and
`BoringAvatarsVersion` — each behind a `show`. `boringAvatarSvg` is the policy
seam: it takes every caller-owned choice (name, palette, size, version,
variant, square, title), validates the two that upstream would silently coerce
or ignore, and hands the rest to the internal dispatch and the emitter. Its
output is the byte-parity document.

## Governing decisions
No ADR. The boundary rule and four maintainer rulings, recorded here in full.

### The boundary rule (retired `theflow.md`, Step 2)
**Identity: bit-exact reproduction of `boring-avatars`, in Dart, for any
upstream version.** The package owns everything that decides *what the image
is*; the consumer owns everything that decides *how it is used*. The core is
three layers with declared seams, all inside this package — Layer 1 data,
Layer 2 scene ([scene-model](scene-model.md)), Layer 3 raster — and the
**policy** is injected, never assumed: the palette (`colors`), the upstream
`version` selector, `square`, the display size, widget layout and decoration,
caching policy, and whether the caller wants pixels or an SVG string
(`CLAUDE.md`, "The palette is the caller's").

**The consumer seam is in-repo** (`lib/src/widget/`) plus real pub.dev
dependents. The in-repo consumer reaches the core through **sibling `src/`
imports, not the barrel**: `buildAvatarScene` is deliberately unexported and
`rasterizeScene` is not exported at all, so the barrel is the surface a
*dependent* imports and not the one this package's own consumer layer uses —
the same arrangement `tool/` has (re-verified: `lib/src/widget/boring_avatar.dart`
imports `../avatar.dart`, `../raster/…`; `tool/crosscheck/emit.dart`,
`tool/readme/generate.dart` call `buildAvatarScene`). *(The rule said "through
the barrel" until #80, a route that does not exist.)*

### `version` has no default (maintainer, 2026-08-08)
Theirs to reverse. A product judgement about the API's shape, not a derivation:
a later argument that a default is friendlier does **not** reopen it.

**What they were shown**, and why the question existed: two artifacts required
opposite things. `version.dart`'s shipped doc-comment said the newest release
is *"what you get unless you ask for an older one"* — promising a default of
`latest` — while `CLAUDE.md`'s freeze invariant exists because changing a
selector's output "silently rewrites the profile picture of every user of every
app that depends on this package". A `latest` default makes the *effective*
selector move on upgrade, which is that failure by another route.

| option | what a caller gets | what it costs |
|---|---|---|
| **required** | an avatar frozen at the version they named | every call site carries a `version:` |
| `latest` | the shortest call | `0.2.0` silently drops `<title>`; `0.3.0` redraws every `pixel` avatar |
| `v1_6_1` fixed | a default that never moves | the default is the *oldest* supported release, so a caller who does not think about it gets a `pixel` that differs from today's npm |

**What they chose:** required. `latest` stays on the enum — passing it is an
explicit decision to track upstream's newest, and its doc-comment says so.
**The same reasoning governs `size`**, which is required too (below). Both are
pinned in `api_surface_test.dart` against the **source text**, since Dart
cannot be asked at runtime whether a parameter has a default — and, since #80,
against the widget's source as well: the first guard read only `avatar.dart`,
so a `BoringAvatar({… version = …})` passed the whole suite until a second
public surface existed and was measured.

### The surface is a top-level function, `boringAvatarSvg` (maintainer, 2026-08-08)
Decided from a derived recommendation — an API-shape call, presented for a
yes/no rather than grilled. `BoringAvatar` was kept free for the widget.

### S-4 — a `size` that is not a size throws (maintainer, 2026-08-08)
The ledger row is in [upstream-divergences](../aggregate/upstream-divergences.md);
the event:

**What the user was shown (2026-08-08):** the measurement below, taken from
upstream 1.6.1 through the parity harness's own installed copy, beside what
this package does for the same input.

| `size` | upstream 1.6.1 | this package |
|---|---|---|
| `80` (control) | `width="80" height="80"` | same |
| `true` / `false` / `null` | **`width` and `height` absent**, plus a React dev warning | `ArgumentError` |
| `[80]` | `width="80"` | `ArgumentError` |
| `{}` | `width="[object Object]"` | `ArgumentError` |
| `undefined` | `width="40"` (upstream's own default) | not reachable — `size` is required |

| option | what a caller gets | what it costs |
|---|---|---|
| throw | a failure naming the argument | a crash where upstream degrades — hidden-state #8's failure mode, in the direction this project had not taken before |
| reproduce the degradation | upstream's bytes for every input | implementing JS's `String()` coercion **and** React's attribute-dropping rules, to emit `width="[object Object]"` faithfully |

**What they chose:** throw — *"걍 에러 던져 그럼. 그런 상황만 아니면 똑같다는
거잖아."* Their reasoning is the divergence's scope: every input a caller can
plausibly mean — any number, any CSS length string — is byte-identical, and the
divergence is confined to values that are not sizes at all.

**Why this is not S-2, which went the other way.** There the reference itself
failed and reproducing the failure was the only thing that matched, because
upstream emitted no bytes to be identical to. Here upstream emits a perfectly
good document and we refuse it. S-2 asked "do we reproduce a crash", this asks
"do we reproduce a coercion". React prints `Received true for a non-boolean
attribute` precisely to tell the author they made a mistake — reproducing it
means reproducing a bug report.

**It is theirs to reverse.** A later argument that the port should be faithful
above all does **not** reopen it; only the user does.

**What it costs.** `boringAvatarSvg` is not byte-identical to upstream for a
`size` that is neither a `num` nor a `String` — it produces no bytes at all.
`avatar_svg_test.dart` asserts the throw *and* the argument it names, so a
guard that rejected something wider, or blamed the wrong parameter, fails.

*Detail at HEAD:* `null` never reaches the guard — `size` is a non-nullable
`Object`, so Dart rejects it at compile time; the runtime `ArgumentError`
covers `bool`, `List`, `Map`, `Symbol` and every other non-`num`, non-`String`.

## Design model
From the source and the rulings above.

- **Exactly four exports, every one with a `show`** (measured in #59, not a
  ruling). Without a `show`, a re-export added *inside* an exported library
  reaches the public surface with the barrel unchanged: an
  `export 'scene/scene.dart';` inside `version.dart` made `SvgNode`,
  `SvgAttribute`, `SvgElement` and `escapeSvgText` importable from the barrel
  with the whole suite green; with the `show` the same edit leaves `SvgNode`
  undefined. So `api_surface_test.dart` pins the exact export list *and* that
  each line has a `show`. `avatar.dart` is shown narrowly because it also holds
  `buildAvatarScene`, whose return type is the scene model — exporting it
  would ship every element, attribute and ordering rule as API.
- **`lib/src/` stays importable, and that is not a contradiction.** `tool/`
  and the tests do it deliberately. "Does not leak" means *not reachable from
  the barrel*; Dart offers nothing stronger short of moving files.
- **`size` is required, `num` or `String`, and reaches only `width`/`height`.**
  Upstream's own default is three-valued across the covered range — `size = 40`
  through 1.11.0; **no default at all from 1.11.1 to 2.0.1** (the destructuring
  omits it, so React drops `width`/`height`); `'40px'` from **2.0.2**, unchanged
  at `master` (re-verified this pass at every tag; the history was got wrong
  twice before #45 measured it — [lessons.md](../../agents/lessons.md), "The
  claim that needed measuring was the one this repo had written down (#51)").
  It stays out of the version state **only as long as `size` stays
  consumer-owned**; if the package ever renders at an implicit default, the
  covered range splits three ways on this axis
  ([version-selectors](version-selectors.md)).
- **`title` is `bool?`** (hidden-state #16): either literal default is wrong for
  one selector; `null` lets each answer as upstream does, and `title: false` at
  `v1_6_1` is an `ArgumentError` rather than a silent no-op — the same
  reasoning as S-4. The decision itself is in
  [version-selectors](version-selectors.md).
- **The palette is passed through, unvalidated**, as upstream passes it. An
  empty palette degrades in five variants and throws `ArgumentError(name:
  'colors')` in `beam` (S-2 — [beam](beam.md)). A malformed colour string is
  written into the document verbatim (rasterizer-side meaning:
  [colour-declarations](colour-declarations.md)).
- **One documented byte exception**: `sunset` with a name containing `'`, `"`,
  `(`, `)`, `\` or a control character percent-encodes the gradient reference
  so the avatar renders (S-1, [sunset](sunset.md)); the doc-comment states it.
- `boringAvatarSvg` is `emitSvg(buildAvatarScene(…))` — no logic of its own
  beyond the defaults (`variant = marble`, `square = false`, `title = null`);
  the `size` guard sits in `buildAvatarScene` because the scene's own check is
  an `assert`, compiled out of release builds.

Outside input: `name`, `colors` and a `String` `size` are caller strings with no
length bound; a numeric `size` is any `num`. Nothing here bounds them.

## Code
- `lib/boring_avatars.dart` — the four `export … show …` lines
- `lib/src/avatar.dart — boringAvatarSvg`
- `lib/src/avatar.dart — buildAvatarScene` (the `size` guard; the rest is
  [variant-dispatch](variant-dispatch.md) and [version-selectors](version-selectors.md))
- Tests: `test/api_surface_test.dart` — group `the barrel` (`exports four names
  and nothing else`, `every export carries a show clause`, `the SVG function
  takes no default version`, `and neither does the widget`);
  `test/avatar_svg_test.dart` — groups `every render upstream produced, through
  the public function`, `square reaches the public function too`, `size is
  injected policy and reaches nothing but width/height` (incl. `anything that
  is not a number or a string is rejected`), `the empty palette splits by
  variant, and the split is upstream's`; `test/title_test.dart`;
  `test/fixtures_test.dart — size is a passthrough …`, `a string size is a
  passthrough too …`.

## Reference behaviour
- `git -C /Volumes/T7/GitHub/.refs/boring-avatars show v1.6.1:src/lib/components/avatar.js`
  — `size = 40`, forwarded untyped (the S-4 site, `avatar.js:18`); `v1.11.1`
  (no size default), `v2.0.2`/`master` `index.tsx` (`size = '40px'`).
- `test/fixtures/<selector>/svg.json` → `sizePassthrough` (40, 80 × square)
  and `sizePassthroughStrings` (`100%`, `2rem`, `40px`, `80`, `a"b`).
- [fidelity.md](../../fidelity.md) §§1–3 — the caller-facing statement of the
  three things not reproduced.

## Cross-cutting invariants
- [frozen-selector-output](../invariant/frozen-selector-output.md) — this
  function's bytes per selector are the frozen contract.
- [variant-design-size](../invariant/variant-design-size.md) — `size` reaches
  only `width`/`height`; the drawing space is the variant's own viewBox.
- [selector-coverage-copies](../invariant/selector-coverage-copies.md) — the
  README's selector table describes this surface.
- [byte-gates-erase-ids](../invariant/byte-gates-erase-ids.md) — `avatar_svg_test.dart`'s own `normalise`.
- [version-required-everywhere](../invariant/version-required-everywhere.md) — `boringAvatarSvg`'s `required BoringAvatarsVersion version`.
- [sunset-url-character-list](../invariant/sunset-url-character-list.md) — `boringAvatarSvg`'s doc-comment restates the list (without `%`).

## Blast radius
- [widget-lifecycle](widget-lifecycle.md) — the second public surface; the
  version-required ruling and `show` discipline hold there too, but by a
  separate source-text guard, so a change to the policy here does not reach it.
- [release-and-publishing](release-and-publishing.md) — the export list and
  every parameter's default are published API; adding an export or a default
  is irreversible once released, and the SDK floor is carried by the same
  release.
- [version-selectors](version-selectors.md) — `version` being required is what
  makes moving `latest` safe; a default here would move every caller's avatar
  on upgrade.
- [svg-emission](svg-emission.md) — the bytes callers receive; anything this
  function adds to the scene is emitted verbatim.
- [example-app](example-app.md), [readme-gallery](readme-gallery.md) — both
  call this surface and document it; a signature change breaks them.

## Known holes / open
- **Stale doc-comments at HEAD** (found this pass): the barrel's comment says
  "the other two carry a `show`" — there are three others since the widget was
  exported; `avatar.dart`'s library doc says "the barrel exports
  [boringAvatarSvg] alone" (true only of `avatar.dart`'s exports);
  `boringAvatarSvg`'s doc says the guarantee "will cover its own rasterizer
  when that ships" — it has shipped; `buildAvatarScene`'s doc calls
  `boringAvatarSvg` "the only caller" — the widget, `tool/crosscheck` and
  `tool/readme` call it too (the widget passes every argument explicitly, so
  the doc's point still holds); `api_surface_test.dart`'s comment says "pins
  three export statements" — four.
- The widget refuses an unreadable palette with `ArgumentError` (#80's ruling)
  where `boringAvatarSvg` passes it through — a seam whose stated rationale
  ("the raster path cannot read it") #64 aged; flagged to the user, not edited
  ([widget-lifecycle](widget-lifecycle.md), [colour-declarations](colour-declarations.md)).
- No bound on `name`, `colors` or `size` (see Design model).
