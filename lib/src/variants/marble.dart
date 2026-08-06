/// The `marble` variant — a background and two blurred blobs, one of them
/// blended into what is under it.
///
/// **Sacred surface.** These values decide what a user's avatar looks like, and
/// after a release they cannot be corrected without changing it.
///
/// `marble` is upstream's default variant — an unknown `variant` prop degrades
/// to it from v1.3.0 onward — and it is the only one of the six that reaches
/// for a filter. Four things about it are worth stating up front:
///
/// * **Three elements are generated and all three are read, but not evenly.**
///   Element 0 contributes a colour and nothing else; its translation, rotation
///   and scale are computed and never used. Elements 1 and 2 each place a path.
/// * **Both paths are scaled by `properties[2].scale`.** The first path takes
///   its colour, translation and rotation from `properties[1]` and then its
///   scale from `properties[2]` — `avatar-marble.js:56`, where the neighbouring
///   five reads all say `[1]`. It reads as a copy-paste slip and it is
///   reproduced here because the reference is the specification; the value
///   differs from `properties[1].scale` on **11 of the 20 corpus names**, so it
///   is not a dormant curiosity. See the divergence ledger in
///   `docs/agents/theflow.md`.
/// * **The two paths do not share a filter, they share a filter *reference*.**
///   One `<filter id="prefix__filter0_f">` sits in `<defs>` and both paths point
///   at it, so each is blurred independently and each gets its own filter
///   region.
/// * **`scale` is a float sum and lands exactly on the literal.** `1.2 +
///   getUnit(n, 4) / 10` takes four values, and all four are bit-identical to
///   the doubles `1.2`, `1.3`, `1.4` and `1.5` — measured, both bit patterns
///   compared. So the emitted attribute is two significant digits and no
///   `1.3000000000000003` can appear. Valid **as long as the range stays
///   `SIZE / 20`**; a range that let `getUnit` return more than 3 would have to
///   be re-measured.
library;

import '../js/js_number.dart';
import '../js/utilities.dart';
import '../scene/scene.dart';

/// The viewBox is a per-variant constant upstream. `marble` uses 80.
const int _size = 80;

/// How many property sets `generateColors` builds.
const int _elements = 3;

/// The blob geometry, verbatim from `avatar-marble.js`. Two literal paths, not
/// generated — the only thing the name decides is where they land.
///
/// Both close with `z` as their last command, so hidden-state #34 (a subpath
/// after `z` welding onto the previous contour) stays inert here, and neither
/// contains an arc, so hidden-state #28 (F.6.5's negative radicand) does too.
const String _blobA =
    'M32.414 59.35L50.376 70.5H72.5v-71H33.728L26.5 13.381l19.057 27.08L32.414 '
    '59.35z';
const String _blobB =
    'M22.216 24L0 46.75l14.108 38.129L78 86l-3.081-59.276-22.378 4.005 12.972 '
    '20.186-23.35 27.395L22.215 24z';

/// One element's generated properties.
///
/// [translateX], [translateY] and [rotate] are unused for element 0, and
/// [scale] is unused for elements 0 **and 1** — see the library doc. [color] is
/// `null` where upstream produces `undefined`, which is every element when the
/// palette is empty.
class MarbleElement {
  const MarbleElement({
    required this.color,
    required this.translateX,
    required this.translateY,
    required this.scale,
    required this.rotate,
  });

  final String? color;
  final int translateX;
  final int translateY;

  /// `1.2 + getUnit(…, 4) / 10` — one of 1.2, 1.3, 1.4, 1.5.
  final double scale;

  final int rotate;
}

/// The three elements' properties, in upstream's order.
List<MarbleElement> marbleProperties(String name, List<String> colors) {
  final numFromName = jsHashCode(name);
  final range = colors.length;

  return List<MarbleElement>.generate(_elements, (i) {
    // `numFromName * (i + 1)` reaches ~6.4e9 at i == 2, which is exact in both
    // JavaScript's float64 and Dart's 64-bit int — no narrowing applies here,
    // unlike inside `hashCode` itself.
    final scaled = numFromName * (i + 1);
    return MarbleElement(
      color: jsGetRandomColor(numFromName + i, colors, range),
      translateX: jsGetUnit(scaled, _size ~/ 10, 1),
      translateY: jsGetUnit(scaled, _size ~/ 10, 2),
      // No index, so `getUnit` never negates: the addend is 0.0–0.3.
      scale: 1.2 + jsGetUnit(scaled, _size ~/ 20) / 10,
      // Index 1, so this one *can* negate: rotation is -359–359.
      rotate: jsGetUnit(scaled, 360, 1),
    );
  });
}

