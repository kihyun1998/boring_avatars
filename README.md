# boring_avatars

[![pub package](https://img.shields.io/pub/v/boring_avatars.svg)](https://pub.dev/packages/boring_avatars)

Deterministic avatars from a name. A bit-exact Dart port of
[boring-avatars](https://github.com/boringdesigners/boring-avatars).

<table>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/kihyun1998/boring_avatars/main/docs/images/variant-marble.png" width="110" alt="marble"></td>
    <td align="center"><img src="https://raw.githubusercontent.com/kihyun1998/boring_avatars/main/docs/images/variant-beam.png" width="110" alt="beam"></td>
    <td align="center"><img src="https://raw.githubusercontent.com/kihyun1998/boring_avatars/main/docs/images/variant-pixel.png" width="110" alt="pixel"></td>
    <td align="center"><img src="https://raw.githubusercontent.com/kihyun1998/boring_avatars/main/docs/images/variant-sunset.png" width="110" alt="sunset"></td>
    <td align="center"><img src="https://raw.githubusercontent.com/kihyun1998/boring_avatars/main/docs/images/variant-ring.png" width="110" alt="ring"></td>
    <td align="center"><img src="https://raw.githubusercontent.com/kihyun1998/boring_avatars/main/docs/images/variant-bauhaus.png" width="110" alt="bauhaus"></td>
  </tr>
  <tr>
    <td align="center"><code>marble</code></td>
    <td align="center"><code>beam</code></td>
    <td align="center"><code>pixel</code></td>
    <td align="center"><code>sunset</code></td>
    <td align="center"><code>ring</code></td>
    <td align="center"><code>bauhaus</code></td>
  </tr>
</table>

<sub>All six drawn from the name `Clara Barton`, by this package's own
rasterizer — `dart run tool/readme/generate.dart` redraws them.</sub>

## Install

```bash
flutter pub add boring_avatars
```

## Draw one

```dart
import 'package:boring_avatars/boring_avatars.dart';

BoringAvatar(
  name: 'Clara Barton',
  colors: const ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'],
  size: 80,
  version: BoringAvatarsVersion.v1_10_1,
  variant: BoringAvatarsVariant.beam,
)
```

Or get the SVG string instead, with the same arguments:

```dart
final svg = boringAvatarSvg(
  name: 'Clara Barton',
  colors: const ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'],
  size: 80,
  version: BoringAvatarsVersion.v1_10_1,
  variant: BoringAvatarsVariant.beam,
);
```

Both take upstream's two deprecated variant names too — `geometric` and
`abstractStyle` — resolving to `beam` and `bauhaus` exactly as upstream
resolves them.

## Arguments

Everything is yours to inject. The package assumes no palette, no size and no
upstream release.

| Argument | |
|---|---|
| `name` | the only input the drawing comes from |
| `colors` | your palette — any CSS colour on the SVG side, [nearly any](docs/colors.md) on the widget side |
| `size` | a `num` for `width="80"`, or a `String` for `'100%'`. Lands on the `<svg>` element's `width` and `height` and reaches nothing else |
| `version` | which upstream release to reproduce. **Required** — see below |
| `variant` | the style, defaulting to `marble` as upstream does |
| `square` | drops the mask's corner radius |
| `title` | whether the document carries a `<title>`. SVG only, and nullable — see below |

## Pick an upstream version

| Selector | Reproduces upstream | What it changes |
|---|---|---|
| `BoringAvatarsVersion.v1_6_1` | `1.6.1`, `1.6.2`, `1.6.3` | — |
| `BoringAvatarsVersion.v1_7_0` | `1.7.0`, `1.8.0`, `1.9.0`, `1.10.0` | `<title>` becomes optional, and defaults **off** |
| `BoringAvatarsVersion.v1_10_1` | `1.10.1`, `1.10.2`, `1.11.1`, `1.11.2`, `2.0.0`, `2.0.1`, `2.0.2`, `2.0.3`, `2.0.4` | `pixel`'s colour index moves — every `pixel` avatar redraws |

npm needs a downgrade to render an older version's avatar; here it is a
parameter. That list covers every release in scope, upstream's newest included.

**`version` has no default, on purpose.** `BoringAvatarsVersion.latest` moves as
this package adds releases, and upstream releases do not all draw the same thing
— `1.10.1` changed `pixel`'s colours. A default of "newest" would therefore
redraw the avatars in your app the day you upgraded a dependency. Name the
version you want and it is yours forever; pass `BoringAvatarsVersion.latest`
explicitly if tracking upstream's newest is what you actually want.

**A shipped selector's output is frozen.** An avatar you render today renders
identically on every future version of this package. Support grows by addition
only: later releases add selector values and never change one.

`1.11.0` is the one gap in that list, and it is
[deliberate](docs/fidelity.md#1110-is-the-one-hole-in-the-table-and-it-is-deliberate).

### `title` means different things at different versions

`<title>` is the accessible name a screen reader announces for the SVG.
Upstream 1.6.x renders it **always** and offers no prop to stop it; 1.7.0 added
the prop and **defaults it off**. This package defaults with each of them, which
is why the argument is `bool?` rather than `bool` — either literal default would
be wrong for one of the two selectors.

```dart
boringAvatarSvg(…, version: BoringAvatarsVersion.v1_6_1);              // has <title>
boringAvatarSvg(…, version: BoringAvatarsVersion.v1_7_0);              // has none
boringAvatarSvg(…, version: BoringAvatarsVersion.v1_7_0, title: true); // has <title>
boringAvatarSvg(…, version: BoringAvatarsVersion.v1_6_1, title: false); // ArgumentError
```

That last line throws rather than quietly doing nothing. Upstream would ignore
it and leave you believing the element was gone.

`BoringAvatar`, the widget, has no `title` parameter: it produces pixels, and
`<title>` is not drawn. Use Flutter's own `Semantics` to announce an avatar.

## The widget draws its own pixels

`BoringAvatar` does **not** use `flutter_svg` and does **not** draw on a
`Canvas`. It rasterises in software, so the same input gives the same bytes on
every platform, GPU, Flutter version and rendering backend — which is a promise
a `Canvas` cannot keep, because its output depends on Skia-vs-Impeller.

Drawing happens off the frame, so your app stays responsive; the box is its
final size from the first frame, but the picture arrives a beat later.

See [docs/rendering.md](docs/rendering.md) for how it lands on the pixel grid
and what happens inside a scrolling list, and
[docs/performance.md](docs/performance.md) for what it costs.

## Where it differs on purpose

Everything else reproduces upstream exactly — **including upstream's own bugs**,
which are reproduced rather than corrected. Three exceptions:

- **A `sunset` name containing `'`, `"`, `(`, `)` or `\`.** Upstream builds an
  invalid CSS url token and the browser paints a **blank avatar**. This package
  percent-encodes the reference, so the avatar renders.
- **A `size` that is not a `num` or a `String`.** Upstream coerces, because
  React does — `{}` becomes `width="[object Object]"`. This package throws an
  `ArgumentError` naming the argument.
- **The document's internal ids**, which from upstream 1.8.0 come from React's
  `useId()` — the component's position in the render tree. Two copies of one
  avatar in one document get two different ids, so there are no fixed bytes for
  anything to reproduce.

Each is measured rather than reasoned about, with the reasoning and the numbers
in [docs/fidelity.md](docs/fidelity.md).

## Further reading

| | |
|---|---|
| [docs/fidelity.md](docs/fidelity.md) | what "bit-exact" is measured to mean, and the three places it stops |
| [docs/rendering.md](docs/rendering.md) | the pixel grid, compositing ancestors, `FilterQuality` |
| [docs/performance.md](docs/performance.md) | timings, and the one size per variant that is much cheaper |
| [docs/colors.md](docs/colors.md) | every colour notation the rasterizer reads |

## Status

`0.3.0` reached upstream's newest release, and with it the public API is
settled: every upstream release worth reproducing has a selector. What follows
is keeping up with upstream's future releases, each as a new value.

`0.3.1` and `0.3.2` are patches on top of that and add no selector. Neither
moves a byte any avatar is made of — both are about **where** the widget puts
them, and the SVG surface is untouched by either.
