/// The `ring` variant — a target of nine concentric bands.
///
/// **Sacred surface.** These values decide what a user's avatar looks like, and
/// after a release they cannot be corrected without changing it.
///
/// Three things about this variant are worth stating up front:
///
/// * **Nine slots are painted from five draws.** `generateColors` takes five
///   colours and then assigns them to nine slots through a fixed remap, so four
///   pairs of bands always share a colour. The remap *is* the specification —
///   there is no rule behind it to re-derive.
/// * **The five draws are consecutive, not independent.** Upstream calls
///   `getRandomColor(numFromName + i, …)` for `i` in 0–4, walking the palette by
///   one each time rather than re-hashing.
/// * **The drawing space is 90, not 80.** Every other variant in the six uses an
///   80-unit viewBox; `ring` uses 90. `size` still only reaches `width` and
///   `height`, so the two numbers are independent. The rasterizer used to
///   refuse any target that was not 90×90; since #58 it scales, so `ring`'s
///   goldens are 90×90 because that is its 1:1 size, not because it is the
///   only size reachable.
library;

import '../js/utilities.dart';
import '../scene/scene.dart';

/// The viewBox is a per-variant constant upstream.
const int _size = 90;

/// How many colours `generateColors` actually draws.
const int _draws = 5;

/// Slot → draw index, in DOM order. Extracted from `avatar-ring.js` at v1.6.1,
/// where it is written out as nine separate assignments.
const List<int> _slotSource = [0, 1, 1, 2, 2, 3, 3, 0, 4];

/// The eight `d` strings, in emission order.
///
/// These are **literals upstream** — the components hardcode 90 and 45 rather
/// than deriving them from `SIZE`, so they are literals here too. Deriving them
/// would invent a structure the reference does not have, and the strings are
/// also what the SVG backend emits verbatim.
///
/// Each is a closed half-disc: an arc from one end of a horizontal diameter to
/// the other, then the chord back. The three radii are 38, 32 and 26, and the
/// arcs are painted largest first so each smaller one covers the last.
const List<String> _paths = [
  'M0 0h90v45H0z',
  'M0 45h90v45H0z',
  'M83 45a38 38 0 00-76 0h76z',
  'M83 45a38 38 0 01-76 0h76z',
  'M77 45a32 32 0 10-64 0h64z',
  'M77 45a32 32 0 11-64 0h64z',
  'M71 45a26 26 0 00-52 0h52z',
  'M71 45a26 26 0 01-52 0h52z',
];

/// The nine band colours, or `null` where upstream produces `undefined`.
///
/// An empty palette makes `range` zero, so every draw is `hash % 0` — `NaN`
/// upstream, `null` here — and all nine come back unfilled. Unlike `beam`,
/// nothing downstream dereferences them, so `ring` degrades rather than
/// throwing (hidden-state #8).
List<String?> ringColors(String name, List<String> colors) {
  final numFromName = jsHashCode(name);
  final range = colors.length;
  final drawn = List<String?>.generate(
    _draws,
    (i) => jsGetRandomColor(numFromName + i, colors, range),
  );
  return [for (final source in _slotSource) drawn[source]];
}

/// Builds the `ring` scene for upstream v1.6.1.
///
/// [size] lands on the `<svg>` element's width and height and reaches nothing
/// else. [square] drops the mask's corner radius, and upstream expresses that
/// by passing `undefined`, which makes React **omit the attribute** rather than
/// write a default.
SvgNode buildRingScene({
  required String name,
  required List<String> colors,
  required Object size,
  bool square = false,
  // **Required, with no default.** A default here would be one selector's
  // answer baked into the sacred surface: 1.6.x renders the element always,
  // 1.7.0 defaults it off, and a builder shared by both may not prefer one.
  // The cost is that every direct caller states which document it wants,
  // which is the information a parity test was relying on a default to
  // supply. See hidden-state #16.
  required bool title,
}) {
  final bands = ringColors(name, colors);

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
          SvgAttribute('id', 'mask__ring'),
          // No `mask-type` here — `pixel` is the only one of the six that
          // declares it, so this is a *luminance* mask (hidden-state #22). It
          // is filled #FFFFFF, where luminance and alpha both come to 1.
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
              if (!square) const SvgAttribute('rx', _size * 2),
              const SvgAttribute('fill', '#FFFFFF'),
            ],
          ),
        ],
      ),
      SvgNode(
        SvgElement.g,
        attributes: const [SvgAttribute('mask', 'url(#mask__ring)')],
        children: [
          for (var i = 0; i < _paths.length; i++)
            SvgNode(
              SvgElement.path,
              attributes: [
                SvgAttribute('d', _paths[i]),
                if (bands[i] != null) SvgAttribute('fill', bands[i]!),
              ],
            ),
          SvgNode(
            SvgElement.circle,
            attributes: [
              const SvgAttribute('cx', 45),
              const SvgAttribute('cy', 45),
              const SvgAttribute('r', 23),
              if (bands[8] != null) SvgAttribute('fill', bands[8]!),
            ],
          ),
        ],
      ),
    ],
  );
}
