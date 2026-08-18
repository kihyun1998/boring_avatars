# boring_avatars

A bit-exact Dart port of
[boring-avatars](https://github.com/boringdesigners/boring-avatars).

Given the same name, palette and variant, this package produces the avatar the
npm package produces — the same numbers, the same SVG, the same bytes. Two
deliberate exceptions are documented under [Where it differs on purpose](#where-it-differs-on-purpose).

Every supported upstream release is reachable at once — npm needs a downgrade to
render an older version's avatar, here it is a parameter. As of `0.3.0` every
release in scope has a selector, up to upstream's newest; later releases of this
package add selector values and never change one.

## Install

```bash
flutter pub add boring_avatars
```

## Usage

```dart
import 'package:boring_avatars/boring_avatars.dart';

final svg = boringAvatarSvg(
  name: 'Clara Barton',
  colors: const ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'],
  size: 80,
  version: BoringAvatarsVersion.v1_6_1,
  variant: BoringAvatarsVariant.beam,
);
```

That returns an `<svg>…</svg>` string. Six variants are available —
`marble` (the default), `beam`, `pixel`, `sunset`, `ring` and `bauhaus` — plus
upstream's two deprecated names, `geometric` and `abstractStyle`, which resolve
to `beam` and `bauhaus` exactly as upstream resolves them.

Everything is yours to inject. The package assumes no palette, no size and no
upstream release:

| Argument | |
|---|---|
| `name` | the only input the drawing comes from |
| `colors` | your palette |
| `size` | a `num` for `width="80"`, or a `String` for `'100%'`. Lands on the `<svg>` element's `width` and `height` and reaches nothing else |
| `version` | which upstream release to reproduce. **Required** — see below |
| `variant` | the style, defaulting to `marble` as upstream does |
| `square` | drops the mask's corner radius |
| `title` | whether the document carries a `<title>` — see below. Nullable, because the versions disagree about the default |

### `title` means different things at different versions

`<title>` is the accessible name a screen reader announces for the SVG.
Upstream 1.6.x renders it **always** and offers no prop to stop it; 1.7.0 added
the prop and **defaults it off**. This package defaults with each of them, which
is why the argument is `bool?` rather than `bool` — either literal default
would be wrong for one of the two selectors.

```dart
boringAvatarSvg(…, version: BoringAvatarsVersion.v1_6_1);              // has <title>
boringAvatarSvg(…, version: BoringAvatarsVersion.v1_7_0);              // has none
boringAvatarSvg(…, version: BoringAvatarsVersion.v1_7_0, title: true); // has <title>
boringAvatarSvg(…, version: BoringAvatarsVersion.v1_6_1, title: false); // ArgumentError
```

That last line throws rather than quietly doing nothing. Upstream would ignore
it — an unknown prop reaches a component that never reads it — and leave you
believing the element was gone.

With `title: true`, `v1_7_0` and `v1_6_1` render **byte-identical** documents.
That is the entire difference between the two selectors.

`BoringAvatar`, the widget, has no `title` parameter: it produces pixels, and
`<title>` is not drawn. Use Flutter's own `Semantics` to announce an avatar.

## Supported upstream releases

| Selector | Reproduces upstream | What it changes |
|---|---|---|
| `BoringAvatarsVersion.v1_6_1` | `1.6.1`, `1.6.2`, `1.6.3` | — |
| `BoringAvatarsVersion.v1_7_0` | `1.7.0`, `1.8.0`, `1.9.0`, `1.10.0` | `<title>` becomes optional, and defaults **off** |
| `BoringAvatarsVersion.v1_10_1` | `1.10.1`, `1.10.2`, `1.11.1`, `1.11.2`, `2.0.0`, `2.0.1`, `2.0.2`, `2.0.3`, `2.0.4` | `pixel`'s colour index moves — every `pixel` avatar redraws |

That list was completed in `0.3.0` and is unchanged in `0.3.1` — upstream's
newest release included.
**Later releases of this package add selector values; they never change one.**
A shipped selector's output is frozen — an avatar you render today renders
identically on every future version of this package — so support grows by
addition only.

**`1.11.0` is the one hole in that list, and it is deliberate.** It sits
between two supported releases, so it deserves its own sentence: 1.11.0 spreads
the component's own props onto the `<svg>` element — the markup carries
`colors="…" name="…"` attributes no other release emits — and upstream fixed it
in 1.11.1. Supporting it would mean reproducing those attributes. A caller
pinned to 1.11.0 is told it is unsupported rather than quietly handed a
neighbour's output.

Upstream releases share a selector when **a caller gets the same thing out of
them**, not when their source happens to match. `1.6.1`, `1.6.2` and `1.6.3`
collapse into one value because all three were measured to render byte-identical
documents, not because the code looked similar. The nine releases behind
`v1_10_1` are the sharper case of the same rule: their *sources* differ plenty
— a props rework, a full TypeScript rewrite — and rendering every one of them
side by side is what shows a caller gets the same document out of all nine.

**These are upstream's git tags, not its npm versions.** The two disagree in
both directions. npm `1.2.1` republished 0.1.4-era code — a tag's worth of
history under a number that suggests otherwise. And going the other way,
upstream's **two most recent npm releases have no tag at all**: the tags stop at
`v2.0.2`, while npm carries `2.0.3` and `2.0.4`, and `2.0.4` is what `npm
install boring-avatars` gives you today.

So when you pin a version here you are naming a tag in
[the upstream repository](https://github.com/boringdesigners/boring-avatars/tags),
and for the newest releases this package will name the source it read instead.
Where the two numbering schemes point at the same code, they agree; where they
do not, the tag is what a selector means.

### `version` has no default, on purpose

`BoringAvatarsVersion.latest` moves as this package adds releases, and upstream
releases do not all draw the same thing — `1.10.1` changed `pixel`'s colours.
A default of "newest" would therefore redraw the avatars in your app the day you
upgraded a dependency. Name the version you want and it is yours forever; pass
`BoringAvatarsVersion.latest` explicitly if tracking upstream's newest is what
you actually want.

## Drawing it in Flutter

```dart
BoringAvatar(
  name: 'Clara Barton',
  colors: const ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'],
  size: 80,
  version: BoringAvatarsVersion.v1_6_1,
  variant: BoringAvatarsVariant.beam,
)
```

`BoringAvatar` draws through this package's own rasterizer, at the display's
physical pixel size. **It does not use `flutter_svg`, and it does not draw on a
`Canvas`.** Measured: `flutter_svg` does not clamp `rx` the way SVG 1.1 §9.4
requires, so the circular mask every variant relies on comes out square, and it
has no `<filter>` at all, so `marble` loses its blur. A `Canvas` would make the
output depend on Skia-vs-Impeller, GPU, platform and Flutter version — which is
the whole reason this package rasterises in software.

So the determinism guarantee — the same bytes on every platform, GPU, Flutter
version and rendering backend — covers the widget as well as the SVG string.
That guarantee is about the image the widget **produces**: it is rasterised at
the box's physical pixel size, painted onto **whole** device pixels, and handed
over with `FilterQuality.none`, so nothing resamples it. That is the ordinary
case; where an ancestor puts it out of reach, see *Where one pixel cannot cover
one pixel* below.

Whole device pixels is the part that has to be arranged rather than assumed. A
45-logical box at 150% display scaling is 67.5 physical pixels, and no buffer is
67.5 pixels wide — so the widget rounds the drawing onto the pixel grid instead
of letting the mismatch reach the sampler. It moves the avatar by at most half a
physical pixel and it is what keeps `FilterQuality.none` honest: before `0.3.1`
a fractional box on a fractional origin cost a whole pixel column, which on a
disc that touches all four edges of its box reads as a flat, shaved edge.

One case is narrowed rather than closed. Where `size × dpr` rounds *up*, the
buffer is a hair wider than the box — 45 logical at 150% is 67.5 physical pixels
holding a 68-pixel buffer — so an ancestor that clips to exactly the box takes
that hair back off. Nothing can place a 68-pixel square inside 67.5. It is
strictly better than before (21 of 105 measured combinations were wrong, now 6,
and the 6 are among the 21), and a clip even a fraction larger than the avatar
avoids it entirely.

The grid it rounds to is the **screen's**, not the enclosing layer's, which
matters more than it sounds: `ListView` gives every child its own
`RepaintBoundary`, and a boundary carries the fractional position itself while
handing its child a whole-looking offset. An avatar sitting in a list is the
ordinary case, not the exotic one.

While a list is actually *scrolling*, though, the alignment goes stale — the
position is computed when the avatar paints, and scrolling moves the layer
without repainting what is inside it. It comes back the moment the row
repaints. This is a Flutter-level limitation rather than one this package can
close (flutter/flutter#111302); Flutter's own text caret snaps to physical
pixels the same way and inherits the same gap.

### Where one pixel cannot cover one pixel

Everything above arranges for one buffer pixel to cover one device pixel, and
`FilterQuality.none` is exact exactly while that holds. Two ordinary situations
put it out of reach, and no placement fixes either: an ancestor that **scales or
rotates**, where this box's grid is not the device's grid at all, and a
**buffer that is not the destination's size** — a parent squeezing the box, or a
display-scale change that leaves the previous buffer up until the new one is
drawn.

There, `FilterQuality.none` is the *worst* available choice rather than the
safest. Nearest neighbour cannot spend a fraction of a pixel, so it drops or
duplicates whole columns — on a smooth `marble` gradient that reads as a fold
straight across the avatar. So the widget draws those with a filter instead:
half a pixel of softness in place of a fold.

This narrows the determinism guarantee's stated scope without spending any of
it. Where the avatar lands one pixel per pixel — the overwhelming majority — the
bytes are exactly what they have always been. Where it does not, the output was
already the backend's: which column nearest neighbour keeps is the sampler's
rounding, so Skia and Impeller were never obliged to agree there either.

Layout that then squeezes the box smaller than the size you asked for is outside
the package, and Flutter's sampler runs there like it would for any image — a
filtered one, now that the drawing is knowingly a scaled copy.

### One rule for callers, and it is about the ancestor rather than the avatar

Everything above happens while the avatar is painted. **An ancestor that
composites — a scroll viewport, an `Opacity` or `FadeTransition`, a
`RepaintBoundary` — draws it into a layer first, and the engine puts that layer
on screen afterwards.** If the layer lands on a fractional device pixel, the
engine resamples the whole layer, avatar included, and no arithmetic available
while painting can pre-empt it.

Measured on a real engine at 150% scaling, comparing each case against the same
avatar with no ancestor at all:

| ancestor | its origin | result |
|---|---|---|
| none | whole *or* fractional | identical either way — the alignment above handles it |
| scroll viewport | whole device pixel | **identical** |
| scroll viewport | half a device pixel | 2556 interior pixels differ, by up to 94 levels |
| `Opacity` | whole device pixel | identical but for the opacity itself |
| `Opacity` | half a device pixel | 3179 interior pixels differ, by up to 94 levels |

So the compositing ancestor is not the problem; **a compositing ancestor at a
fractional origin is.** If an avatar inside a list or a fade looks folded, align
*that ancestor* to whole device pixels, or keep the avatar out of it — and note
that wrapping the avatar in a `RepaintBoundary` does not help, because a boundary
is one more layer with an origin of its own.

### The avatar arrives a beat after the widget does

Drawing happens off the frame — in a background isolate on native, and in
interruptible slices on web, where Flutter has no isolate to offer. **Your app
stays responsive while it draws**, and the box is its final size from the very
first frame, so nothing reflows when the picture lands. But the picture is not
there on frame one.

Cutting the drawing into slices is not a tax on it. Measured back to back across
eight runs and five sizes, the interruptible drawing takes the same total time
as the uninterrupted one — the responsiveness is free.

Measured for `marble`, the most expensive variant, at its **physical** size:

| physical pixels a side | native | web |
|---|---|---|
| 80 (a 40-logical avatar at 2x) | 33 ms | |
| 120 (the same at 3x) | 80 ms | |
| 210 | 237 ms | |
| 480 | | 5.4 s |

The blanks are not measured. Cost grows with area and web runs the same drawing
about **four times slower** than native, which is enough to place them — but they
are arithmetic, and this table only states what was observed. They are also one
machine's: a busy machine moves the absolute numbers by several times, so read
them as an order of magnitude. The ratios below are the durable part, because a
ratio measured back to back cancels the conditions both halves shared.

Two things worth knowing before scaling from it. `pixel` is the cheapest variant
and `marble` and `beam` the dearest, but **the gap depends on the size**: `pixel`
is about eight times cheaper than `marble` at 80 physical pixels and only two to
three times cheaper at 480. The next paragraph is why. And compiling to
WebAssembly does **not** help — measured, it is 2.2–2.6x slower than the
JavaScript build for this code.

**One size per variant is much cheaper than its neighbours.** Each variant is
drawn from a fixed-size design — 80 units for `marble`, `pixel`, `sunset` and
`bauhaus`, 90 for `ring`, 36 for `beam`. Ask for exactly that many *physical*
pixels and the scale is 1, which is the one case where an axis-aligned rectangle
stays a rectangle and takes an exact closed-form coverage instead of going
through the polygon integrator. The picture is the same either way; the cost is
not. Measured, `pixel` is **6.5x cheaper at 80 than at 81**, and `bauhaus` about
twice as cheap. `ring`, which has no axis-aligned rectangle in it, does not move
across the same step — which is what identifies the cause rather than merely
observing the dip.

So if you draw many avatars and can pick the number, a `size` where
`size × devicePixelRatio` lands exactly on the variant's own is worth having.
Nothing else about the avatar changes.

**One thing does change, and it is not a defect.** Away from that size, two
shapes that meet edge to edge can share a pixel, and neither fills it — so
`pixel` shows faint seams between its tiles at most scales. A browser does the
same thing with the same document: measured against Chrome at a 1.25 scale, both
leave **784** pixels partly covered and there is not one pixel Chrome fills that
this package leaves open. Reproducing the browser is the whole point, so the
seams stay.

Away from that one size the cost is O(area), so it is the physical size that
matters: doubling `size` is four times the work, and moving the same avatar from
a 2x display to a 3x one is 2.25 times.

**If the inputs change, the widget blanks rather than showing the old avatar** —
a new `name`, palette, `variant`, `version` or `square` is a different person's
face, and showing the previous one under the new name would be a small lie. A
change to `size` alone is the *same* avatar at a new resolution, so that one
keeps drawing until the sharper version is ready and never flashes.

**A raster that fails reports through Flutter's error machinery** rather than
disappearing, and the widget clears rather than leaving a stale avatar behind.

**`colors` is narrower on the widget — but not by much any more.**
`boringAvatarSvg` hands a colour to the document and a browser draws it, so
*any* CSS colour works there. The rasterizer reads:

* hex — `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`;
* the **148 CSS named colours**, plus `transparent` and `currentColor`;
* `rgb()` / `rgba()` / `hsl()` / `hsla()` — either separator, percentages or
  0–255, alpha as a number or a percentage, and a hue in `deg`, `grad`, `rad`
  or `turn`;
* the CSS Color 4 families — `hwb()`, `lab()` / `lch()`, `oklab()` /
  `oklch()`, and `color()` with every predefined space (`srgb`,
  `srgb-linear`, `display-p3`, `a98-rgb`, `prophoto-rgb`, `rec2020`, the
  `xyz` trio). A colour outside the sRGB gamut clips per channel, which is
  what Chrome was measured doing;
* the **42 system colours** (`Canvas`, `AccentColor`, the deprecated
  aliases…), frozen at the values Chrome resolves on macOS in light mode —
  the one place "the same as the browser" cannot be promised across
  machines, because system colours vary by OS and theme by design.

Keywords are ASCII case-insensitive and tolerate surrounding whitespace, as CSS
defines them. For something outside that grammar the rasterizer answers as a
browser answers an invalid declaration — the shape is not painted, and a
gradient stop falls back to black — but the widget rejects the palette first
and names the argument, so a typo fails loudly instead of as a missing shape.

The name table is **generated from the CSS Color 4 specification**, not typed
out, and every one of the 148 was cross-checked against a real Chrome render —
a mistyped entry would be wrong only for the palette that names it, which no
test could catch.

**A palette colour may be translucent.** `#RRGGBBAA`, `rgba(…)`, `hsla(…)` and
`transparent` all carry their own alpha, and it multiplies the shape's coverage
— what a browser does with the same document. Measured against Chrome on a
stacked variant, every interior pixel agrees to within 1/255.

## Where it differs on purpose

Two inputs do not reproduce upstream. Everything else does — including
upstream's own bugs, which are reproduced rather than corrected.

### A `sunset` name containing quotes or brackets

With `variant: sunset`, a name containing `'`, `"`, `(`, `)`, `\` or a control
character makes upstream build a gradient reference that is not a valid CSS url
token — so the browser resolves nothing and **paints a blank avatar**.
Reproduced in Chrome: `O'Brien-Smith, Jr.` renders as fully transparent pixels.
This package percent-encodes that reference, so the avatar renders. The
gradient's own `id` stays byte-identical to upstream, and so does every other
name and every other variant.

An apostrophe in a name is common enough that reproducing the blank was judged
the wrong trade. If you need upstream's exact bytes including its blanks, this
is the one place you will not get them.

### A `size` that is not a size

`size` accepts a `num` (`80` → `width="80"`) or a `String` (`'100%'`). Anything
else throws an `ArgumentError` naming the argument. Upstream instead coerces,
because React does:

| `size` | upstream 1.6.1 | this package |
|---|---|---|
| `80`, `'100%'` | `width="80"`, `width="100%"` | identical |
| `true`, `false`, `null` | `width` and `height` **absent**, plus a React console warning | `ArgumentError` |
| `[80]` | `width="80"` | `ArgumentError` |
| `{}` | `width="[object Object]"` | `ArgumentError` |

Reproducing that would mean reproducing JavaScript's `String()` coercion and
React's attribute-dropping rules in order to emit `width="[object Object]"`
faithfully — and React prints that warning precisely to tell the author they
made a mistake, so the behaviour being reproduced is a bug report. Every value a
caller can plausibly mean by "size" is byte-identical; the divergence is
confined to values that are not sizes at all.

## An empty palette is not always an error

Upstream degrades rather than validating, and it degrades *differently* per
variant. This package reproduces that instead of smoothing it over: with
`colors: []`, five variants render an avatar with colours missing, and `beam`
throws an `ArgumentError` — because upstream throws there too, and a `beam` that
degraded would be an image upstream has never produced.

## Status

`0.3.0` reached upstream's newest release: `v1_10_1` covers `1.10.1` through
`2.0.4` (nine releases, `1.11.0` excluded — see the support table), alongside
`v1_7_0` (`1.7.0`–`1.10.0`) and `v1_6_1` (`1.6.1`–`1.6.3`). With that, the
public API is settled: every upstream release worth reproducing has a selector,
and what follows is keeping up with upstream's future releases, each as a new
value.

`0.3.1` is a patch on top of that and adds no selector. It moves no byte any
avatar is made of — it fixes **where** the widget puts them, which was off the
device pixel grid at fractional display scalings. The SVG surface is untouched
by it entirely.

Releases share a selector because a caller gets the same thing out of them, and
that is **measured rather than asserted**. For `v1_10_1`, each of the other
eight releases is rendered and compared to 1.10.1 across **2,400 documents —
variant × name × palette × title × square — zero differ**. For `v1_7_0`, the
same comparison covers 1.10.0; 1.8.0 and 1.9.0 cannot be rendered by anybody —
their npm tarballs contain no JavaScript at all (`main` points at a
`build/index.js` that is not in the package — 0 files, counted) — so their
evidence is that their source tree *is* 1.10.0's, byte for byte. `2.0.3` and
`2.0.4` have no git tag; they are covered from the npm packages themselves,
whose recorded publish commits resolve in upstream's history (both to the same
source tree as `master`), and that resolution is recorded in the fixture.

**One attribute inside those groups is not reproduced, and cannot be.** From
1.8.0 upstream names its mask with React's `useId()`, which is the component's
position in the render tree rather than anything about the avatar. Measured:
the same avatar is `:R0:` alone, `:R3:` as a third child, `:R2:` after a
`<span>` — and **two copies of one avatar in a single document get two
different ids**. So such a release has no fixed bytes for an avatar for
anything to reproduce, including itself. This package emits the literal
`mask__marble` that 1.7.0 writes, at every position — and the same goes for
`marble`'s filter id, which is the literal `prefix__filter0_f` through 1.10.1
and `useId()`-derived from 1.10.2.

Everything a reader can see is unaffected, and that is measured rather than
argued: upstream's own documents and this package's went through one Chrome,
1,200 renders per selector — `v1_6_1` against 1.6.1, `v1_7_0` against 1.10.0,
`v1_10_1` against **2.0.4**, the far end of its group. Each run: **1,150
pixel-identical**, 40 where both sides produce no document at all (`beam` with
an empty palette), and the 10 `sunset` blanks documented below. **Zero
unexplained differences, in any run.**

If you need the document's internal ids to match a particular upstream render,
that is the one thing these selectors do not give you.

The emitted documents are pinned by the test suite against fixtures generated
from the real npm package — 600 per selector, across six variants, twenty
names and five palettes, plus title, square and size variations. The two divergences above were
measured rather than reasoned about — the blank `sunset` avatar in Chrome, the
`size` coercions by rendering upstream itself. Both the parity harness and the
browser tooling live in the repository, so any of it can be re-measured rather
than taken on trust.
