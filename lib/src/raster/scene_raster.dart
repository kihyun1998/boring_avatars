/// Turns a scene into pixels.
///
/// The rasterizer reads scene nodes **by attribute name**, never by position,
/// which is what lets the SVG emitter depend on attribute *order* without that
/// ordering leaking down here. This file is where that claim is cashed.
///
/// It handles what `pixel`, `ring`, `sunset`, `bauhaus` and `beam` need — a
/// rounded-rect mask over axis-aligned and rounded rectangles, filled and
/// stroked paths, circles, cubics, gradient paint servers,
/// `translate`/`rotate`/`scale` transforms composed down through `<g>`, and a
/// stroked `<line>`. Filters, `matrix`/`skew`, quadratics and
/// `stroke-linecap: square` arrive with the variants that use them, and
/// **everything else throws**. That is the point of
/// [UnsupportedSceneError]: an unhandled `<line>` rendering as blank, or a
/// `transform` being ignored so a rect lands square and unrotated, is a
/// plausible *wrong picture* — and a golden would freeze it. A loud failure at
/// the seam is the only thing that stops the next variant from shipping a
/// silently incorrect image.
library;

import '../scene/scene.dart';
import 'path.dart';
import 'raster.dart';
import 'transform.dart';

export 'raster.dart' show UnsupportedSceneError;

/// The attributes each drawn element understands.
///
/// Anything else changes the picture, so meeting one is a failure rather than
/// something to skip. `fill-rule` is absent from every list on purpose: it is a
/// capability, not a decoration, and no version in scope overrides the nonzero
/// default.
///
/// `stroke` is on `<rect>` because `beam`'s eyes declare it — always as `none`,
/// so it never paints. Reading it is not the same as honouring it: a `<rect>`
/// whose `stroke` would actually paint throws below, because outlining a
/// rounded rectangle is a real capability and nothing in the six asks for one.
const _drawableAttributes = <SvgElement, Set<String>>{
  SvgElement.rect: {
    'x',
    'y',
    'width',
    'height',
    'rx',
    'ry',
    'fill',
    'stroke',
    'transform',
  },
  SvgElement.path: {
    'd',
    'fill',
    'stroke',
    'stroke-width',
    'stroke-linecap',
    'transform',
  },
  SvgElement.circle: {'cx', 'cy', 'r', 'fill', 'transform'},
  // A `<line>` has no interior to fill: its colour arrives through `stroke`,
  // whose initial value is `none` — so an empty palette, which makes upstream
  // omit the attribute, draws nothing without needing any other declaration.
  SvgElement.line: {
    'x1',
    'y1',
    'x2',
    'y2',
    'stroke-width',
    'stroke',
    'transform',
  },
};

/// The attributes each **container** understands.
///
/// A container carries no geometry of its own, which is exactly why it was
/// tempting to walk through it unchecked — and why doing so was wrong. `beam`
/// wraps its whole face in `<g transform="translate(4.5 4.5) rotate(-9 18 18)">`
/// and an unchecked container renders that face 4.5 units off and unrotated,
/// with nothing thrown. Same failure this file's doc opens with, one level up.
const _containerAttributes = <SvgElement, Set<String>>{
  SvgElement.svg: {'viewBox', 'fill', 'role', 'xmlns', 'width', 'height'},
  // `transform` on a `<g>` is `beam`'s face wrapper. It is on this list only
  // because [_collectShapes] now **composes** it into every descendant — an
  // allow-list entry for a transform nobody applied would render the face 4.5
  // units off and unrotated with nothing thrown, which is hidden-state #30
  // exactly.
  SvgElement.g: {'mask', 'transform'},
  SvgElement.title: {},
};

/// `<defs>` and what it may hold. Nothing here is drawn in place — it is
/// referenced — but it decides what the drawn shapes look like, so it is
/// checked as strictly as they are.
const _defsAttributes = <SvgElement, Set<String>>{
  SvgElement.defs: {},
  SvgElement.linearGradient: {'id', 'x1', 'y1', 'x2', 'y2', 'gradientUnits'},
  SvgElement.stop: {'offset', 'stop-color'},
};

