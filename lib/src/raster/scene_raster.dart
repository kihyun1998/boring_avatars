/// Turns a scene into pixels.
///
/// The rasterizer reads scene nodes **by attribute name**, never by position,
/// which is what lets the SVG emitter depend on attribute *order* without that
/// ordering leaking down here. This file is where that claim is cashed.
///
/// It handles what `pixel` needs — a rounded-rect mask over axis-aligned
/// rectangles. Curves, strokes, gradients and filters arrive with the variants
/// that use them, and **everything else throws**. That is the point of
/// [UnsupportedSceneError]: an unhandled `<path>` rendering as blank, or a
/// `transform` being ignored so a rect lands square and unrotated, is a
/// plausible *wrong picture* — and a golden would freeze it. A loud failure at
/// the seam is the only thing that stops the next variant from shipping a
/// silently incorrect image.
library;

import '../scene/scene.dart';
import 'raster.dart';

/// Thrown when a scene needs a capability this rasterizer does not have yet.
class UnsupportedSceneError extends Error {
  UnsupportedSceneError(this.message);
  final String message;

  @override
  String toString() => 'UnsupportedSceneError: $message';
}

/// Attributes the rect path understands. Anything else on a drawn rect changes
/// the picture, so meeting one is a failure rather than something to skip.
const _supportedRectAttributes = {'x', 'y', 'width', 'height', 'fill'};

/// Elements that carry no geometry and can be walked through or ignored.
const _structuralElements = {
  SvgElement.svg,
  SvgElement.g,
  SvgElement.title,
  SvgElement.defs,
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

  final mask = _readMask(root);
  final rects = <RasterRect>[];
  _collectRects(root, rects, insideMask: false);

  return rasterizeMaskedRects(
    width: width,
    height: height,
    rects: rects,
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
RoundedRectMask _readMask(SvgNode root) {
  final maskNode = _firstOfKind(root, SvgElement.mask);
  if (maskNode == null) {
    throw UnsupportedSceneError('the scene has no <mask>');
  }

  // `pixel` declares mask-type="alpha"; the other five declare nothing, which
  // in SVG means a *luminance* mask. Every mask shape in the six is filled
  // #FFFFFF, where luminance and alpha both come to 1 — so the distinction is
  // inert today. It is checked rather than assumed: see hidden-state #22.
  final maskType = maskNode.attribute('mask-type');
  if (maskType != null && maskType != 'alpha') {
    throw UnsupportedSceneError('mask-type "$maskType" is not implemented');
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

  return RoundedRectMask(
    x: _num(rect.attribute('x')) ?? 0,
    y: _num(rect.attribute('y')) ?? 0,
    width: _num(rect.attribute('width'))!,
    height: _num(rect.attribute('height'))!,
    // An absent `rx` is a square corner, not a default radius — upstream
    // expresses `square: true` by omitting the attribute entirely.
    rx: _num(rect.attribute('rx')) ?? 0,
  );
}

/// Collects the rects that are actually drawn — the ones under the masked
/// group, not the one that defines the mask.
void _collectRects(
  SvgNode node,
  List<RasterRect> out, {
  required bool insideMask,
}) {
  if (node.element == SvgElement.mask) return; // the mask shape, not content

  if (insideMask) {
    if (node.element != SvgElement.rect &&
        !_structuralElements.contains(node.element)) {
      throw UnsupportedSceneError(
        '<${node.element.tag}> is not implemented; only <rect> is drawn so far',
      );
    }
    if (node.element == SvgElement.rect) {
      for (final a in node.attributes) {
        if (!_supportedRectAttributes.contains(a.name)) {
          throw UnsupportedSceneError(
            '<rect ${a.name}="…"> is not implemented and would change the '
            'picture if ignored',
          );
        }
      }
      out.add(
        RasterRect(
          _num(node.attribute('x')) ?? 0,
          _num(node.attribute('y')) ?? 0,
          _num(node.attribute('width'))!,
          _num(node.attribute('height'))!,
          node.attribute('fill') as String?,
        ),
      );
      return;
    }
  }

  final within = insideMask || node.attribute('mask') != null;
  for (final child in node.children) {
    _collectRects(child, out, insideMask: within);
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
