# boring_avatars

A bit-exact Dart port of
[boring-avatars](https://github.com/boringdesigners/boring-avatars).

Given the same name, palette and variant, this package produces the avatar the
npm package produces — the same numbers, the same SVG, the same bytes. Two
deliberate exceptions are documented under [Where it differs on purpose](#where-it-differs-on-purpose).

Every supported upstream release is reachable at once — npm needs a downgrade to
render an older version's avatar, here it is a parameter. `0.1.0` supports the
first of them; the rest arrive as additional selector values.

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

That is everything `0.2.0` supports. **Later releases of this package add
selector values; they never change one.** A shipped selector's output is frozen
— an avatar you render today renders identically on every future version of this
package — so support grows by addition only.

Upstream releases share a selector when **a caller gets the same thing out of
them**, not when their source happens to match. `1.6.1`, `1.6.2` and `1.6.3`
collapse into one value because all three were measured to render byte-identical
documents, not because the code looked similar.

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
That guarantee is about the image the widget **produces**: it is drawn at the
box's own physical pixel size and handed over with `FilterQuality.none`, so
nothing resamples it. Layout that then squeezes the box smaller than the size
you asked for is outside the package, and Flutter's sampler runs there like it
would for any image.

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

`0.2.0` adds upstream `1.7.0`–`1.10.0` as a second selector, alongside
`1.6.1`–`1.6.3`. What follows: the remaining upstream releases, each as a new
selector value.

Four upstream releases share `v1_7_0` because a caller gets the same thing out
of them, and that is **measured rather than asserted**. 1.10.0 is rendered and
compared to 1.7.0 across 1,200 documents — zero differ. 1.8.0 and 1.9.0 cannot
be rendered by anybody: their npm tarballs contain no JavaScript at all (`main`
points at a `build/index.js` that is not in the package — 0 files, counted),
so their evidence is that their source tree *is* 1.10.0's, byte for byte.

**One attribute inside that group is not reproduced, and cannot be.** From
1.8.0 upstream names its mask with React's `useId()`, which is the component's
position in the render tree rather than anything about the avatar. Measured:
the same avatar is `:R0:` alone, `:R3:` as a third child, `:R2:` after a
`<span>` — and **two copies of one avatar in a single document get two
different ids**. So 1.8.0 has no fixed bytes for an avatar for anything to
reproduce, including 1.8.0. This package emits the literal `mask__marble` that
1.7.0 writes, at every position.

Everything a reader can see is unaffected: the id names nothing but the mask's
own reference, and every shape, coordinate, colour and attribute is identical.
If you need the document's internal ids to match a particular upstream render,
that is the one thing this selector does not give you.

The emitted documents are pinned by the test suite against fixtures generated
from the real npm package — 600 of them, across six variants, twenty names and
five palettes, plus square and size variations. The two divergences above were
measured rather than reasoned about — the blank `sunset` avatar in Chrome, the
`size` coercions by rendering upstream itself. Both the parity harness and the
browser tooling live in the repository, so any of it can be re-measured rather
than taken on trust.