/// The `<mask>` element and its shape, which [_readMask] reads instead.
const _maskAttributes = {
  'id',
  'mask-type',
  'maskUnits',
  'x',
  'y',
  'width',
  'height',
};

/// Rasterises [root] at [width] × [height] device pixels.
///
/// Throws [UnsupportedSceneError] when the scene's `viewBox` does not match
/// those dimensions — scaling is a real capability and `ring` will need it
/// (its viewBox is 90 wide), so silently cropping is not an option.
RasterImage rasterizeScene(
  SvgNode root, {
  required int width,
  required int height,
}) {
  _checkViewBox(root, width, height);

  final maskNode = _firstOfKind(root, SvgElement.mask);
  if (maskNode == null) {
    throw UnsupportedSceneError('the scene has no <mask>');
  }
  final mask = _readMask(maskNode);
  // The paint servers are read before the shapes, because a shape's `fill` can
  // reference one — `sunset` paints both its halves that way.
  final paints = _readPaintServers(root);
  final shapes = <RasterShape>[];
  _collectShapes(
    root,
    shapes,
    insideMask: false,
    maskId: maskNode.attribute('id') as String?,
    paints: paints,
    inherited: Affine.identity,
  );

  return rasterizeMaskedShapes(
    width: width,
    height: height,
    shapes: shapes,
    mask: mask,
  );
}

void _checkViewBox(SvgNode root, int width, int height) {
  final viewBox = root.attribute('viewBox');
  if (viewBox is! String) {
    throw UnsupportedSceneError('the root <svg> has no viewBox');
  }
  final parts = viewBox.split(' ').map(double.tryParse).toList();
  if (parts.length != 4 || parts.contains(null)) {
    throw UnsupportedSceneError('unreadable viewBox "$viewBox"');
  }
  if (parts[0] != 0 || parts[1] != 0) {
    throw UnsupportedSceneError('a non-zero viewBox origin needs a transform');
  }
  if (parts[2] != width || parts[3] != height) {
    throw UnsupportedSceneError(
      'viewBox is ${parts[2]}x${parts[3]} but the target is ${width}x$height; '
      'scaling is not implemented',
    );
  }
}

/// Reads the `<mask>`'s single rect into a mask description.
///
/// Everything is looked up by name — `x`, `y`, `width`, `height`, `rx` — so a
/// call site that writes them in a different order rasterises identically.
RoundedRectMask _readMask(SvgNode maskNode) {
  // `pixel` declares mask-type="alpha"; the other five declare nothing, which
  // in SVG means a *luminance* mask. Every mask shape in the six is filled
  // #FFFFFF, where luminance and alpha both come to 1 — so the distinction is
  // inert today. It is checked rather than assumed: see hidden-state #22.
  for (final a in maskNode.attributes) {
    if (!_maskAttributes.contains(a.name)) {
      throw UnsupportedSceneError(
        '<mask ${a.name}="…"> is not implemented and would change the picture '
        'if ignored',
      );
    }
  }

  final maskType = maskNode.attribute('mask-type');
  if (maskType != null && maskType != 'alpha') {
    throw UnsupportedSceneError('mask-type "$maskType" is not implemented');
  }

  // `maskUnits` decides whether the region numbers below are user units or
  // fractions of the bounding box. All six declare `userSpaceOnUse`, and the
  // other value would silently reinterpret every one of them.
  final maskUnits = maskNode.attribute('maskUnits');
  if (maskUnits != null && maskUnits != 'userSpaceOnUse') {
    throw UnsupportedSceneError('maskUnits "$maskUnits" is not implemented');
  }

  final shapes = maskNode.children
      .where((c) => c.element != SvgElement.title)
      .toList();
  if (shapes.length != 1 || shapes.single.element != SvgElement.rect) {
    throw UnsupportedSceneError(
      'expected a <mask> holding one <rect>, found '
      '${shapes.map((s) => s.element.tag).join(", ")}',
    );
  }
  final rect = shapes.single;

  final fill = rect.attribute('fill');
  if (maskType == null && fill != '#FFFFFF') {
    throw UnsupportedSceneError(
      'a luminance mask filled "$fill" is not implemented; only #FFFFFF, '
      'where luminance and alpha agree',
    );
  }

  final shape = RoundedRectMask(
    x: _num(rect.attribute('x')) ?? 0,
    y: _num(rect.attribute('y')) ?? 0,
    width: _num(rect.attribute('width'))!,
    height: _num(rect.attribute('height'))!,
    // An absent `rx` is a square corner, not a default radius — upstream
    // expresses `square: true` by omitting the attribute entirely.
    rx: _num(rect.attribute('rx')) ?? 0,
  );

  // `<mask>` carries its own clip region, and anything the shape puts outside
  // it is cut. Reading the shape and ignoring the region works only while the
  // two agree, which they do in all six — so it is checked rather than assumed.
  final regionX = _num(maskNode.attribute('x')) ?? 0;
  final regionY = _num(maskNode.attribute('y')) ?? 0;
  final regionW = _num(maskNode.attribute('width'));
  final regionH = _num(maskNode.attribute('height'));
  if (regionW != null && regionH != null) {
    final clips =
        regionX > shape.x ||
        regionY > shape.y ||
        regionX + regionW < shape.x + shape.width ||
        regionY + regionH < shape.y + shape.height;
    if (clips) {
      throw UnsupportedSceneError(
        'the <mask> region ($regionX $regionY $regionW $regionH) cuts its own '
        'shape; clipping the mask is not implemented',
      );
    }
  }

  return shape;
}

