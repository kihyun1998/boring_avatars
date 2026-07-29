/// The `sunset` variant — two stacked vertical gradients.
///
/// **Sacred surface.** These values decide what a user's avatar looks like, and
/// after a release they cannot be corrected without changing it.
///
/// Three things about this variant are surprising enough to state up front:
///
/// * **The gradient ids are derived from the name.** Upstream builds them as
///   `'gradient_paint0_linear_' + props.name.replace(/\s/g, '')`, so the
///   caller's name ends up inside an id — with whitespace stripped, and with
///   whatever escaping the attribute needs (`O'Brien` becomes `O&#x27;Brien`).
///   The parity fixture normalises ids away on both sides, so nothing in the
///   byte sweep checks this; `sunset_parity_test.dart` asserts it separately
///   against ids the harness recorded unnormalised.
/// * **An empty palette paints the avatar black, not transparent.** The other
///   five variants answer an empty palette by dropping `fill`, which draws
///   nothing. Here the `<stop>`s lose their `stop-color`, and SVG's initial
///   value for that is black. Confirmed in Chrome.
/// * **`<defs>` sits outside the masked group**, after it, and the drawn paths
///   reach it by reference. The rasterizer therefore cannot treat `<defs>` as
///   "not drawn and so not interesting" — it holds the paint.
library;

import '../js/utilities.dart';
import '../scene/scene.dart';

/// The viewBox is a per-variant constant upstream.
const int _size = 80;

/// How many colours `generateColors` draws — two stops for each of two
/// gradients.
const int _elements = 4;

/// The two halves, as `d` strings. Literals upstream, so literals here.
const String _topHalf = 'M0 0h80v40H0z';
const String _bottomHalf = 'M0 40h80v40H0z';

/// The four stop colours, or `null` where upstream produces `undefined`.
///
/// The same consecutive walk `ring` uses — `getRandomColor(hash + i, …)` for
/// `i` in 0–3, not four independent draws.
List<String?> sunsetColors(String name, List<String> colors) {
  final numFromName = jsHashCode(name);
  final range = colors.length;
  return List<String?>.generate(
    _elements,
    (i) => jsGetRandomColor(numFromName + i, colors, range),
  );
}

/// The name as it appears inside the gradient ids.
///
/// `props.name.replace(/\s/g, '')`. Dart's `\s` matches exactly the same 25
/// code points as JavaScript's — measured, U+0009 through U+FEFF, both being
/// ECMAScript's WhiteSpace plus LineTerminator — so this is a straight
/// translation rather than an approximation. Valid **as long as both stay on
/// that definition**; a Dart release that widened `\s` would silently rename
/// every gradient.
String sunsetIdName(String name) => name.replaceAll(RegExp(r'\s'), '');

/// Builds the `sunset` scene for upstream v1.6.1.
SvgNode buildSunsetScene({
  required String name,
  required List<String> colors,
  required Object size,
  bool square = false,
}) {
  final stops = sunsetColors(name, colors);
  final idName = sunsetIdName(name);
  final topId = 'gradient_paint0_linear_$idName';
  final bottomId = 'gradient_paint1_linear_$idName';

  SvgNode gradient(String id, num y1, num y2, String? from, String? to) =>
      SvgNode(
        SvgElement.linearGradient,
        attributes: [
          SvgAttribute('id', id),
          const SvgAttribute('x1', _size / 2),
          SvgAttribute('y1', y1),
          const SvgAttribute('x2', _size / 2),
          SvgAttribute('y2', y2),
          const SvgAttribute('gradientUnits', 'userSpaceOnUse'),
        ],
        children: [
          // The first stop carries no `offset` — upstream omits it, and SVG's
          // initial value is 0. The second is explicit.
          SvgNode(
            SvgElement.stop,
            attributes: [if (from != null) SvgAttribute('stop-color', from)],
          ),
          SvgNode(
            SvgElement.stop,
            attributes: [
              const SvgAttribute('offset', 1),
              if (to != null) SvgAttribute('stop-color', to),
            ],
          ),
        ],
      );

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
      // 1.6.x has no `title` prop — the element is unconditional (#16). It
      // carries the **raw** name, not the whitespace-stripped one.
      SvgNode(SvgElement.title, text: name),
      SvgNode(
        SvgElement.mask,
        attributes: const [
          SvgAttribute('id', 'mask__sunset'),
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
        attributes: const [SvgAttribute('mask', 'url(#mask__sunset)')],
        children: [
          // `fill` before `d` here. `ring` writes the same element the other
          // way round — the order is the call site's, not the element's (#18).
          SvgNode(
            SvgElement.path,
            attributes: [
              SvgAttribute('fill', 'url(#$topId)'),
              const SvgAttribute('d', _topHalf),
            ],
          ),
          SvgNode(
            SvgElement.path,
            attributes: [
              SvgAttribute('fill', 'url(#$bottomId)'),
              const SvgAttribute('d', _bottomHalf),
            ],
          ),
        ],
      ),
      SvgNode(
        SvgElement.defs,
        children: [
          gradient(topId, 0, _size / 2, stops[0], stops[1]),
          gradient(bottomId, _size / 2, _size, stops[2], stops[3]),
        ],
      ),
    ],
  );
}
