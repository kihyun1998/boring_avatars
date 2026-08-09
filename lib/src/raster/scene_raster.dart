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

import 'dart:math' as math;

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
  // `filter` and `style` are `marble`'s, and both are on this list only
  // because they are now *applied* — an allow-list entry for an effect nobody
  // honours is hidden-state #30 exactly, and it is the cheap wrong fix every
  // time this seam fires.
  SvgElement.path: {
    'd',
    'fill',
    'stroke',
    'stroke-width',
    'stroke-linecap',
    'transform',
    'filter',
    'style',
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
  // `x`, `y`, `width` and `height` are read even though `marble` writes none of
  // them: the *default* region has to be resolved either way, and an explicit
  // one is the same arithmetic with the fallback skipped. Reading them is what
  // makes the clip testable — no variant produces a region that cuts anything.
  SvgElement.filter: {
    'id',
    'filterUnits',
    'color-interpolation-filters',
    'x',
    'y',
    'width',
    'height',
  },
  SvgElement.feFlood: {'flood-opacity', 'flood-color', 'result'},
  SvgElement.feBlend: {'in', 'in2', 'mode', 'result'},
  SvgElement.feGaussianBlur: {'in', 'stdDeviation', 'result'},
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

/// What the `<mask>`'s own `<rect>` may carry.
///
/// The mask element was allow-listed in #37 and **its child was not**, so a
/// `transform` or an `opacity` on the shape that defines the mask was read past
/// in silence. Measured before it was fixed: `<rect width="4" height="4"
/// transform="scale(2)">` inside the mask produced exactly the 4×4 coverage of
/// the untransformed rect, where a browser gives 8×8 — and `opacity="0.5"`
/// produced full coverage where a browser halves it. Two wrong pictures, no
/// throw, in the element that decides what the whole avatar is clipped to.
///
/// Same class as hidden-state #30, one level in: that row was about containers
/// on the *drawing* walk, and `<mask>` is read by a different function that
/// never got the same treatment.
///
/// **`ry` is deliberately absent.** [RoundedRectMask] clamps a single radius
/// jointly, which is only right while every mask is square; a mask that
/// declared `ry` would silently take circular corners where §9.2 says
/// elliptical. It throws until that class grows the second radius.
const _maskShapeAttributes = {'x', 'y', 'width', 'height', 'rx', 'fill'};

/// Rasterises [root] at [width] × [height] device pixels.
///
/// The target need not match the scene's `viewBox`: the two are related by a
/// **uniform** device scale, derived rather than passed. `ring` draws in 90
/// units and `beam` in 36, and a widget turns logical pixels into physical
/// ones by a device pixel ratio that is not required to be an integer — so an
/// integer-only scale would be no scale at all.
///
/// Throws [UnsupportedSceneError] for a non-positive target, a `viewBox` with
/// no extent, or a target whose two axes scale differently. The last is not
/// pedantry: [_ShapeAttributes.blurSigma] reads the matrix's column norms
/// because a Gaussian is isotropic only under a similarity, so a non-uniform
/// scale would silently pick one of two blurs.
RasterImage rasterizeScene(
  SvgNode root, {
  required int width,
  required int height,
}) {
  final view = _resolveScale(root, width, height);

  final maskNode = _firstOfKind(root, SvgElement.mask);
  if (maskNode == null) {
    throw UnsupportedSceneError('the scene has no <mask>');
  }
  final mask = _readMask(maskNode, view.scale);
  // The paint servers are read before the shapes, because a shape's `fill` can
  // reference one — `sunset` paints both its halves that way.
  final paints = _readPaintServers(root, view.scale);
  // **The viewBox, not the target.** A filter region is in user units — §15.7.2
  // again — and [_ShapeAttributes.filterRegionQuad] maps it through the same
  // matrix that carries the device scale. Handing the device size to this
  // resolver and then scaling the result would apply the scale twice.
  final filters = _readFilters(root, view.viewWidth, view.viewHeight);
  final shapes = <RasterShape>[];
  _collectShapes(
    root,
    shapes,
    insideMask: false,
    maskId: maskNode.attribute('id') as String?,
    paints: paints,
    filters: filters,
    inherited: Affine.scaling(view.scale, view.scale),
    // **Pre-scaled by the device scale, and by nothing else.** Flattening
    // happens in user units and the matrix multiplies the resulting error, so
    // a chord that sat `1/4096` inside its arc sits `scale × 1.3` device
    // pixels inside it once `marble`'s own `scale(1.3)` has applied too.
    // Dividing here holds the *device* error at the constant the tolerance was
    // chosen for, and at `scale == 1` it changes nothing — which is what keeps
    // every committed golden byte-identical.
    //
    // The variant's own scale is deliberately left out. Folding that in as
    // well would be exact and would move every golden for no visible gain,
    // which is the trade `_shapesOf`'s circle arm already records; what
    // changes with #58 is only that the *device* factor is unbounded, so it is
    // the one that has to be divided out.
    flatness: defaultFlatness / view.scale,
  );

  // The region **travels per shape**, so there is no scene-wide one to
  // reconcile. An earlier revision of this function refused a scene whose two
  // filters declared different regions; that check existed only because the
  // region was being resolved once, in viewport space — which was the defect.
  // See [_Filter.region].
  return rasterizeMaskedShapes(
    width: width,
    height: height,
    shapes: shapes,
    mask: mask,
  );
}

/// The device scale mapping the scene's `viewBox` onto a `width` × `height`
/// target, and the viewBox that the scene's user units are in.
///
/// **The scale is derived, never passed.** A caller handing over both a size
/// and a factor can contradict itself; deriving it means the two cannot
/// disagree, and it is what makes the non-uniform case detectable at all.
///
/// **A non-uniform scale is refused rather than averaged.** Two of this file's
/// readers need the transform to be a *similarity*: [_ShapeAttributes.blurSigma]
/// takes the matrix's column norms and says so — a Gaussian is only isotropic
/// under one — and [_ShapeAttributes.filterRegionQuad] maps the region through
/// the same matrix. Letting `sx != sy` through would silently pick one of two
/// blurs, which is the class of quiet wrong picture this seam exists to stop.
({double scale, double viewWidth, double viewHeight}) _resolveScale(
  SvgNode root,
  int width,
  int height,
) {
  if (width <= 0 || height <= 0) {
    throw UnsupportedSceneError(
      'the target is ${width}x$height; a raster needs a positive size',
    );
  }

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

  final viewWidth = parts[2]!;
  final viewHeight = parts[3]!;
  if (!viewWidth.isFinite ||
      !viewHeight.isFinite ||
      viewWidth <= 0 ||
      viewHeight <= 0) {
    throw UnsupportedSceneError(
      'viewBox is ${viewWidth}x$viewHeight; there is nothing to scale from',
    );
  }

  final sx = width / viewWidth;
  final sy = height / viewHeight;
  if (sx != sy) {
    throw UnsupportedSceneError(
      'viewBox is ${viewWidth}x$viewHeight but the target is ${width}x$height, '
      'which scales x by $sx and y by $sy; a non-uniform scale is not '
      'implemented',
    );
  }
  return (scale: sx, viewWidth: viewWidth, viewHeight: viewHeight);
}

/// Reads the `<mask>`'s single rect into a mask description.
///
/// Everything is looked up by name — `x`, `y`, `width`, `height`, `rx` — so a
/// call site that writes them in a different order rasterises identically.
///
/// [scale] converts the mask's user units to device pixels. It is applied at
/// the end rather than to the attributes as they are read, because the region
/// check below compares the region against the shape and both have to be in
/// the same space to mean anything. Scaling the four numbers is enough: the
/// radius is `min(rx, w / 2, h / 2)`, and a `min` of scaled inputs is the
/// scaled `min`.
RoundedRectMask _readMask(SvgNode maskNode, double scale) {
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
  _checkAttributes(rect, _maskShapeAttributes);

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

  return scale == 1
      ? shape
      : RoundedRectMask(
          x: shape.x * scale,
          y: shape.y * scale,
          width: shape.width * scale,
          height: shape.height * scale,
          rx: shape.radius * scale,
        );
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
  required Map<String, _Filter> filters,
  required Affine inherited,
  required double flatness,
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
    out.addAll(_shapesOf(node, paints, filters, inherited, flatness));
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
      filters: filters,
      inherited: matrix,
      flatness: flatness,
    );
  }
}

