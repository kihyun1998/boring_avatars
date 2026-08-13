import 'dart:io';

import 'package:boring_avatars/src/raster/raster.dart';
import 'package:boring_avatars/src/raster/scene_raster.dart';
import 'package:boring_avatars/src/scene/scene.dart';
import 'package:boring_avatars/src/variants/marble.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';
import 'support/golden_cases.dart';

/// Layer-3 for `marble` — the blur, the blend, and the offscreen layer both of
/// them need.
///
/// **The goldens at the bottom prove nothing on their own.** They are generated
/// from the same code the test runs, so they lock a *state*, not a
/// *correctness*. What makes that state evidence is everything above them: the
/// box size against the spec's own formula, the blend against hand-computed
/// values, the region against numbers measured in Chrome, and the padding
/// against a shape that is mostly off-canvas. Each of those is checkable
/// without any committed file.
void main() {
  const palette = goldenDefaultPalette;

  /// A minimal scene: one filtered, optionally blended shape over a background.
  ///
  /// Built by hand rather than taken from `marble` so the cases below can reach
  /// inputs upstream never produces — an off-canvas shape, a region that
  /// actually clips, a non-uniform scale.
  SvgNode scene({
    required List<SvgAttribute> shape,
    List<SvgAttribute> filter = const [
      SvgAttribute('id', 'f'),
      SvgAttribute('filterUnits', 'userSpaceOnUse'),
      SvgAttribute('color-interpolation-filters', 'sRGB'),
    ],
    num sigma = 7,
    String? background = '#000000',
    int size = 80,
  }) => SvgNode(
    SvgElement.svg,
    attributes: [
      SvgAttribute('viewBox', '0 0 $size $size'),
      const SvgAttribute('fill', 'none'),
    ],
    children: [
      SvgNode(
        SvgElement.mask,
        attributes: [
          const SvgAttribute('id', 'm'),
          const SvgAttribute('maskUnits', 'userSpaceOnUse'),
          const SvgAttribute('x', 0),
          const SvgAttribute('y', 0),
          SvgAttribute('width', size),
          SvgAttribute('height', size),
        ],
        children: [
          SvgNode(
            SvgElement.rect,
            attributes: [
              SvgAttribute('width', size),
              SvgAttribute('height', size),
              const SvgAttribute('fill', '#FFFFFF'),
            ],
          ),
        ],
      ),
      SvgNode(
        SvgElement.g,
        attributes: const [SvgAttribute('mask', 'url(#m)')],
        children: [
          if (background != null)
            SvgNode(
              SvgElement.rect,
              attributes: [
                SvgAttribute('width', size),
                SvgAttribute('height', size),
                SvgAttribute('fill', background),
              ],
            ),
          SvgNode(SvgElement.path, attributes: shape),
        ],
      ),
      SvgNode(
        SvgElement.defs,
        children: [
          SvgNode(
            SvgElement.filter,
            attributes: filter,
            children: [
              const SvgNode(
                SvgElement.feFlood,
                attributes: [
                  SvgAttribute('flood-opacity', 0),
                  SvgAttribute('result', 'BackgroundImageFix'),
                ],
              ),
              const SvgNode(
                SvgElement.feBlend,
                attributes: [
                  SvgAttribute('in', 'SourceGraphic'),
                  SvgAttribute('in2', 'BackgroundImageFix'),
                  SvgAttribute('result', 'shape'),
                ],
              ),
              SvgNode(
                SvgElement.feGaussianBlur,
                attributes: [
                  SvgAttribute('stdDeviation', sigma),
                  const SvgAttribute('result', 'e'),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  group('the three-box approximation is the spec\'s, not an approximation of it', () {
    test('the box size is SVG 1.1 §15.17\'s formula', () {
      // d = floor(s * 3 * sqrt(2 * PI) / 4 + 0.5). Spot values computed by
      // hand rather than by re-running the expression under test.
      expect(gaussianBoxSize(0), 0);
      expect(gaussianBoxSize(1), 2); // 1.880 + 0.5 -> 2
      expect(gaussianBoxSize(7), 13); // 13.160 + 0.5 -> 13
      expect(gaussianBoxSize(8.4), 16); // 15.792 + 0.5 -> 16
      expect(gaussianBoxSize(9.1), 17); // 17.108 + 0.5 -> 17
      expect(gaussianBoxSize(56), 105); // 105.26 + 0.5 -> 105
    });

    test('and both parities are reachable from real marble input', () {
      // The odd and even branches are different code. `marble`'s two scales
      // put one on each side, so neither can sit unrun — which is what
      // happened to the F.6.6 arc correction for two whole tickets (#36/#37).
      expect(gaussianBoxSize(7 * 1.2).isEven, isTrue, reason: 'scale 1.2');
      expect(gaussianBoxSize(7 * 1.3).isOdd, isTrue, reason: 'scale 1.3');
      // And every scale a name can produce is one of these four.
      for (final scale in [1.2, 1.3, 1.4, 1.5]) {
        expect(gaussianBoxSize(7 * scale), greaterThan(0));
      }
    });

    test('a blur conserves ink — it moves coverage, it does not create it', () {
      // The outside opinion that needs no browser: three box passes are each an
      // average, so the total alpha over a large enough layer is unchanged.
      // A kernel that was normalised wrongly would fail this without any
      // reference render.
      final sharp = rasterizeScene(
        scene(
          shape: const [
            SvgAttribute('d', 'M20 20H60V60H20z'),
            SvgAttribute('fill', '#FFFFFF'),
          ],
          background: null,
        ),
        width: 80,
        height: 80,
      );
      final blurred = rasterizeScene(
        scene(
          shape: const [
            SvgAttribute('filter', 'url(#f)'),
            SvgAttribute('d', 'M20 20H60V60H20z'),
            SvgAttribute('fill', '#FFFFFF'),
          ],
          background: null,
        ),
        width: 80,
        height: 80,
      );
      var sharpInk = 0, blurredInk = 0;
      for (var i = 3; i < sharp.bytes.length; i += 4) {
        sharpInk += sharp.bytes[i];
        blurredInk += blurred.bytes[i];
      }
      // The shape is 40 x 40 at the centre of an 80 x 80 canvas and sigma is 7,
      // so nothing of consequence blurs off the edge. Within a rounding budget
      // of one level per painted pixel.
      expect(sharpInk, 40 * 40 * 255);
      expect((blurredInk - sharpInk).abs(), lessThan(40 * 40));
    });
  });

  group('the blur is measured in the element\'s own space', () {
    test('a scaled element blurs by scale x stdDeviation', () {
      // The bug this pins cost 27/255 against Chrome. §15.7.2's user space for
      // `userSpaceOnUse` is the one in place where the filter is *referenced*,
      // and an element's own `transform` is part of that — so `scale(2)` on a
      // shape doubles its blur.
      //
      // Asserted as a *relation between two renders*, not against a magic
      // number: a shape scaled 2x and blurred must match the same shape drawn
      // twice as large and blurred twice as much.
      final scaled = rasterizeScene(
        scene(
          shape: const [
            SvgAttribute('filter', 'url(#f)'),
            SvgAttribute('d', 'M15 15H25V25H15z'),
            SvgAttribute('fill', '#FFFFFF'),
            SvgAttribute('transform', 'scale(2)'),
          ],
          sigma: 3,
          background: null,
        ),
        width: 80,
        height: 80,
      );
      final equivalent = rasterizeScene(
        scene(
          shape: const [
            SvgAttribute('filter', 'url(#f)'),
            SvgAttribute('d', 'M30 30H50V50H30z'),
            SvgAttribute('fill', '#FFFFFF'),
          ],
          sigma: 6,
          background: null,
        ),
        width: 80,
        height: 80,
      );
      var worst = 0;
      for (var i = 0; i < scaled.bytes.length; i++) {
        final d = (scaled.bytes[i] - equivalent.bytes[i]).abs();
        if (d > worst) worst = d;
      }
      expect(
        worst,
        lessThanOrEqualTo(1),
        reason: 'scale(2) x sigma 3 == sigma 6',
      );
    });

    test('a non-uniform transform is refused rather than averaged', () {
      // A Gaussian is only isotropic under a similarity. Faking it with the
      // mean of two scales would be a plausible wrong picture.
      //
      // **This test used to assert nothing.** It checked `returnsNormally` on a
      // *uniform* `scale(2)` and then compared `gaussianBoxSize(14)` to 26,
      // and its comment claimed the real case could not be built because
      // "`parseTransform` has no two-argument `scale`". That was false —
      // `transform.dart` implements §7.4's two-argument form deliberately, with
      // a doc-comment about why its default differs from `translate`'s. The
      // #41 refuting lens deleted the guard outright and the whole suite stayed
      // green.
      expect(
        () => rasterizeScene(
          scene(
            shape: const [
              SvgAttribute('filter', 'url(#f)'),
              SvgAttribute('d', 'M20 20H60V60H20z'),
              SvgAttribute('fill', '#FFFFFF'),
              SvgAttribute('transform', 'scale(2 3)'),
            ],
          ),
          width: 80,
          height: 80,
        ),
        throwsA(isA<UnsupportedSceneError>()),
      );
      // A skew would reach it too, if one were ever writable — the guard is on
      // the two column norms, not on the spelling of the function.
      expect(
        () => rasterizeScene(
          scene(
            shape: const [
              SvgAttribute('filter', 'url(#f)'),
              SvgAttribute('d', 'M20 20H60V60H20z'),
              SvgAttribute('fill', '#FFFFFF'),
              SvgAttribute('transform', 'scale(1 2) rotate(30 40 40)'),
            ],
          ),
          width: 80,
          height: 80,
        ),
        throwsA(isA<UnsupportedSceneError>()),
      );
      // And the uniform case it used to test still passes, so the guard is not
      // simply refusing every scale.
      expect(
        () => rasterizeScene(
          scene(
            shape: const [
              SvgAttribute('filter', 'url(#f)'),
              SvgAttribute('d', 'M20 20H60V60H20z'),
              SvgAttribute('fill', '#FFFFFF'),
              SvgAttribute('transform', 'scale(2)'),
            ],
          ),
          width: 80,
          height: 80,
        ),
        returnsNormally,
      );
    });
  });

  group('the offscreen layer is bigger than the canvas', () {
    test('a shape that is mostly off-canvas still blurs back into view', () {
      // `marble`'s second blob reaches x = 89 and y = 100 once `scale(1.3)` is
      // applied, on an 80 x 80 target. A layer rasterised only over [0, 80)
      // would drop that and the picture would be wrong at the edge with
      // nothing thrown — so this puts the whole shape outside and asserts that
      // ink still arrives.
      final image = rasterizeScene(
        scene(
          shape: const [
            SvgAttribute('filter', 'url(#f)'),
            // Entirely to the right of the canvas.
            SvgAttribute('d', 'M85 20H140V60H85z'),
            SvgAttribute('fill', '#FFFFFF'),
          ],
          background: null,
        ),
        width: 80,
        height: 80,
      );
      final atEdge = image.bytes[(40 * 80 + 79) * 4 + 3];
      expect(
        atEdge,
        greaterThan(0),
        reason: 'an off-canvas shape has to blur inwards',
      );
      // And it falls off going left, rather than filling the canvas.
      final inward = image.bytes[(40 * 80 + 60) * 4 + 3];
      expect(inward, lessThan(atEdge));
      expect(image.bytes[(40 * 80 + 20) * 4 + 3], 0);
    });

    test('the reach is wide enough for the kernel that uses it', () {
      // Three boxes of width d have support 3d - 2, so a pixel can be reached
      // from (3d - 1) / 2 away. Short padding silently truncates the blur.
      for (final d in [2, 13, 16, 17, 105]) {
        expect(blurReach(d), greaterThanOrEqualTo((3 * d - 1) ~/ 2));
      }
      expect(blurReach(0), 0);
      expect(blurReach(1), 0);
    });
  });

  group('overlay blends against the group, and only the group', () {
    test('the blend function is CSS Compositing L1\'s, hand-checked', () {
      // overlay(Cb, Cs) = Cb <= 0.5 ? 2*Cb*Cs : 1 - 2*(1-Cb)*(1-Cs)
      const overlay = RasterBlendMode.overlay;
      expect(overlay.apply(0, 1), 0);
      expect(overlay.apply(0.25, 0.5), closeTo(0.25, 1e-12));
      expect(overlay.apply(0.5, 0.5), closeTo(0.5, 1e-12));
      expect(overlay.apply(0.75, 0.5), closeTo(0.75, 1e-12));
      expect(overlay.apply(1, 0), 1);
      // The measured case: overlay(#808080, #3399CC) is (52, 153, 204) in
      // Chrome. 0x80/255 is just above 0.5, so this exercises the upper branch
      // at the point where the two are nearest.
      expect((overlay.apply(0x80 / 255, 0x33 / 255) * 255).round(), 52);
      expect((overlay.apply(0x80 / 255, 0x99 / 255) * 255).round(), 153);
      expect((overlay.apply(0x80 / 255, 0xCC / 255) * 255).round(), 204);
      // `normal` returns the source untouched, whatever is underneath.
      expect(RasterBlendMode.normal.apply(0.3, 0.7), 0.7);
    });

    test('an opaque white backdrop swallows the source entirely', () {
      // This is why `Alice`'s two-colour palette is in the golden roster: with
      // Cb = 1 the upper branch is 1 - 2*0*(1-Cs) = 1 for every Cs, so the
      // blend saturates and a *region* goes flat white. It is the one place
      // `marble`'s calibration produces interior mismatches at all, because
      // everywhere else the blur leaves no 3x3-uniform pixel to classify.
      for (final source in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        expect(RasterBlendMode.overlay.apply(1, source), 1);
      }
      // And symmetrically, an opaque black backdrop swallows it the other way.
      for (final source in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        expect(RasterBlendMode.overlay.apply(0, source), 0);
      }
    });

    test('a transparent backdrop lets the source through unchanged', () {
      // The general formula's first term. `marble`'s overlay blob looks like
      // an ordinary blob outside the background rect and tints only over it —
      // and since the background covers the whole canvas, this is the case the
      // *mask* corners reach.
      final image = RasterImage(1, 1);
      image.blendSource(0, 0, 0.2, 0.4, 0.6, 1, RasterBlendMode.overlay);
      expect(image.bytes.sublist(0, 4), [51, 102, 153, 255]);
    });

    test('marble declares the blend on the second path only', () {
      // Order decides what blends against what. Asserted at the raster seam
      // rather than only in the bytes: a scene that carried the style on the
      // first path would draw a different picture and emit different bytes,
      // and only one of those two is this file's business.
      final withBlend = rasterizeScene(
        buildMarbleScene(
          title: true,
          name: 'Alice',
          colors: const ['#000000', '#FFFFFF'],
          size: 80,
        ),
        width: 80,
        height: 80,
      );
      final withoutBlend = rasterizeScene(
        _stripStyle(
          buildMarbleScene(
            title: true,
            name: 'Alice',
            colors: const ['#000000', '#FFFFFF'],
            size: 80,
          ),
        ),
        width: 80,
        height: 80,
      );
      // A tripwire that trips: dropping the blend has to change the picture,
      // or nothing in this file is testing the blend at all.
      expect(
        withBlend.bytes,
        isNot(withoutBlend.bytes),
        reason: 'the overlay has to be visible in the output',
      );
    });
  });

  group('the filter region', () {
    test('defaults to -10%/120% of the viewport, not of the bounding box', () {
      // §15.7.2 gives the defaults and §7.10 says a percentage under
      // `userSpaceOnUse` resolves against the viewport. Measured in Chrome
      // before it was implemented: a 10 x 10 rect at (35, 35) blurred with no
      // region renders identically to one given x="-8" y="-8" width="96"
      // height="96" on an 80 x 80 viewBox — ink from 18.25 to 61.75 — and
      // quite differently from the bbox reading, which cuts it to 34…46.
      //
      // Asserted as an equality between the two renders, which is exactly what
      // the browser measurement showed.
      final byDefault = rasterizeScene(
        scene(
          shape: const [
            SvgAttribute('filter', 'url(#f)'),
            SvgAttribute('d', 'M35 35H45V45H35z'),
            SvgAttribute('fill', '#FFFFFF'),
          ],
          background: null,
        ),
        width: 80,
        height: 80,
      );
      final explicit = rasterizeScene(
        scene(
          shape: const [
            SvgAttribute('filter', 'url(#f)'),
            SvgAttribute('d', 'M35 35H45V45H35z'),
            SvgAttribute('fill', '#FFFFFF'),
          ],
          filter: const [
            SvgAttribute('id', 'f'),
            SvgAttribute('filterUnits', 'userSpaceOnUse'),
            SvgAttribute('color-interpolation-filters', 'sRGB'),
            SvgAttribute('x', -8),
            SvgAttribute('y', -8),
            SvgAttribute('width', 96),
            SvgAttribute('height', 96),
          ],
          background: null,
        ),
        width: 80,
        height: 80,
      );
      expect(byDefault.bytes, explicit.bytes);

      // And the bbox reading really is a different picture, so the assertion
      // above is not satisfied by both readings agreeing.
      final asBoundingBox = rasterizeScene(
        scene(
          shape: const [
            SvgAttribute('filter', 'url(#f)'),
            SvgAttribute('d', 'M35 35H45V45H35z'),
            SvgAttribute('fill', '#FFFFFF'),
          ],
          filter: const [
            SvgAttribute('id', 'f'),
            SvgAttribute('filterUnits', 'userSpaceOnUse'),
            SvgAttribute('color-interpolation-filters', 'sRGB'),
            SvgAttribute('x', 34),
            SvgAttribute('y', 34),
            SvgAttribute('width', 12),
            SvgAttribute('height', 12),
          ],
          background: null,
        ),
        width: 80,
        height: 80,
      );
      expect(asBoundingBox.bytes, isNot(byDefault.bytes));
    });

    test('and each of the four default percentages is pinned', () {
      // `marble`'s own goldens pin **two** of them. The region clips it at the
      // top, so `y` and `height` are caught by `marble-clara-square` — but `x`
      // and `width` land at -8 and 108, both off-canvas, and mutating them to
      // -20% / 140% survived the whole suite when the #41 refuting lens tried
      // it. The number the correction of hidden-state #11 turns on was
      // resting entirely on a Chrome measurement recorded in a comment.
      //
      // A translate brings each edge onto the canvas, which is the only way to
      // reach them: the region moves with the element (§15.7.2), so the same
      // property that made the region a defect makes it testable.
      // The shape covers the whole canvas whatever the translate does, so the
      // only thing that can remove ink is the region itself. A shape with its
      // own edge nearby would make the test pass for the wrong reason.
      RasterImage render(String transform) => rasterizeScene(
        scene(
          shape: [
            const SvgAttribute('filter', 'url(#f)'),
            const SvgAttribute('d', 'M-200 -200H200V200H-200z'),
            const SvgAttribute('fill', '#FFFFFF'),
            SvgAttribute('transform', transform),
          ],
          sigma: 1,
          background: null,
        ),
        width: 80,
        height: 80,
      );
      int alphaAt(RasterImage i, int x, int y) => i.bytes[(y * 80 + x) * 4 + 3];

      // translate(20 0) puts the region's LEFT edge at -8 + 20 = 12.
      final left = render('translate(20 0)');
      expect(alphaAt(left, 5, 40), 0, reason: 'x=5 is left of the region');
      expect(alphaAt(left, 11, 40), 0, reason: 'x=11 is left of the region');
      expect(
        alphaAt(left, 14, 40),
        greaterThan(0),
        reason: 'x=14 is inside it',
      );

      // translate(-40 0) puts the RIGHT edge at -8 + 96 - 40 = 48.
      final right = render('translate(-40 0)');
      expect(
        alphaAt(right, 45, 40),
        greaterThan(0),
        reason: 'x=45 is inside the region',
      );
      expect(alphaAt(right, 50, 40), 0, reason: 'x=50 is right of it');
      expect(alphaAt(right, 70, 40), 0);
    });

    test('and the region scales with the device, not with the viewport', () {
      // #58 made the target size independent of the viewBox, which puts a
      // second reading of the same numbers in play: the region's default is
      // -10%/120% *of the viewBox*, and resolving it against the device size
      // instead makes it `scale` times too big. Nothing else catches that —
      // every region in the six is wider than its mask, so an over-large one
      // clips exactly as much as a correct one, which is nothing. Measured:
      // both that mutation and swapping the viewBox's two numbers survived the
      // whole suite before this test existed.
      //
      // Same construction as the test above, at 2x. The region's left edge is
      // at user 12, so it is at device 24 — and a region resolved against the
      // 160-pixel target would put it at 32, leaving x=28 empty.
      RasterImage renderAt(int side) => rasterizeScene(
        scene(
          shape: const [
            SvgAttribute('filter', 'url(#f)'),
            SvgAttribute('d', 'M-200 -200H200V200H-200z'),
            SvgAttribute('fill', '#FFFFFF'),
            SvgAttribute('transform', 'translate(20 0)'),
          ],
          sigma: 1,
          background: null,
        ),
        width: side,
        height: side,
      );
      int alphaAt(RasterImage i, int side, int x, int y) =>
          i.bytes[(y * side + x) * 4 + 3];

      final two = renderAt(160);
      expect(
        alphaAt(two, 160, 20, 80),
        0,
        reason: 'device x=20 is left of the region, which starts at 24',
      );
      expect(
        alphaAt(two, 160, 28, 80),
        greaterThan(0),
        reason:
            'device x=28 is inside it — a region resolved against the '
            'target rather than the viewBox would start at 32 and leave this '
            'empty',
      );
    });

    test('clips the output — a region that cuts really does cut', () {
      // Inert for `marble`: its region is (-8, -8, 96, 96) and the mask is
      // 0…80, so anything the region would remove the mask has removed
      // already. That makes the clip untestable from the variant, which is
      // exactly the "value nothing reads" case — so it is constructed here.
      final clipped = rasterizeScene(
        scene(
          shape: const [
            SvgAttribute('filter', 'url(#f)'),
            SvgAttribute('d', 'M20 20H60V60H20z'),
            SvgAttribute('fill', '#FFFFFF'),
          ],
          filter: const [
            SvgAttribute('id', 'f'),
            SvgAttribute('filterUnits', 'userSpaceOnUse'),
            SvgAttribute('color-interpolation-filters', 'sRGB'),
            SvgAttribute('x', 30),
            SvgAttribute('y', 0),
            SvgAttribute('width', 80),
            SvgAttribute('height', 80),
          ],
          background: null,
        ),
        width: 80,
        height: 80,
      );
      // Left of x = 30 the filter output is cut away entirely …
      expect(clipped.bytes[(40 * 80 + 20) * 4 + 3], 0);
      expect(clipped.bytes[(40 * 80 + 29) * 4 + 3], 0);
      // … and to the right of it the blur is untouched, because the region
      // clips the OUTPUT and not the source. Measured in Chrome: a bar
      // spanning x = -40…20 inside a region starting at x = 6 renders
      // identically to an unclipped one at every x >= 6.
      final unclipped = rasterizeScene(
        scene(
          shape: const [
            SvgAttribute('filter', 'url(#f)'),
            SvgAttribute('d', 'M20 20H60V60H20z'),
            SvgAttribute('fill', '#FFFFFF'),
          ],
          background: null,
        ),
        width: 80,
        height: 80,
      );
      for (var x = 31; x < 80; x++) {
        expect(
          clipped.bytes[(40 * 80 + x) * 4 + 3],
          unclipped.bytes[(40 * 80 + x) * 4 + 3],
          reason: 'x=$x is inside the region and must be unaffected',
        );
      }
    });

    test('and marble\'s own region does not cut anything', () {
      // The claim above, cashed on the real variant: the region is inert here,
      // and this is what fails the day a viewBox or a mask changes that.
      final withRegion = rasterizeScene(
        buildMarbleScene(
          title: true,
          name: 'Clara Barton',
          colors: palette,
          size: 80,
        ),
        width: 80,
        height: 80,
      );
      final withHugeRegion = rasterizeScene(
        _widenFilterRegion(
          buildMarbleScene(
            title: true,
            name: 'Clara Barton',
            colors: palette,
            size: 80,
          ),
        ),
        width: 80,
        height: 80,
      );
      expect(withRegion.bytes, withHugeRegion.bytes);
    });
  });

  group('the scene seam still refuses what it cannot draw', () {
    SvgNode marble() => buildMarbleScene(
      title: true,
      name: 'Clara Barton',
      colors: palette,
      size: 80,
    );

    test('a filter chain that is not upstream\'s is refused, not reduced', () {
      // The three primitives are collapsed to "blur by sigma" only because the
      // first two are checked to be the no-ops they look like.
      expect(
        () => rasterizeScene(
          _editFilterPrimitive(marble(), 0, const [
            SvgAttribute('flood-opacity', 1),
            SvgAttribute('result', 'BackgroundImageFix'),
          ]),
          width: 80,
          height: 80,
        ),
        throwsA(isA<UnsupportedSceneError>()),
        reason: 'a flood that paints is a background we would be dropping',
      );
      expect(
        () => rasterizeScene(
          _editFilterPrimitive(marble(), 1, const [
            SvgAttribute('in', 'SomethingElse'),
            SvgAttribute('in2', 'BackgroundImageFix'),
            SvgAttribute('result', 'shape'),
          ]),
          width: 80,
          height: 80,
        ),
        throwsA(isA<UnsupportedSceneError>()),
      );
    });

    test('linearRGB is refused — the SVG default is not what we implement', () {
      expect(
        () => rasterizeScene(
          _editFilterAttribute(
            marble(),
            'color-interpolation-filters',
            'linearRGB',
          ),
          width: 80,
          height: 80,
        ),
        throwsA(isA<UnsupportedSceneError>()),
      );
    });

    test('objectBoundingBox filterUnits is refused', () {
      expect(
        () => rasterizeScene(
          _editFilterAttribute(marble(), 'filterUnits', 'objectBoundingBox'),
          width: 80,
          height: 80,
        ),
        throwsA(isA<UnsupportedSceneError>()),
      );
    });

    test('a filter reference with no filter is refused, not ignored', () {
      // A browser draws the element **unfiltered** here, so ignoring it draws
      // a sharp blob where upstream draws a blurred one.
      expect(
        () => rasterizeScene(
          _editFilterAttribute(marble(), 'id', 'somethingelse'),
          width: 80,
          height: 80,
        ),
        throwsA(isA<UnsupportedSceneError>()),
      );
    });

    test('the three chain guards nothing was exercising', () {
      // The #41 refuting lens deleted each of these with `if (false)` and the
      // whole suite stayed green — a half-covered seam, five of its guards
      // tested and four not. They all *work*; reproduced before writing this,
      // which is worth saying because the lens reported the third one as a
      // live wrong picture ("renders sharp rather than being refused") and it
      // does not: it throws.
      SvgNode withPrimitives(List<SvgNode> primitives) => _editFilterChildren(
        buildMarbleScene(
          title: true,
          name: 'Clara Barton',
          colors: palette,
          size: 80,
        ),
        primitives,
      );

      // `feBlend mode="multiply"` is a real compositing step, not the no-op
      // the chain is reduced away on the strength of.
      expect(
        () => rasterizeScene(
          withPrimitives(const [
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
                SvgAttribute('mode', 'multiply'),
                SvgAttribute('result', 'shape'),
              ],
            ),
            SvgNode(
              SvgElement.feGaussianBlur,
              attributes: [
                SvgAttribute('stdDeviation', 7),
                SvgAttribute('result', 'e'),
              ],
            ),
          ]),
          width: 80,
          height: 80,
        ),
        throwsA(isA<UnsupportedSceneError>()),
      );

      // A blur reading the flood instead of the blend is filtering a different
      // image — a fully transparent one, so the element would vanish.
      expect(
        () => rasterizeScene(
          withPrimitives(const [
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
            SvgNode(
              SvgElement.feGaussianBlur,
              attributes: [
                SvgAttribute('in', 'BackgroundImageFix'),
                SvgAttribute('stdDeviation', 7),
                SvgAttribute('result', 'e'),
              ],
            ),
          ]),
          width: 80,
          height: 80,
        ),
        throwsA(isA<UnsupportedSceneError>()),
      );

      // A negative sigma would make `gaussianBoxSize` negative and `d <= 1`,
      // which skips the blur — so the element would render **sharp** rather
      // than refusing. That is the wrong-picture failure this seam exists for.
      expect(
        () => rasterizeScene(
          withPrimitives(const [
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
            SvgNode(
              SvgElement.feGaussianBlur,
              attributes: [
                SvgAttribute('stdDeviation', -7),
                SvgAttribute('result', 'e'),
              ],
            ),
          ]),
          width: 80,
          height: 80,
        ),
        throwsA(isA<UnsupportedSceneError>()),
      );
    });

    test('an inline style we do not implement is refused', () {
      expect(
        () => rasterizeScene(
          _replaceStyle(marble(), 'mix-blend-mode:multiply'),
          width: 80,
          height: 80,
        ),
        throwsA(isA<UnsupportedSceneError>()),
      );
      // Including one that merely *contains* the declaration we know: a
      // substring match would let the second declaration through unread.
      expect(
        () => rasterizeScene(
          _replaceStyle(marble(), 'mix-blend-mode:overlay;opacity:0.5'),
          width: 80,
          height: 80,
        ),
        throwsA(isA<UnsupportedSceneError>()),
      );
    });
  });

  group(
    'an empty palette draws nothing, and that is not frozen as a golden',
    () {
      test('every pixel is fully transparent', () {
        // All three fills are dropped, so there is no image — asserted as
        // behaviour rather than committed as a blank file, which is the failure
        // #40 found in `sunset`.
        final image = rasterizeScene(
          buildMarbleScene(
            title: true,
            name: 'Clara Barton',
            colors: const [],
            size: 80,
          ),
          width: 80,
          height: 80,
        );
        for (var i = 0; i < image.bytes.length; i++) {
          expect(image.bytes[i], 0, reason: 'byte $i');
        }
      });
    },
  );

  group('determinism', () {
    test('the same input produces identical bytes on every run', () {
      final a = rasterizeScene(
        buildMarbleScene(
          title: true,
          name: 'Clara Barton',
          colors: palette,
          size: 80,
        ),
        width: 80,
        height: 80,
      );
      final b = rasterizeScene(
        buildMarbleScene(
          title: true,
          name: 'Clara Barton',
          colors: palette,
          size: 80,
        ),
        width: 80,
        height: 80,
      );
      expect(a.bytes, b.bytes);
    });
  });

  group('goldens lock the verified state', () {
    final cases = goldenCasesFor('marble');

    test('the roster is not empty, and it is marble\'s', () {
      expect(cases.keys, hasLength(4));
      expect(cases.keys, everyElement(startsWith('marble-')));
    });

    for (final entry in cases.entries) {
      test('${entry.key} is byte-identical', () {
        final (sceneNode, size) = entry.value;
        final ours = rasterizeScene(sceneNode, width: size, height: size);
        final golden = File('test/goldens/${entry.key}.rgba').readAsBytesSync();
        expectGoldenIdentical(
          RgbaImage(size, size, ours.bytes),
          RgbaImage(size, size, golden),
          reason: entry.key,
        );
      });
    }

    test('the four goldens are four different images', () {
      // A generator bug writing one render four times would satisfy every
      // other assertion in this group.
      final digests = <String>{};
      for (final entry in cases.entries) {
        digests.add(
          File('test/goldens/${entry.key}.rgba').readAsBytesSync().join(','),
        );
      }
      expect(digests, hasLength(4));
    });
  });
}

/// Removes the inline `style` from every element.
SvgNode _stripStyle(SvgNode n) => SvgNode(
  n.element,
  attributes: [
    for (final a in n.attributes)
      if (a.name != 'style') a,
  ],
  text: n.text,
  children: [for (final c in n.children) _stripStyle(c)],
);

/// Replaces the inline `style` wherever one is declared.
SvgNode _replaceStyle(SvgNode n, String value) => SvgNode(
  n.element,
  attributes: [
    for (final a in n.attributes)
      if (a.name == 'style') SvgAttribute('style', value) else a,
  ],
  text: n.text,
  children: [for (final c in n.children) _replaceStyle(c, value)],
);

/// Sets an attribute on the `<filter>` element.
SvgNode _editFilterAttribute(SvgNode n, String name, String value) => SvgNode(
  n.element,
  attributes: n.element == SvgElement.filter
      ? [
          for (final a in n.attributes)
            if (a.name == name) SvgAttribute(name, value) else a,
        ]
      : n.attributes,
  text: n.text,
  children: [for (final c in n.children) _editFilterAttribute(c, name, value)],
);

/// Replaces the attributes of the filter's [index]-th primitive.
SvgNode _editFilterPrimitive(
  SvgNode n,
  int index,
  List<SvgAttribute> attributes,
) => SvgNode(
  n.element,
  attributes: n.attributes,
  text: n.text,
  children: [
    for (var i = 0; i < n.children.length; i++)
      if (n.element == SvgElement.filter && i == index)
        SvgNode(n.children[i].element, attributes: attributes)
      else
        _editFilterPrimitive(n.children[i], index, attributes),
  ],
);

/// Gives the `<filter>` a region large enough to clip nothing.
SvgNode _widenFilterRegion(SvgNode n) => SvgNode(
  n.element,
  attributes: n.element == SvgElement.filter
      ? [
          ...n.attributes,
          const SvgAttribute('x', -500),
          const SvgAttribute('y', -500),
          const SvgAttribute('width', 1000),
          const SvgAttribute('height', 1000),
        ]
      : n.attributes,
  text: n.text,
  children: [for (final c in n.children) _widenFilterRegion(c)],
);

/// Replaces the `<filter>`'s primitive list.
SvgNode _editFilterChildren(SvgNode n, List<SvgNode> primitives) => SvgNode(
  n.element,
  attributes: n.attributes,
  text: n.text,
  children: n.element == SvgElement.filter
      ? primitives
      : [for (final c in n.children) _editFilterChildren(c, primitives)],
);