/// Upstream builds this attribute by concatenating numbers into a string, so it
/// is a string here too — the SVG backend emits it verbatim and the rasterizer
/// parses it back. Deriving a matrix at the scene seam and re-serialising it
/// would put the geometry in two places, which is what this seam prevents.
///
/// [placement] supplies the translation and the rotation; [scaleFrom] supplies
/// the scale, and upstream reads it from `properties[2]` for **both** paths.
/// The two parameters exist so that split is visible at the call site rather
/// than buried in an index.
String _placement(MarbleElement placement, MarbleElement scaleFrom) =>
    'translate(${jsNum(placement.translateX)} ${jsNum(placement.translateY)}) '
    'rotate(${jsNum(placement.rotate)} ${jsNum(_size ~/ 2)} '
    '${jsNum(_size ~/ 2)}) '
    'scale(${jsNum(scaleFrom.scale)})';

/// Builds the `marble` scene for upstream v1.6.1.
///
/// [size] lands on the `<svg>` element's width and height and reaches nothing
/// else. [square] drops the mask's corner radius, and upstream expresses that
/// by passing `undefined`, which makes React **omit the attribute** rather than
/// write a default.
SvgNode buildMarbleScene({
  required String name,
  required List<String> colors,
  required Object size,
  bool square = false,
}) {
  final properties = marbleProperties(name, colors);

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
      // 1.6.x has no `title` prop — the element is unconditional (#16).
      SvgNode(SvgElement.title, text: name),
      SvgNode(
        SvgElement.mask,
        attributes: const [
          SvgAttribute('id', 'mask__marble'),
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
        attributes: const [SvgAttribute('mask', 'url(#mask__marble)')],
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
          // The first blob. Placed by element 1, scaled by element 2.
          SvgNode(
            SvgElement.path,
            attributes: [
              const SvgAttribute('filter', 'url(#prefix__filter0_f)'),
              const SvgAttribute('d', _blobA),
              if (properties[1].color != null)
                SvgAttribute('fill', properties[1].color!),
              SvgAttribute(
                'transform',
                _placement(properties[1], properties[2]),
              ),
            ],
          ),
          // The second blob. `style` is React's object prop serialised — the
          // property name hyphenates, and it is the only inline style in the
          // package.
          SvgNode(
            SvgElement.path,
            attributes: [
              const SvgAttribute('filter', 'url(#prefix__filter0_f)'),
              const SvgAttribute('style', 'mix-blend-mode:overlay'),
              const SvgAttribute('d', _blobB),
              if (properties[2].color != null)
                SvgAttribute('fill', properties[2].color!),
              SvgAttribute(
                'transform',
                _placement(properties[2], properties[2]),
              ),
            ],
          ),
        ],
      ),
      // `<defs>` sits *outside* the masked group and holds the paint the drawn
      // shapes reference — hidden-state #40, which cost `sunset` a whole
      // variant's worth of blank renders before it was read.
      SvgNode(
        SvgElement.defs,
        children: [
          SvgNode(
            SvgElement.filter,
            attributes: const [
              SvgAttribute('id', 'prefix__filter0_f'),
              // No x/y/width/height, so the region takes the spec's defaults.
              SvgAttribute('filterUnits', 'userSpaceOnUse'),
              SvgAttribute('color-interpolation-filters', 'sRGB'),
            ],
            children: const [
              // A fully transparent flood, blended under the source, and then
              // blurred. The first two primitives leave the source graphic
              // unchanged; only the blur reaches the picture.
              SvgNode(
                SvgElement.feFlood,
                attributes: [
                  SvgAttribute('flood-opacity', 0),
                  SvgAttribute('result', 'BackgroundImageFix'),
                ],
              ),
              SvgNode(
                SvgElement.feBlend,
                attributes: [
                  SvgAttribute('in', 'SourceGraphic'),
                  SvgAttribute('in2', 'BackgroundImageFix'),
                  SvgAttribute('result', 'shape'),
                ],
              ),
              // No `in`, so it takes the previous primitive's result.
              SvgNode(
                SvgElement.feGaussianBlur,
                attributes: [
                  SvgAttribute('stdDeviation', 7),
                  SvgAttribute('result', 'effect1_foregroundBlur'),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
