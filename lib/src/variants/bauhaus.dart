/// The `bauhaus` variant — a background, a bar, a disc and a rule.
///
/// **Sacred surface.** These values decide what a user's avatar looks like, and
/// after a release they cannot be corrected without changing it.
///
/// Four things about this variant are worth stating up front:
///
/// * **Four elements are generated and three of them are drawn.** Upstream
///   builds an array of four property sets and then uses `properties[0]` for a
///   colour only — its translation and rotation are computed and never read.
///   They are computed here too, because the loop that produces them is a
///   single expression upstream and special-casing `i == 0` would invent a
///   structure the reference does not have.
/// * **`isSquare` does not use the loop index.** `getBoolean(numFromName, 2)`
///   sits inside the `Array.from` callback next to four fields that all use
///   `i`, so all four elements carry the *same* flag — and only `properties[1]`
///   reads it. A port that threaded `i` through it, which is the change a
///   reader is most likely to make, **survives the whole 100-render byte
///   sweep**: measured, 22 tests green. `getDigit(n, 2)` is the hundreds
///   digit, so `hash + 1` moves element 1's flag only when
///   `hash ≡ 99 (mod 100)` — about one name in a hundred, and none of the
///   corpus's twenty. The blindness is therefore the **corpus's**, not the
///   port's: one more name in that class would close it at layer 2.
///   `bauhaus_parity_test.dart` asserts on layer 1 directly and carries three
///   constructed names so it does not depend on which corpus is current.
/// * **The translation range shrinks as the index grows.** `SIZE / 2 - (i + 17)`
///   is 23, 22, 21 and 20 — so the four elements do not share a range, and a
///   port that hoisted the constant out of the loop moves three of them.
/// * **The line is painted by `stroke`, not by `fill`.** It is the first
///   element in the package whose colour arrives through a stroke, and an empty
///   palette therefore drops `stroke` where the other three drop `fill`.
library;

import '../js/js_number.dart';
import '../js/utilities.dart';
import '../scene/scene.dart';

/// The viewBox is a per-variant constant upstream. `bauhaus` uses 80.
const int _size = 80;

/// How many property sets `generateColors` builds.
const int _elements = 4;

/// One element's generated properties.
///
/// [translateX], [translateY] and [rotate] are unused for element 0 — see the
/// library doc. [color] is `null` where upstream produces `undefined`, which is
/// every element when the palette is empty.
class BauhausElement {
  const BauhausElement({
    required this.color,
    required this.translateX,
    required this.translateY,
    required this.rotate,
    required this.isSquare,
  });

  final String? color;
  final int translateX;
  final int translateY;
  final int rotate;

  /// The same value for all four elements — upstream's callback ignores `i`.
  final bool isSquare;
}

/// The four elements' properties, in upstream's order.
List<BauhausElement> bauhausProperties(String name, List<String> colors) {
  final numFromName = jsHashCode(name);
  final range = colors.length;

  return List<BauhausElement>.generate(_elements, (i) {
    // `numFromName * (i + 1)` reaches ~8.6e9 at i == 3, which is exact in both
    // JavaScript's float64 and Dart's 64-bit int — no narrowing applies here,
    // unlike inside `hashCode` itself.
    final scaled = numFromName * (i + 1);
    // `SIZE / 2 - (i + 17)`: 23, 22, 21, 20. A `~/` is safe because 80 is even,
    // but the literal is written out so the shrink is visible.
    final translateRange = _size ~/ 2 - (i + 17);
    return BauhausElement(
      color: jsGetRandomColor(numFromName + i, colors, range),
      translateX: jsGetUnit(scaled, translateRange, 1),
      translateY: jsGetUnit(scaled, translateRange, 2),
      // No index, so `getUnit` never negates: rotation is 0–359.
      rotate: jsGetUnit(scaled, 360),
      isSquare: jsGetBoolean(numFromName, 2),
    );
  });
}

/// Upstream builds this attribute by concatenating numbers into a string, so it
/// is a string here too — the SVG backend emits it verbatim and the rasterizer
/// parses it back. Deriving a matrix at the scene seam and re-serialising it
/// would put the geometry in two places, which is what this seam prevents.
String _translateRotate(BauhausElement element) =>
    'translate(${jsNum(element.translateX)} ${jsNum(element.translateY)}) '
    'rotate(${jsNum(element.rotate)} ${jsNum(_size ~/ 2)} '
    '${jsNum(_size ~/ 2)})';

/// Builds the `bauhaus` scene for upstream v1.6.1.
///
/// [size] lands on the `<svg>` element's width and height and reaches nothing
/// else. [square] drops the mask's corner radius, and upstream expresses that
/// by passing `undefined`, which makes React **omit the attribute** rather than
/// write a default.
SvgNode buildBauhausScene({
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
  final properties = bauhausProperties(name, colors);

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
          SvgAttribute('id', 'mask__bauhaus'),
          // No `mask-type` — `pixel` is the only one of the six that declares
          // it, so this is a *luminance* mask (hidden-state #22), filled
          // #FFFFFF where luminance and alpha both come to 1.
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
        attributes: const [SvgAttribute('mask', 'url(#mask__bauhaus)')],
        children: [
          // The background. Element 0 contributes its colour and nothing else.
          SvgNode(
            SvgElement.rect,
            attributes: [
              const SvgAttribute('width', _size),
              const SvgAttribute('height', _size),
              if (properties[0].color != null)
                SvgAttribute('fill', properties[0].color!),
            ],
          ),
          // The bar. `width` is the full 80 at `x = 10`, so it overhangs the
          // drawing space by 10 before the transform even applies — the mask is
          // what cuts it.
          SvgNode(
            SvgElement.rect,
            attributes: [
              const SvgAttribute('x', (_size - 60) ~/ 2),
              const SvgAttribute('y', (_size - 20) ~/ 2),
              const SvgAttribute('width', _size),
              SvgAttribute(
                'height',
                properties[1].isSquare ? _size : _size ~/ 8,
              ),
              if (properties[1].color != null)
                SvgAttribute('fill', properties[1].color!),
              SvgAttribute('transform', _translateRotate(properties[1])),
            ],
          ),
          // The disc. `cx cy fill r transform` — the attribute order is this
          // call site's, and it differs from `ring`'s circle (hidden-state #18).
          SvgNode(
            SvgElement.circle,
            attributes: [
              const SvgAttribute('cx', _size ~/ 2),
              const SvgAttribute('cy', _size ~/ 2),
              if (properties[2].color != null)
                SvgAttribute('fill', properties[2].color!),
              const SvgAttribute('r', _size ~/ 5),
              SvgAttribute(
                'transform',
                'translate(${jsNum(properties[2].translateX)} '
                    '${jsNum(properties[2].translateY)})',
              ),
            ],
          ),
          // The rule. No `fill` at any point — the colour is the stroke.
          SvgNode(
            SvgElement.line,
            attributes: [
              const SvgAttribute('x1', 0),
              const SvgAttribute('y1', _size ~/ 2),
              const SvgAttribute('x2', _size),
              const SvgAttribute('y2', _size ~/ 2),
              const SvgAttribute('stroke-width', 2),
              if (properties[3].color != null)
                SvgAttribute('stroke', properties[3].color!),
              SvgAttribute('transform', _translateRotate(properties[3])),
            ],
          ),
        ],
      ),
    ],
  );
}
