/// The `beam` variant — a face on a rotated, scaled, rounded card.
///
/// **Sacred surface.** These values decide what a user's avatar looks like, and
/// after a release they cannot be corrected without changing it.
///
/// Five things about this variant are worth stating up front:
///
/// * **Its drawing space is 36, not 80.** Every other variant in the six is 80
///   and `ring` is 90. `size` still only reaches `width`/`height`, so the
///   *display* size is unchanged — but every coordinate here is on a 36-unit
///   canvas, and a golden generated at 80 would be a different picture.
///   Hidden-state #26 recorded this the wrong way round until #38 measured it.
/// * **It is the only variant that can fail on the caller's palette.** The face
///   colour comes from `getContrast(wrapperColor)`, and an empty palette makes
///   `wrapperColor` `undefined`, on which upstream calls `.slice` and throws.
///   The other five degrade by dropping an attribute. See [beamProperties].
/// * **Two of its fields are conditionally corrected, and the correction is not
///   symmetric with the test.** `preTranslateX < 5 ? preTranslateX + SIZE / 9`
///   nudges *small* values up by 4 and leaves the rest alone — so the value 5
///   is reachable two ways (as itself, and never from 1) and the distribution
///   has a step in it. Reading the ternary the other way round moves every
///   avatar whose hash lands under the threshold.
/// * **The mouth is two different elements, not one element with two fills.**
///   Open is a *stroked cubic* with `fill="none"`; closed is a *filled arc*
///   whose radii are too small for its own chord and are corrected by F.6.6.
///   They share no attributes: `d stroke fill stroke-linecap` against `d fill`.
/// * **The eyes are ellipses.** `1.5 × 2` with `rx="1"` resolves under §9.2 to
///   `rx` 0.75 and `ry` 1 — each clamped against its own side — and since those
///   are exactly half the width and half the height, the straight edges vanish.
library;

import '../js/js_number.dart';
import '../js/utilities.dart';
import '../scene/scene.dart';

/// The viewBox is a per-variant constant upstream. `beam` uses **36**.
const int _size = 36;

/// `beam`'s generated values, in upstream's own order.
///
/// Every field is one line of `generateData` in `avatar-beam.js`.
class BeamProperties {
  const BeamProperties({
    required this.wrapperColor,
    required this.faceColor,
    required this.backgroundColor,
    required this.wrapperTranslateX,
    required this.wrapperTranslateY,
    required this.wrapperRotate,
    required this.wrapperScale,
    required this.isMouthOpen,
    required this.isCircle,
    required this.eyeSpread,
    required this.mouthSpread,
    required this.faceRotate,
    required this.faceTranslateX,
    required this.faceTranslateY,
  });

  /// The card's colour.
  final String wrapperColor;

  /// Black or white, whichever reads on [wrapperColor].
  final String faceColor;

  final String backgroundColor;

  /// Integer-valued: `getUnit` returns an integer and `SIZE / 9` is exactly 4.
  final int wrapperTranslateX;
  final int wrapperTranslateY;

  /// 0–359. No index, so `getUnit` never negates it.
  final int wrapperRotate;

  /// 1, 1.1 or 1.2 — `1 + getUnit(n, 3) / 10`.
  final double wrapperScale;

  final bool isMouthOpen;

  /// Whether the card is a circle: `rx` becomes the whole size rather than a
  /// sixth of it, and §9.2's clamp then makes it a disc.
  final bool isCircle;

  final int eyeSpread;
  final int mouthSpread;
  final int faceRotate;

  /// A `num`, not an `int`: the halving branch produces `.5` values.
  final num faceTranslateX;
  final num faceTranslateY;
}