/// Collects the shapes that are actually drawn — the ones under the masked
/// group, not the one that defines the mask.
///
/// Shapes come out in document order, which is paint order.
///
/// **Every element on the walk is checked, containers included.** An element
/// this rasterizer cannot fully honour is a failure wherever it sits: the point
/// is not that shapes are hard and containers are easy, it is that anything
/// ignored becomes a picture nobody was asked about.
void _collectShapes(
  SvgNode node,
  List<RasterShape> out, {
  required bool insideMask,
  required String? maskId,
  required Map<String, RasterPaint> paints,
  required Affine inherited,
}) {
  // `<mask>` is read by _readMask and `<defs>` by _readPaintServers — neither
  // is drawn where it sits. Both are validated there, not skipped: reading
  // `<defs>` as "not drawn, so not interesting" is what made every `sunset`
  // render come out blank.
  if (node.element == SvgElement.mask || node.element == SvgElement.defs) {
    return;
  }

  final drawable = _drawableAttributes[node.element];
  final container = _containerAttributes[node.element];
  if (drawable == null && container == null) {
    throw UnsupportedSceneError(
      '<${node.element.tag}> is not implemented; only '
      '${_drawableAttributes.keys.map((e) => "<${e.tag}>").join(", ")} '
      'are drawn so far',
    );
  }

  for (final a in node.attributes) {
    if (!(drawable ?? container!).contains(a.name)) {
      throw UnsupportedSceneError(
        '<${node.element.tag} ${a.name}="…"> is not implemented and would '
        'change the picture if ignored',
      );
    }
  }

  if (drawable != null) {
    if (!insideMask) {
      // Every drawn element in the six sits under `<g mask="url(#…)">`. One
      // that does not would be dropped here without a word, which is the same
      // silent-wrong-picture failure as ignoring an attribute.
      throw UnsupportedSceneError(
        '<${node.element.tag}> is drawn outside a masked group; only masked '
        'content is rasterised',
      );
    }
    out.addAll(_shapesOf(node, paints, inherited));
    return;
  }

  // §7.5: nesting is how a transform list is *defined*, so an ancestor's
  // transform composes with the descendant's exactly as two functions in one
  // list do — the ancestor applies second, because the child's coordinates are
  // in the child's own space. `beam` is the only variant with a transformed
  // container, and it puts its whole face inside one.
  final ownTransform = node.attribute('transform');
  if (ownTransform != null && ownTransform is! String) {
    throw UnsupportedSceneError(
      '<${node.element.tag}> has an unreadable `transform`',
    );
  }
  final matrix = ownTransform == null
      ? inherited
      : inherited.multiply(parseTransform(ownTransform as String));

  // A `mask="url(#…)"` that names something else is not a masked group. SVG 1.1
  // says a broken reference renders nothing; SVG 2 says render unmasked. Either
  // way, treating it as *our* mask draws a picture no browser produces — so the
  // reference is matched rather than merely noticed.
  final reference = node.attribute('mask') as String?;
  if (reference != null && reference != 'url(#$maskId)') {
    throw UnsupportedSceneError(
      '<${node.element.tag} mask="$reference"> does not reference the scene\'s '
      'only mask, "$maskId"',
    );
  }

  final within = insideMask || reference != null;
  for (final child in node.children) {
    _collectShapes(
      child,
      out,
      insideMask: within,
      maskId: maskId,
      paints: paints,
      inherited: matrix,
    );
  }
}

