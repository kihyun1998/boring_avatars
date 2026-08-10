// The closed-form rectangle path — a property no golden can see.
//
// `scene_raster.dart` sends a rect to [RasterRect] only when its matrix
// `isTranslationOnly` (`transform.dart` — `a == 1 && d == 1`), and to
// [RasterPolygon] otherwise. The device scale is `target / viewBox`, so that
// condition holds at **exactly one target size**: the variant's own design
// side.
//
// **Both integrators draw the same picture.** That is the point of the pair and
// it is also why nothing else in this suite can defend the fast path: every
// byte assertion stays green whichever one runs. The difference is cost, and it
// was measured — `pixel` at 80 physical pixels is **6.5x** cheaper than at 81,
// `bauhaus` about 2x, and `ring`, which has no axis-aligned rects, is flat
// across the same sweep. That last one is the control that makes the
// attribution a measurement rather than a story; the numbers and the method are
// in `docs/agents/theflow.md`.
//
// So: structural assertions, not timings. A timing test would be flaky here —
// the same cell measured 39.3 ms and 286.2 ms within a single process on this
// machine under load, which is recorded in the same place.

import 'package:boring_avatars/src/avatar.dart';
import 'package:boring_avatars/src/raster/raster.dart';
import 'package:boring_avatars/src/raster/scene_raster.dart';
import 'package:boring_avatars/src/variant.dart';
import 'package:boring_avatars/src/version.dart';
import 'package:flutter_test/flutter_test.dart';

const _palette = <String>[
  '#92A1C6',
  '#146A7C',
  '#F0AB3D',
  '#C271B4',
  '#C20D90',
];

List<RasterShape> _shapesAt(
  BoringAvatarsVariant variant,
  int side,
  int target,
) => SceneRaster(
  buildAvatarScene(
    name: 'Clara Barton',
    colors: _palette,
    size: side,
    version: BoringAvatarsVersion.v1_6_1,
    variant: variant,
    square: false,
  ),
  width: target,
  height: target,
).shapes;

int _rects(List<RasterShape> shapes) => shapes.whereType<RasterRect>().length;

void main() {
  group('at the design size the rects stay rects', () {
    test('pixel is all of them, which is why it is the cheapest variant', () {
      final shapes = _shapesAt(BoringAvatarsVariant.pixel, 80, 80);
      expect(shapes, isNotEmpty);
      expect(
        _rects(shapes),
        shapes.length,
        reason:
            'every shape pixel draws is an axis-aligned rect, so at scale 1 '
            'every one of them must take the closed-form integrator',
      );
    });

    test('bauhaus takes it for the ones it does not rotate', () {
      // Partial on purpose: bauhaus rotates some of its rects, and a rotated
      // rect *has* to become a polygon. Asserting "some but not all" is what
      // distinguishes this from both failure modes — none taking the path, and
      // a change that wrongly gave a rotated rect the axis-aligned integrator.
      final shapes = _shapesAt(BoringAvatarsVariant.bauhaus, 80, 80);
      expect(_rects(shapes), greaterThan(0));
      expect(_rects(shapes), lessThan(shapes.length));
    });
  });

  group('one pixel away, none of them do', () {
    // The discriminator. If these passed too, the assertions above would be
    // satisfied by a build that never consulted the matrix at all.
    test('pixel at 81 is entirely polygons', () {
      final shapes = _shapesAt(BoringAvatarsVariant.pixel, 80, 81);
      expect(shapes, isNotEmpty);
      expect(
        _rects(shapes),
        0,
        reason:
            'the device scale is 81/80, so no matrix is a translation and the '
            'closed-form path is unreachable — this is the 6.5x cliff',
      );
    });

    test('and so is bauhaus', () {
      expect(_rects(_shapesAt(BoringAvatarsVariant.bauhaus, 80, 81)), 0);
    });
  });

  test('a variant with no axis-aligned rects is flat across the same step', () {
    // The control. `ring` measured the same cost at 90 and at 91, and this is
    // why: there is nothing in it for the fast path to catch, at either size.
    for (final target in <int>[90, 91]) {
      final shapes = _shapesAt(BoringAvatarsVariant.ring, 90, target);
      expect(shapes, isNotEmpty);
      expect(
        _rects(shapes),
        0,
        reason: 'ring has no axis-aligned rect to accelerate, at $target',
      );
    }
  });

  test('and it draws something, which the assertions above do not check', () {
    // Deliberately modest, and labelled as such. Everything above counts
    // *shapes*, so all four would pass against a resolver that produced a
    // perfect list of `RasterRect`s and a rasteriser that drew none of them.
    // This is the floor under that: the fast path, actually run, actually
    // filling a buffer.
    //
    // It is not the correctness proof and does not pretend to be one. That is
    // `pixel_raster_test.dart` and the committed fixtures, which compare these
    // very bytes against Chrome's — and which stayed green with the fast path
    // forced off, which is the whole reason this file exists.
    final image = rasterizeScene(
      buildAvatarScene(
        name: 'Clara Barton',
        colors: _palette,
        size: 80,
        version: BoringAvatarsVersion.v1_6_1,
        variant: BoringAvatarsVariant.pixel,
        square: false,
      ),
      width: 80,
      height: 80,
    );
    expect(image.width, 80);
    expect(image.bytes.length, 80 * 80 * 4);
    expect(
      image.bytes.any((b) => b != 0),
      isTrue,
      reason: 'the rect path drew nothing at all',
    );
  });
}