/// `beam`'s values for [name] under [colors].
///
/// **Throws on an empty palette, and that is upstream's behaviour rather than a
/// choice about robustness.** `getRandomColor(hash, [], 0)` indexes with `NaN`
/// and yields `undefined`; `getContrast` then calls `.slice(0, 1)` on it and
/// JavaScript raises a `TypeError`. Measured across the whole corpus: 20 names
/// × the empty palette, 20 throws, and **zero** throws from the other five
/// variants on the same input (hidden-state #8). The fixture records it as
/// `{"__throws": "TypeError"}`.
///
/// The exception is an [ArgumentError] rather than an imitation of a JS
/// `TypeError`: what a caller can observe is *that this input fails*, and that
/// is reproduced exactly. The shape of the failure is a Dart API decision, and
/// upstream's is an accident of a dynamic language rather than a designed
/// contract. **Decided by the user on 2026-08-06**, shown all three options and
/// what each costs — recorded as an event in the divergence ledger, and theirs
/// to reverse.
BeamProperties beamProperties(String name, List<String> colors) {
  final numFromName = jsHashCode(name);
  final range = colors.length;

  final wrapperColor = jsGetRandomColor(numFromName, colors, range);
  if (wrapperColor == null) {
    throw ArgumentError.value(
      colors,
      'colors',
      'beam derives its face colour from the palette, so an empty one has no '
          'avatar to produce — upstream raises a TypeError here for the same '
          'reason. The other five variants degrade instead',
    );
  }

  // `SIZE / 9` is exactly 4, `SIZE / 6` exactly 6 and `SIZE / 12` exactly 3 in
  // float64, so the integer arithmetic below is provably the same value
  // JavaScript computes — the divisions are written out rather than folded so
  // that stays checkable against the reference.
  const nudge = _size ~/ 9; // 4
  const faceThreshold = _size ~/ 6; // 6

  final preTranslateX = jsGetUnit(numFromName, 10, 1);
  final wrapperTranslateX = preTranslateX < 5
      ? preTranslateX + nudge
      : preTranslateX;
  final preTranslateY = jsGetUnit(numFromName, 10, 2);
  final wrapperTranslateY = preTranslateY < 5
      ? preTranslateY + nudge
      : preTranslateY;

  return BeamProperties(
    wrapperColor: wrapperColor,
    faceColor: jsGetContrast(wrapperColor),
    // Non-null by derivation, not by hope: `range` is at least 1 here — the
    // guard above is the only way it can be 0 — and `jsMod` of a non-negative
    // `hashCode` is in `[0, range)`, which is in bounds. The `!` is safe for
    // exactly as long as `hashCode` stays `Math.abs`'d.
    backgroundColor: jsGetRandomColor(numFromName + 13, colors, range)!,
    wrapperTranslateX: wrapperTranslateX,
    wrapperTranslateY: wrapperTranslateY,
    wrapperRotate: jsGetUnit(numFromName, 360),
    // Float division, as upstream writes it: `1 + 1/10` is 1.1 and prints as
    // "1.1". An integer division would give 1 for every name.
    wrapperScale: 1 + jsGetUnit(numFromName, _size ~/ 12) / 10,
    isMouthOpen: jsGetBoolean(numFromName, 2),
    isCircle: jsGetBoolean(numFromName, 1),
    eyeSpread: jsGetUnit(numFromName, 5),
    mouthSpread: jsGetUnit(numFromName, 3),
    faceRotate: jsGetUnit(numFromName, 10, 3),
    // The face follows the card only when the card moved far enough, and then
    // by *half* as much. Below the threshold it gets its own unrelated value —
    // note the different ranges, 8 and 7, and the different digit indices.
    faceTranslateX: wrapperTranslateX > faceThreshold
        ? wrapperTranslateX / 2
        : jsGetUnit(numFromName, 8, 1),
    faceTranslateY: wrapperTranslateY > faceThreshold
        ? wrapperTranslateY / 2
        : jsGetUnit(numFromName, 7, 2),
  );
}

/// Upstream concatenates these numbers into a string, so the scene carries the
/// *string* and the rasterizer parses it back — the seam that keeps one copy of
/// the placement. See `transform.dart`.
String _wrapperTransform(BeamProperties p) =>
    'translate(${jsNum(p.wrapperTranslateX)} ${jsNum(p.wrapperTranslateY)}) '
    'rotate(${jsNum(p.wrapperRotate)} ${jsNum(_size / 2)} '
    '${jsNum(_size / 2)}) scale(${jsNum(p.wrapperScale)})';

