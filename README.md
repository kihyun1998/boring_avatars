# boring_avatars

A bit-exact Dart port of
[boring-avatars](https://github.com/boringdesigners/boring-avatars).

Given the same name, palette and variant, this package produces the avatar the
npm package produces — the same numbers, the same SVG, the same bytes.

Every supported upstream release is reachable at once. npm needs a downgrade to
render an older version's avatar; here it is a parameter.

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

### `version` has no default, on purpose

`BoringAvatarsVersion.latest` moves as this package adds releases, and upstream
releases do not all draw the same thing — `1.10.1` changed `pixel`'s colours.
A default of "newest" would therefore redraw the avatars in your app the day you
upgraded a dependency. Name the version you want and it is yours forever; pass
`BoringAvatarsVersion.latest` explicitly if tracking upstream's newest is what
you actually want.

## Drawing it in Flutter

**Flutter cannot draw an SVG on its own.** To show this string in a Flutter app
you need a third-party renderer such as
[`flutter_svg`](https://pub.dev/packages/flutter_svg) — and the pixels are then
that package's, not this one's.

This package's determinism guarantee — the same bytes on every platform, GPU,
Flutter version and rendering backend — covers what it produces. Today that is
the SVG document. Its own deterministic rasterizer and a `BoringAvatar` widget
follow in a later release; until then, the guarantee does not extend to whatever
renderer you hand the string to.

## An empty palette is not always an error

Upstream degrades rather than validating, and it degrades *differently* per
variant. This package reproduces that instead of smoothing it over: with
`colors: []`, five variants render an avatar with colours missing, and `beam`
throws an `ArgumentError` — because upstream throws there too, and a `beam` that
degraded would be an image upstream has never produced.

## Status

Pre-release. Supported upstream versions, the version matrix and the npm-vs-git
caveat are documented at first publish.
