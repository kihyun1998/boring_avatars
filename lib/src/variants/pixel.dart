/// The `pixel` variant — an 8×8 mosaic of coloured tiles.
///
/// **Sacred surface.** These values decide what a user's avatar looks like, and
/// after a release they cannot be corrected without changing it.
///
/// Two things about this variant are surprising enough to state up front:
///
/// * **The first tile is never filled.** Upstream builds its colour list with
///   `getRandomColor(numFromName % i, …)` starting at `i == 0`, and `hash % 0`
///   is `NaN` in JavaScript, so `colors[NaN]` is `undefined` and React omits
///   the attribute. It happens for every name and every palette, including the
///   defaults — not an edge case (hidden-state #17).
/// * **The tiles are not emitted in reading order.** The DOM order is
///   `x = 0, 20, 40, 60, 10, 30, 50, 70` across the top row, then column by
///   column. The table below is extracted from the component rather than
///   retyped, because the order is load-bearing for byte parity and invisible
///   on screen.
library;

import '../js/js_number.dart';
import '../js/utilities.dart';
import '../scene/scene.dart';

/// The viewBox is a per-variant constant upstream.
const int _size = 80;

/// The tile grid, as `[x, y, colourIndex]`, **in upstream's emission order**.
///
/// Extracted from `avatar-pixel.js` at v1.6.1 and checked: 64 entries, indices
/// 0–63 exactly once, covering the 8×8 grid.
const List<List<int>> _tiles = [
  [0, 0, 0],
  [20, 0, 1],
  [40, 0, 2],
  [60, 0, 3],
  [10, 0, 4],
  [30, 0, 5],
  [50, 0, 6],
  [70, 0, 7],
  [0, 10, 8],
  [0, 20, 9],
  [0, 30, 10],
  [0, 40, 11],
  [0, 50, 12],
  [0, 60, 13],
  [0, 70, 14],
  [20, 10, 15],
  [20, 20, 16],
  [20, 30, 17],
  [20, 40, 18],
  [20, 50, 19],
  [20, 60, 20],
  [20, 70, 21],
  [40, 10, 22],
  [40, 20, 23],
  [40, 30, 24],
  [40, 40, 25],
  [40, 50, 26],
  [40, 60, 27],
  [40, 70, 28],
  [60, 10, 29],
  [60, 20, 30],
  [60, 30, 31],
  [60, 40, 32],
  [60, 50, 33],
  [60, 60, 34],
  [60, 70, 35],
  [10, 10, 36],
  [10, 20, 37],
  [10, 30, 38],
  [10, 40, 39],
  [10, 50, 40],
  [10, 60, 41],
  [10, 70, 42],
  [30, 10, 43],
  [30, 20, 44],
  [30, 30, 45],
  [30, 40, 46],
  [30, 50, 47],
  [30, 60, 48],
  [30, 70, 49],
  [50, 10, 50],
  [50, 20, 51],
  [50, 30, 52],
  [50, 40, 53],
  [50, 50, 54],
  [50, 60, 55],
  [50, 70, 56],
  [70, 10, 57],
  [70, 20, 58],
  [70, 30, 59],
  [70, 40, 60],
  [70, 50, 61],
  [70, 60, 62],
  [70, 70, 63],
];

/// The 64 tile colours, or `null` where upstream produces `undefined`.
///
/// Index 0 is always `null` — see the library doc.
List<String?> pixelColors(String name, List<String> colors) {
  final numFromName = jsHashCode(name);
  final range = colors.length;
  return List<String?>.generate(64, (i) {
    // `numFromName % i`, where i == 0 gives NaN upstream. jsMod would throw.
    final index = jsModOrNull(numFromName, i);
    if (index == null) return null;
    return jsGetRandomColor(index, colors, range);
  });
}

/// Builds the `pixel` scene for upstream v1.6.1.
///
/// [size] lands on the `<svg>` element's width and height and reaches nothing
/// else — it is consumer policy, and the fixture proves it is a passthrough.
/// [square] drops the mask's corner radius, and upstream expresses that by
/// passing `undefined`, which makes React **omit the attribute** rather than
/// write a default.
SvgNode buildPixelScene({
  required String name,
  required List<String> colors,
  required Object size,
  bool square = false,
  // Defaults to the **1.6.x document**, which is the one shape this builder
  // was written against — not to upstream 1.7.0's `title = false`. The
  // public seam never reaches the default: `buildAvatarScene` resolves the
  // version's answer and always passes it. See hidden-state #16.
  bool title = true,
}) {
  final tileColors = pixelColors(name, colors);

  return SvgNode(
    SvgElement.svg,
    attributes: [
      const SvgAttribute('viewBox', '0 0 $_size $_size'),
      const SvgAttribute('fill', 'none'),
      const SvgAttribute('role', 'img'),
      const SvgAttribute('xmlns', 'http://www.w3.org/2000/svg'),
      SvgAttribute('width', size),
      SvgAttribute('height', size),
    ],
    children: [
      // `{props.title && <title>…</title>}` — upstream 1.7.0 onward (#16).
      if (title) SvgNode(SvgElement.title, text: name),
      SvgNode(
        SvgElement.mask,
        attributes: const [
          SvgAttribute('id', 'mask__pixel'),
          SvgAttribute('mask-type', 'alpha'),
          SvgAttribute('maskUnits', 'userSpaceOnUse'),
          SvgAttribute('x', 0),
          SvgAttribute('y', 0),
          SvgAttribute('width', _size),
          SvgAttribute('height', _size),
        ],
        children: [
          SvgNode(
            SvgElement.rect,
            attributes: [
              const SvgAttribute('width', _size),
              const SvgAttribute('height', _size),
              // `rx={square ? undefined : SIZE * 2}` — omitted, not defaulted.
              if (!square) const SvgAttribute('rx', _size * 2),
              const SvgAttribute('fill', '#FFFFFF'),
            ],
          ),
        ],
      ),
      SvgNode(
        SvgElement.g,
        attributes: const [SvgAttribute('mask', 'url(#mask__pixel)')],
        children: [
          for (final tile in _tiles)
            SvgNode(
              SvgElement.rect,
              attributes: [
                // Upstream passes `x` and `y` only when they are non-zero, so
                // the attribute is absent rather than `="0"`. Verified against
                // the component: the omissions coincide exactly with zero.
                if (tile[0] != 0) SvgAttribute('x', tile[0]),
                if (tile[1] != 0) SvgAttribute('y', tile[1]),
                const SvgAttribute('width', 10),
                const SvgAttribute('height', 10),
                if (tileColors[tile[2]] != null)
                  SvgAttribute('fill', tileColors[tile[2]]!),
              ],
            ),
        ],
      ),
    ],
  );
}