String _faceTransform(BeamProperties p) =>
    'translate(${jsNum(p.faceTranslateX)} ${jsNum(p.faceTranslateY)}) '
    'rotate(${jsNum(p.faceRotate)} ${jsNum(_size / 2)} ${jsNum(_size / 2)})';

/// Builds the `beam` scene for upstream v1.6.1.
///
/// [size] lands on the `<svg>` element's width and height and reaches nothing
/// else — the drawing is on a 36-unit canvas whatever it says. [square] drops
/// the mask's corner radius, which upstream expresses by passing `undefined` so
/// that React omits the attribute rather than writing a default.
SvgNode buildBeamScene({
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
  final p = beamProperties(name, colors);

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
          SvgAttribute('id', 'mask__beam'),
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
        attributes: const [SvgAttribute('mask', 'url(#mask__beam)')],
        children: [
          // The background.
          SvgNode(
            SvgElement.rect,
            attributes: [
              const SvgAttribute('width', _size),
              const SvgAttribute('height', _size),
              SvgAttribute('fill', p.backgroundColor),
            ],
          ),
          // The card. `x y width height transform fill rx` — this call site's
          // order, and it is not the eyes' order even though both are `<rect>`
          // (hidden-state #18). `x` and `y` are string literals `"0"` in the
          // JSX and emit as `0` either way.
          SvgNode(
            SvgElement.rect,
            attributes: [
              const SvgAttribute('x', 0),
              const SvgAttribute('y', 0),
              const SvgAttribute('width', _size),
              const SvgAttribute('height', _size),
              SvgAttribute('transform', _wrapperTransform(p)),
              SvgAttribute('fill', p.wrapperColor),
              // §9.2 clamps this to half the side, so `_size` turns the card
              // into a disc — the same trick `pixel` plays on its mask with
              // rx=160 on 80.
              SvgAttribute('rx', p.isCircle ? _size : _size ~/ 6),
            ],
          ),
          SvgNode(
            SvgElement.g,
            attributes: [SvgAttribute('transform', _faceTransform(p))],
            children: [
              if (p.isMouthOpen)
                // A stroked cubic. No `stroke-width`, so §11.4's initial 1
                // applies, and `fill="none"` is SVG's own "no paint" keyword
                // rather than a colour that failed to parse (ADR-0001).
                SvgNode(
                  SvgElement.path,
                  attributes: [
                    SvgAttribute(
                      'd',
                      'M15 ${jsNum(19 + p.mouthSpread)}c2 1 4 1 6 0',
                    ),
                    SvgAttribute('stroke', p.faceColor),
                    const SvgAttribute('fill', 'none'),
                    const SvgAttribute('stroke-linecap', 'round'),
                  ],
                )
              else
                // A filled arc whose radii cannot span its own chord: rx 1 and
                // ry 0.75 over a chord of 10. F.6.6 step 3 scales both by
                // sqrt(lambda) = 5, giving 5 and 3.75 — the first input in this
                // package that makes that correction fire at all.
                SvgNode(
                  SvgElement.path,
                  attributes: [
                    SvgAttribute(
                      'd',
                      'M13,${jsNum(19 + p.mouthSpread)} a1,0.75 0 0,0 10,0',
                    ),
                    SvgAttribute('fill', p.faceColor),
                  ],
                ),
              _eye(14 - p.eyeSpread, p.faceColor),
              _eye(20 + p.eyeSpread, p.faceColor),
            ],
          ),
        ],
      ),
    ],
  );
}

/// One eye. `x y width height rx stroke fill` — the eyes' own attribute order.
///
/// `stroke="none"` paints nothing and is read as SVG's keyword rather than as
/// an unreadable colour; the rasterizer refuses a `<rect>` stroke that *would*
/// paint, because outlining a rounded rectangle is a capability nothing here
/// has built.
SvgNode _eye(int x, String colour) => SvgNode(
  SvgElement.rect,
  attributes: [
    SvgAttribute('x', x),
    const SvgAttribute('y', 14),
    const SvgAttribute('width', 1.5),
    const SvgAttribute('height', 2),
    const SvgAttribute('rx', 1),
    const SvgAttribute('stroke', 'none'),
    SvgAttribute('fill', colour),
  ],
);