/// Reads every `<defs>` into paint servers, keyed by id.
///
/// `<defs>` holds nothing that is drawn where it sits, which made it tempting
/// to skip — and skipping it is why every `sunset` render came out blank before
/// #40: the shapes referenced paint that had never been read.
Map<String, RasterPaint> _readPaintServers(SvgNode root, double scale) {
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
        // `<filter>` also lives in `<defs>` and is read by [_readFilters]. It
        // is skipped here rather than refused, and validated there — the same
        // split `<mask>` and `<defs>` already take on the drawing walk.
        if (child.element == SvgElement.filter) continue;
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
        out[id] = _readLinearGradient(child, scale);
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

/// One `<filter>`, reduced to the only thing it does to the picture.
class _Filter {
  const _Filter(this.sigma, this.region);

  /// `feGaussianBlur`'s `stdDeviation`, in user units.
  final double sigma;

  /// The filter region in user units — a hard clip on the **output**.
  final ({double x, double y, double width, double height}) region;
}

/// Reads every `<filter>` in the scene, keyed by id.
///
/// **The chain is validated as a whole, not primitive by primitive.** Upstream
/// writes exactly one shape of filter:
///
/// ```
/// feFlood  flood-opacity="0"  result="BackgroundImageFix"
/// feBlend  in="SourceGraphic" in2="BackgroundImageFix" result="shape"
/// feGaussianBlur stdDeviation="7" result="effect1_foregroundBlur"
/// ```
///
/// A fully transparent flood, the source blended over it (which leaves the
/// source alone), and a blur of the result. Net effect: **blur the source**.
/// Reducing it to a sigma is only honest because the first two primitives are
/// checked to be the no-ops they look like — a `flood-opacity` that was not
/// zero, or an `feBlend` reading something other than `SourceGraphic`, is a
/// different picture and throws rather than being reduced away.
Map<String, _Filter> _readFilters(
  SvgNode root,
  double viewWidth,
  double viewHeight,
) {
  final out = <String, _Filter>{};

  void walk(SvgNode node) {
    if (node.element == SvgElement.filter) {
      final id = node.attribute('id');
      if (id is! String) {
        throw UnsupportedSceneError('a <filter> has no id');
      }

      // `objectBoundingBox` — the SVG default — would reinterpret the region
      // as fractions of the shape's box. `marble` declares user space.
      final units = node.attribute('filterUnits');
      if (units != 'userSpaceOnUse') {
        throw UnsupportedSceneError(
          'filterUnits "$units" is not implemented; only userSpaceOnUse',
        );
      }

      // The SVG default is **linearRGB**, so an absent attribute is not the
      // same as this one. `marble` declares sRGB, which is what this
      // rasterizer does — it blurs the channels as stored.
      final space = node.attribute('color-interpolation-filters');
      if (space != 'sRGB') {
        throw UnsupportedSceneError(
          'color-interpolation-filters "$space" is not implemented; only '
          'sRGB. The SVG default is linearRGB and would need a gamma pass',
        );
      }

      // §15.7.2's defaults are -10% / -10% / 120% / 120%, and under
      // `userSpaceOnUse` a percentage resolves against the **viewport**, not
      // the bounding box (§7.10). Measured in Chrome before it was written:
      // a 10 × 10 rect at (35, 35) blurred with no region renders identically
      // to one given x="-8" y="-8" width="96" height="96" on an 80 × 80
      // viewBox, and quite differently from the bbox reading's 34…46.
      //
      // hidden-state #11 said "of the bbox" and had never been executed —
      // `marble` is the only variant with a filter and it was unported.
      final region = (
        x: _num(node.attribute('x')) ?? -0.1 * viewWidth,
        y: _num(node.attribute('y')) ?? -0.1 * viewHeight,
        width: _num(node.attribute('width')) ?? 1.2 * viewWidth,
        height: _num(node.attribute('height')) ?? 1.2 * viewHeight,
      );

      final primitives = node.children;
      if (primitives.length != 3 ||
          primitives[0].element != SvgElement.feFlood ||
          primitives[1].element != SvgElement.feBlend ||
          primitives[2].element != SvgElement.feGaussianBlur) {
        throw UnsupportedSceneError(
          'the only filter chain implemented is feFlood + feBlend + '
          'feGaussianBlur, found '
          '${primitives.map((p) => "<${p.element.tag}>").join(", ")}',
        );
      }
      for (final p in primitives) {
        _checkAttributes(p, _defsAttributes[p.element]!);
      }

      // The flood must be invisible, or it is a background this rasterizer
      // would be dropping.
      final floodOpacity = _num(primitives[0].attribute('flood-opacity'));
      if (floodOpacity != 0) {
        throw UnsupportedSceneError(
          '<feFlood flood-opacity="$floodOpacity"> paints; only a fully '
          'transparent flood is reduced away',
        );
      }
      final floodResult = primitives[0].attribute('result');

      // The blend must be the source over that invisible flood, in `normal`
      // mode — anything else is a real compositing step.
      final blend = primitives[1];
      if (blend.attribute('in') != 'SourceGraphic' ||
          blend.attribute('in2') != floodResult) {
        throw UnsupportedSceneError(
          '<feBlend in="${blend.attribute('in')}" in2="${blend.attribute('in2')}"> '
          'is not the source over the flood, so it cannot be reduced away',
        );
      }
      final blendMode = blend.attribute('mode');
      if (blendMode != null && blendMode != 'normal') {
        throw UnsupportedSceneError(
          '<feBlend mode="$blendMode"> is not implemented',
        );
      }

      // And the blur must read the blend's output — an explicit `in` naming
      // something else would be filtering a different image.
      final blur = primitives[2];
      final blurIn = blur.attribute('in');
      if (blurIn != null && blurIn != blend.attribute('result')) {
        throw UnsupportedSceneError(
          '<feGaussianBlur in="$blurIn"> does not read the blend\'s result',
        );
      }
      final sigma = _num(blur.attribute('stdDeviation'));
      if (sigma == null || sigma < 0) {
        throw UnsupportedSceneError(
          '<feGaussianBlur stdDeviation="${blur.attribute('stdDeviation')}"> is '
          'not a usable standard deviation',
        );
      }

      out[id] = _Filter(sigma, region);
      return;
    }
    for (final child in node.children) {
      walk(child);
    }
  }

  walk(root);
  return out;
}

/// [scale] converts the gradient's user units to device pixels.
///
/// **This is not optional and the compiler cannot say so.**
/// [LinearGradientPaint.colourAt] projects the *device* pixel centre
/// (`px + 0.5`) onto the `x1,y1 -> x2,y2` axis, so an axis left in user units
/// puts the whole ramp in the top-left `1/scale` of the image and every pixel
/// outside it clamps to an end stop. Measured when #58 first landed without
/// this: `sunset` at 2x, box-filtered back to 1:1, came back **108/255** off
/// across whole interior rows while the shapes themselves were exactly where
/// they belonged. Nothing else in the file reads a length this way — the
/// shapes go through the matrix and the mask is scaled at construction — which
/// is precisely why this one was missed.
LinearGradientPaint _readLinearGradient(SvgNode node, double scale) {
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
    x1: (_num(node.attribute('x1')) ?? 0) * scale,
    y1: (_num(node.attribute('y1')) ?? 0) * scale,
    x2: (_num(node.attribute('x2')) ?? 0) * scale,
    y2: (_num(node.attribute('y2')) ?? 0) * scale,
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
  Map<String, _Filter> filters,
  Affine inherited,
  double flatness,
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

  /// The `stdDeviation` of the `<filter>` this element references, in **device
  /// pixels**, if any.
  ///
  /// A `filter="url(#…)"` naming something absent is refused rather than
  /// ignored: a browser renders the element **unfiltered** in that case, so
  /// ignoring it would draw a sharp blob where upstream draws a blurred one —
  /// a plausible wrong picture, which is what this seam exists to stop.
  ///
  /// **The declared sigma is in the referencing element's own user space, and
  /// that space includes the element's `transform`.** §15.7.2 says
  /// `userSpaceOnUse` means "the user coordinate system in place at the time
  /// when the filter is referenced", which for an element carrying a transform
  /// is the transformed one — so `marble`'s `scale(1.2)` makes a declared
  /// `stdDeviation="7"` a blur of **8.4** device pixels.
  ///
  /// Measured before it was written this way. Sweeping our sigma against
  /// Chrome's fixed `stdDeviation="7"` render of the same blob, the error
  /// bottoms out at 8.4–8.5 and not at 7:
  ///
  /// ```
  /// sigma 7.0  d=13  worst 27  mean 6.23
  /// sigma 8.0  d=15  worst 15  mean 2.85
  /// sigma 8.5  d=16  worst 12  mean 0.76   <- 7 x 1.2 = 8.4
  /// sigma 9.0  d=17  worst 10  mean 1.00
  /// ```
  double? blurSigma(Affine matrix) {
    final declared = node.attribute('filter') as String?;
    if (declared == null) return null;
    final id = RegExp(r'^url\(#(.*)\)$').firstMatch(declared)?.group(1);
    final filter = id == null ? null : filters[id];
    if (filter == null) {
      throw UnsupportedSceneError(
        '<${node.element.tag} filter="$declared"> references a filter that is '
        'not declared in any <defs>',
      );
    }

    // A Gaussian is only isotropic under a *similarity* transform. Every
    // transform any version in scope writes is `translate · rotate · scale`
    // with one scale factor, so the two column norms agree; a non-uniform
    // scale or a skew would need an elliptical kernel, which is a real
    // capability and not one to fake with the average of two numbers.
    final scaleX = math.sqrt(matrix.a * matrix.a + matrix.b * matrix.b);
    final scaleY = math.sqrt(matrix.c * matrix.c + matrix.d * matrix.d);
    if ((scaleX - scaleY).abs() > 1e-9) {
      throw UnsupportedSceneError(
        'a filtered element under a non-uniform transform ($scaleX x $scaleY) '
        'would need an anisotropic blur, which is not implemented',
      );
    }
    return filter.sigma * scaleX;
  }

  /// This element's filter region as a quad in **device** coordinates.
  ///
  /// The region is a rectangle in the element's **own** space (§15.7.2 — the
  /// same sentence that governs [blurSigma]), so the element's `transform`
  /// carries it: under a rotation the device-space image is a quadrilateral,
  /// and it is handed over as a contour so the clip can be antialiased by the
  /// scanline integrator rather than stepped at the pixel centre.
  ///
  /// **Applying §15.7.2 to the sigma and not to the region was the defect the
  /// #41 completeness pass found.** Reproduced in Chrome on three constructions
  /// with a control, then on the variant itself: `marble-clara-square` really
  /// is clipped by its own region — Chrome differs from an unclippable region
  /// by 23 pixels there — and the port was clipping nothing.
  PathContour? filterRegionQuad(Affine matrix) {
    final declared = node.attribute('filter') as String?;
    if (declared == null) return null;
    final id = RegExp(r'^url\(#(.*)\)$').firstMatch(declared)?.group(1);
    final filter = filters[id];
    // A dangling reference already threw in [blurSigma]; reaching here with a
    // null filter would mean the two disagreed about what they resolved.
    if (filter == null) return null;
    final r = filter.region;
    return matrix.transformContour(
      rectangleContour(r.x, r.y, r.width, r.height),
    );
  }

  /// The `mix-blend-mode` this element's inline `style` declares.
  ///
  /// The whole `style` attribute is matched, not searched: `marble` writes
  /// exactly one declaration and nothing else in the six writes a `style` at
  /// all, so accepting a *substring* would let a second declaration through
  /// unread. A CSS parser is a capability no version in scope asks for.
  RasterBlendMode blendMode() {
    final declared = node.attribute('style') as String?;
    if (declared == null) return RasterBlendMode.normal;
    if (declared == 'mix-blend-mode:overlay') return RasterBlendMode.overlay;
    throw UnsupportedSceneError(
      '<${node.element.tag} style="$declared"> is not implemented; the only '
      'inline style in scope is "mix-blend-mode:overlay"',
    );
  }

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
              roundedRectContour(
                x,
                y,
                width,
                height,
                rx,
                ry,
                flatness: flatness,
              ),
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
      // A filter and a blend mode apply to the element as a whole — to its
      // fill and its stroke together, as one offscreen result. No element in
      // the six carries both a stroke and a filter, so the two `RasterPolygon`s
      // below are never both filtered; were that to change, they would have to
      // share one layer rather than take one each.
      final sigma = blurSigma(matrix);
      final mode = blendMode();
      final clip = filterRegionQuad(matrix);
      if (sigma != null && fill != null && stroke != null) {
        throw UnsupportedSceneError(
          '<path> has a fill, a stroke and a filter; the two would be blurred '
          'separately where SVG blurs the composited element',
        );
      }
      return [
        // §11: the fill is painted first and the stroke on top of it. `beam`
        // never asks for both at once — the open mouth strokes and the closed
        // one fills — but the order is the spec's, not the variant's.
        if (fill != null)
          RasterPolygon(
            [
              for (final contour in parsePath(d, flatness: flatness))
                matrix.transformContour(contour),
            ],
            fill,
            blurSigma: sigma,
            blendMode: mode,
            filterRegion: clip,
          ),
        if (stroke != null)
          RasterPolygon(
            [
              for (final contour in strokePathOutline(
                parsePathSubpaths(d, flatness: flatness),
                width: strokeWidth(),
                cap: strokeCap(),
                // The joint and cap discs are curves too. Until #58's
                // completeness pass they were the one flattening in the file
                // that never saw the device scale: constant segment count, so
                // the device error grew linearly and crossed the 1/255 bar at
                // about 25x — a 900-pixel `beam`, which its 36-unit viewBox
                // reaches at an ordinary avatar size.
                flatness: flatness,
              ))
                matrix.transformContour(contour),
            ],
            stroke,
            blurSigma: sigma,
            blendMode: mode,
            filterRegion: clip,
          ),
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
              flatness: flatness,
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
