# boring_avatars

A bit-exact Dart port of
[boring-avatars](https://github.com/boringdesigners/boring-avatars).

Given the same name, palette and variant, this package produces the avatar the
npm package produces — the same numbers, the same SVG, the same bytes. Two
deliberate exceptions are documented under [Where it differs on purpose](#where-it-differs-on-purpose).

Every supported upstream release is reachable at once — npm needs a downgrade to
render an older version's avatar, here it is a parameter. `0.1.0` supports the
first of them; the rest arrive as additional selector values.

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

## Supported upstream releases

| Selector | Reproduces upstream |
|---|---|
| `BoringAvatarsVersion.v1_6_1` | `1.6.1`, `1.6.2`, `1.6.3` |

That is everything `0.1.0` supports. **Later releases of this package add
selector values; they never change one.** A shipped selector's output is frozen
— an avatar you render today renders identically on every future version of this
package — so support grows by addition only.

Upstream releases share a selector when **a caller gets the same thing out of
them**, not when their source happens to match. `1.6.1`, `1.6.2` and `1.6.3`
collapse into one value because all three were measured to render byte-identical
documents, not because the code looked similar.

**These are upstream's git tags, not its npm versions.** The two disagree: npm
`1.2.1`, for instance, republished 0.1.4-era code. When you pin a version here,
you are naming a tag in
[the upstream repository](https://github.com/boringdesigners/boring-avatars/tags).

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

**`colors` is narrower on the widget.** `boringAvatarSvg` hands a colour to the
document and a browser draws it, so `'red'` works there. The rasterizer reads
`#RRGGBB` and nothing else yet, and rather than draw a blank avatar for a colour
it cannot read, the widget rejects it and names the argument. Later releases
widen what is accepted; a palette that works today keeps working.

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

`0.1.0` ships the SVG string and the widget, for upstream `1.6.1`–`1.6.3`.
What follows: the remaining upstream releases, each as a new selector value.

The emitted documents are pinned by the test suite against fixtures generated
from the real npm package — 600 of them, across six variants, twenty names and
five palettes, plus square and size variations. The two divergences above were
measured rather than reasoned about — the blank `sunset` avatar in Chrome, the
`size` coercions by rendering upstream itself. Both the parity harness and the
browser tooling live in the repository, so any of it can be re-measured rather
than taken on trust.