/// Reads every `<defs>` into paint servers, keyed by id.
///
/// `<defs>` holds nothing that is drawn where it sits, which made it tempting
/// to skip — and skipping it is why every `sunset` render came out blank before
/// #40: the shapes referenced paint that had never been read.
Map<String, RasterPaint> _readPaintServers(SvgNode root) {
  final out = <String, RasterPaint>{};

  void walk(SvgNode node) {
    if (node.element == SvgElement.defs) {
      _checkAttributes(node, _defsAttributes[SvgElement.defs]!);
      for (final child in node.children) {
        final allowed = _defsAttributes[child.element];
        if (allowed == null) {
          throw UnsupportedSceneError(
            '<defs> holds <${child.element.tag}>, which is not implemented',
          );
        }
        _checkAttributes(child, allowed);
        if (child.element != SvgElement.linearGradient) {
          throw UnsupportedSceneError(
            '<${child.element.tag}> is not a paint server this rasterizer '
            'reads',
          );
        }
        final id = child.attribute('id');
        if (id is! String) {
          throw UnsupportedSceneError('a <linearGradient> has no id');
        }
        out[id] = _readLinearGradient(child);
      }
      return;
    }
    for (final child in node.children) {
      walk(child);
    }
  }

  walk(root);
  return out;
}

LinearGradientPaint _readLinearGradient(SvgNode node) {
  // `objectBoundingBox` — the SVG default — would reinterpret x1/y1/x2/y2 as
  // fractions of the shape's box. All six variants declare user space, and
  // reading the numbers under the other meaning silently rescales the paint.
  final units = node.attribute('gradientUnits');
  if (units != 'userSpaceOnUse') {
    throw UnsupportedSceneError(
      'gradientUnits "$units" is not implemented; only userSpaceOnUse',
    );
  }

  final stops = <(double, RasterColour)>[];
  for (final child in node.children) {
    _checkAttributes(child, _defsAttributes[SvgElement.stop]!);
    if (child.element != SvgElement.stop) {
      throw UnsupportedSceneError(
        '<linearGradient> holds <${child.element.tag}>, expected <stop>',
      );
    }
    // An absent `offset` is 0 and an absent `stop-color` is **black** — both
    // are SVG's initial values, and the second is what makes an empty palette
    // paint `sunset` solid black instead of transparent. Confirmed in Chrome.
    //
    // The same four states a `fill` reads, answered differently on purpose.
    // `stop-color` takes `currentColor | <color> <icccolor> | inherit` (SVG
    // 1.1, 13.2.4) and **`none` is not in that grammar**, where for `<paint>`
    // it is the first alternative — so the value that means "no paint" over
    // there is an invalid value here. It cannot mean "no paint" anyway: a
    // gradient stop has no such state, only a colour.
    final offset = _num(child.attribute('offset')) ?? 0;
    final declared = child.attribute('stop-color') as String?;
    final colour = switch (readColourDeclaration(declared)) {
      AbsentColour() => const RasterColour(0, 0, 0),
      ParsedColour(:final colour) => colour,
      NoneColour() => throw UnsupportedSceneError(
        'stop-color "none" is not in this property\'s grammar; `none` is a '
        '<paint> value and a <stop> has no "do not paint" state',
      ),
      // Chrome paints an unreadable `stop-color` **black**, not nothing —
      // measured. Refusing rather than guessing is today's answer and #64 is
      // where it is taken, together with `fill`'s.
      UnreadableColour(:final text) => throw UnsupportedSceneError(
        'stop-color "$text" is not a colour this rasterizer can read',
      ),
    };
    stops.add((offset, colour));
  }
  if (stops.isEmpty) {
    throw UnsupportedSceneError('a <linearGradient> has no stops');
  }

  return LinearGradientPaint(
    x1: _num(node.attribute('x1')) ?? 0,
    y1: _num(node.attribute('y1')) ?? 0,
    x2: _num(node.attribute('x2')) ?? 0,
    y2: _num(node.attribute('y2')) ?? 0,
    stops: stops,
  );
}

void _checkAttributes(SvgNode node, Set<String> allowed) {
  for (final a in node.attributes) {
    if (!allowed.contains(a.name)) {
      throw UnsupportedSceneError(
        '<${node.element.tag} ${a.name}="…"> is not implemented and would '
        'change the picture if ignored',
      );
    }
  }
}

/// Turns one drawn element into the shapes it paints, reading its attributes
/// **by name**.
///
/// **One element can paint twice.** `beam`'s open mouth is a `<path>` with both
/// a `stroke` and a `fill="none"`, and its closed mouth the same `<path>` with
/// a fill and no stroke — so this returns a list, in SVG's own painting order:
/// §11 fills first, then strokes. Returning a single shape forced a choice
/// between the two and would have dropped one of them silently.
List<RasterShape> _shapesOf(
  SvgNode node,
  Map<String, RasterPaint> paints,
  Affine inherited,
) {
  /// The paint the [attribute] names — `fill` or `stroke`.
  ///
  /// A `<funciri>` is resolved here and everything else goes through
  /// [readColourDeclaration], the vocabulary `<stop>` also reads. Five cases,
  /// and three of them paint nothing — by three different decisions, which no
  /// picture can tell apart and which therefore have to be written down:
  ///
  /// * **absent** — no paint. For `stroke` that is SVG's own initial value;
  ///   for `fill` the initial value is **black**, and what makes the absence
  ///   mean nothing is the root `<svg fill="none">` every one of the six
  ///   variants declares, inherited down (#17). Measured across all 600
  ///   renders in the fixture: the root's `fill` is `none` in every one. Valid
  ///   **as long as that stays true** — a scene whose root declared a colour
  ///   would paint every unfilled shape with it, and nothing here reads the
  ///   root to notice. Not reachable from any public entry point today, since
  ///   the scene is only ever built by this package's own variant builders.
  /// * **`none`** — no paint, because SVG says so: it is the first alternative
  ///   of `<paint>` (11.2). This is the one that used to be indistinguishable
  ///   from a parse failure, and `beam` is the only variant that writes it —
  ///   `<path fill="none">` on 44 of its 80 renders and `<rect stroke="none">`
  ///   160 times.
  /// * **`url(#…)`** — a paint server, and it must exist. A dangling reference
  ///   makes a browser draw **nothing** — measured, `0,0,0,0` at every pixel,
  ///   because a CSS `<url>` with no fallback and an invalid target has the
  ///   used value `none`. So resolving it to "no paint" would in fact agree
  ///   with Chrome; it throws anyway, because a blank avatar is
  ///   indistinguishable from the bug where the paint was never *read* — which
  ///   is exactly what #40 fixed, and it was silent for a whole variant.
  /// * **a colour** — `#RRGGBB` paints.
  /// * **unreadable** — a form only a browser can read (`red`, `#F00`) keeps
  ///   its recorded behaviour of painting nothing, which is hidden-state #20
  ///   and the caller's palette, not upstream's output. **#64 is where this
  ///   answer changes**; splitting it out of the two above is what lets it
  ///   change alone.
  RasterPaint? resolvePaint(String attribute) {
    final declared = node.attribute(attribute) as String?;
    if (declared != null && declared.startsWith('url(')) {
      final id = RegExp(r'^url\(#(.*)\)$').firstMatch(declared)?.group(1);
      final paint = id == null ? null : paints[id];
      if (paint == null) {
        throw UnsupportedSceneError(
          '<${node.element.tag} $attribute="$declared"> references a paint '
          'server that is not declared in any <defs>',
        );
      }
      return paint;
    }
    return switch (readColourDeclaration(declared)) {
      AbsentColour() => null,
      NoneColour() => null,
      ParsedColour(:final colour) => SolidPaint(colour),
      UnreadableColour() => null,
    };
  }

  final fill = resolvePaint('fill');

  /// The element's own `transform`, composed under everything it is nested in.
  ///
  /// SVG 1.1 §7.4 applies it *before* the element's coordinates are read, so
  /// the shape is built in its own space and every vertex is then mapped. §7.5
  /// makes nesting the *definition* of a transform list, so an ancestor's
  /// matrix multiplies on the left — [inherited] carries `beam`'s face group
  /// down to the mouth and the eyes.
  final declaredTransform = node.attribute('transform');
  if (declaredTransform != null && declaredTransform is! String) {
    throw UnsupportedSceneError(
      '<${node.element.tag}> has an unreadable `transform`',
    );
  }
  final matrix = declaredTransform == null
      ? inherited
      : inherited.multiply(parseTransform(declaredTransform as String));

  /// A geometry attribute the element cannot be drawn without.
  ///
  /// Missing means the scene is malformed, and a malformed scene has to fail
  /// the same loud way an unimplemented one does. A `!` here would surface as
  /// a null-check `_TypeError` — a crash that says nothing about which element
  /// was wrong, in a seam whose entire purpose is to say exactly that.
  double required(String name) {
    final value = _num(node.attribute(name));
    if (value == null) {
      throw UnsupportedSceneError(
        '<${node.element.tag}> has no readable `$name`',
      );
    }
    return value;
  }

  /// `stroke-width`, defaulting to SVG's initial value.
  ///
  /// §11.4 gives `stroke-width` an initial value of **1**, and `beam`'s open
  /// mouth is the first element in the six to rely on it — it declares
  /// `stroke-linecap` and no width at all. `<line>` deliberately keeps
  /// requiring one (below): `bauhaus` always writes it, so a default there
  /// would be arithmetic no test in this package could reach.
  double strokeWidth() => _num(node.attribute('stroke-width')) ?? 1;

  /// `stroke-linecap`, defaulting to §11.4's initial `butt`.
  StrokeCap strokeCap() => switch (node.attribute('stroke-linecap')) {
    null || 'butt' => StrokeCap.butt,
    'round' => StrokeCap.round,
    final other => throw UnsupportedSceneError(
      'stroke-linecap "$other" is not implemented; only butt and round, which '
      'are the only two any version in scope writes',
    ),
  };

  switch (node.element) {
    case SvgElement.rect:
      final x = _num(node.attribute('x')) ?? 0;
      final y = _num(node.attribute('y')) ?? 0;
      final width = required('width');
      final height = required('height');

      // `beam`'s eyes declare `stroke="none"`, which paints nothing — so the
      // attribute is read rather than refused. Anything that *would* paint is
      // a different matter: outlining a rounded rectangle is a real capability
      // and no version in scope asks for one, so it fails loudly here instead
      // of drawing a rect that is missing its outline.
      final declaredStroke = node.attribute('stroke');
      if (declaredStroke != null &&
          readColourDeclaration(declaredStroke as String) is! NoneColour) {
        throw UnsupportedSceneError(
          '<rect stroke="$declaredStroke"> would paint an outline, which is '
          'not implemented; only stroke="none" is read',
        );
      }

      // §9.2's corner radii. Present on `beam`'s wrapper (rx 36 or 6) and on
      // both eyes (rx 1 on a 1.5 x 2 box, which resolves to two *different*
      // radii — see [roundedRectContour]).
      final rx = _num(node.attribute('rx'));
      final ry = _num(node.attribute('ry'));
      if (rx != null || ry != null) {
        return [
          RasterPolygon([
            matrix.transformContour(
              roundedRectContour(x, y, width, height, rx, ry),
            ),
          ], fill),
        ];
      }

      // A pure translation leaves the rectangle axis-aligned, so it keeps the
      // closed-form integrator: a box-overlap product has nothing to
      // approximate, where the polygon path quantises the vertical direction
      // and a horizontal edge is exactly where that is worst. Anything that
      // rotates or scales it has to become a polygon, and then the
      // quantisation is moot because none of its edges are horizontal any more.
      if (matrix.isTranslationOnly) {
        return [RasterRect(x + matrix.e, y + matrix.f, width, height, fill)];
      }
      return [
        RasterPolygon([
          matrix.transformContour(rectangleContour(x, y, width, height)),
        ], fill),
      ];
    case SvgElement.path:
      final d = node.attribute('d');
      if (d is! String) {
        throw UnsupportedSceneError('<path> has no readable `d`');
      }
      final stroke = resolvePaint('stroke');
      return [
        // §11: the fill is painted first and the stroke on top of it. `beam`
        // never asks for both at once — the open mouth strokes and the closed
        // one fills — but the order is the spec's, not the variant's.
        if (fill != null)
          RasterPolygon([
            for (final contour in parsePath(d))
              matrix.transformContour(contour),
          ], fill),
        if (stroke != null)
          RasterPolygon([
            for (final contour in strokePathOutline(
              parsePathSubpaths(d),
              width: strokeWidth(),
              cap: strokeCap(),
            ))
              matrix.transformContour(contour),
          ], stroke),
      ];
    case SvgElement.circle:
      // Flatten first, then map. For a **rigid** transform that is exact.
      //
      // This comment used to end "…which is also why `scale` has to throw:
      // scaling after flattening would apply the tolerance in the wrong
      // space". `scale` no longer throws, and the rounded rect thirty lines
      // above does exactly what that sentence warned about — so the rule is
      // restated rather than left contradicting the code beside it.
      //
      // **What it actually costs, measured.** A scale of `s` multiplies the
      // flattening error by `s`. `beam`'s wrapper is the only scaled shape in
      // the six and its largest is 1.2, so the worst tolerance becomes
      // 1.2/4096 = 0.00029 user units against the ≤1/255 = 0.0039 coverage
      // bar — an order of magnitude of headroom. Pre-scaling the tolerance
      // would be exact and would move every golden for no visible gain, so it
      // is not done. Valid **as long as no variant scales by more than about
      // 13×**, at which point the flattening error reaches the coverage bar.
      return [
        RasterPolygon([
          matrix.transformContour(
            flattenCircle(
              _num(node.attribute('cx')) ?? 0,
              _num(node.attribute('cy')) ?? 0,
              required('r'),
            ),
          ),
        ], fill),
      ];
    case SvgElement.line:
      // The colour is the stroke, and there is no `fill` on the allow-list —
      // a `<line fill="…">` therefore throws one level up rather than being
      // silently painted with a property that has no interior to paint.
      final stroke = resolvePaint('stroke');
      final outline = strokeSegmentContour(
        _num(node.attribute('x1')) ?? 0,
        _num(node.attribute('y1')) ?? 0,
        _num(node.attribute('x2')) ?? 0,
        _num(node.attribute('y2')) ?? 0,
        // A `<line>` keeps *requiring* `stroke-width` where a `<path>` defaults
        // it to §11.4's initial 1. Not an inconsistency for its own sake: the
        // default is implemented once, in `strokeWidth()` above, and reached
        // only from the element that actually omits the attribute. `bauhaus`
        // always writes it, so a default here would be arithmetic no test in
        // this package could drive.
        required('stroke-width'),
      );
      return [
        RasterPolygon(
          outline == null ? const [] : [matrix.transformContour(outline)],
          stroke,
        ),
      ];
    default:
      throw UnsupportedSceneError(
        '<${node.element.tag}> has no shape conversion',
      );
  }
}

SvgNode? _firstOfKind(SvgNode node, SvgElement kind) {
  if (node.element == kind) return node;
  for (final child in node.children) {
    final found = _firstOfKind(child, kind);
    if (found != null) return found;
  }
  return null;
}

double? _num(Object? value) => switch (value) {
  null => null,
  final num n => n.toDouble(),
  final String s => double.tryParse(s),
  _ => null,
};
