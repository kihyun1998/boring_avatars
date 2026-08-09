import 'dart:io';
import 'dart:ui' as ui;

import 'package:boring_avatars/boring_avatars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden_cases.dart';

/// `BoringAvatar` — the consumer seam (#80).
void main() {
  _bytesOnScreen();

  const palette = ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'];

  Widget wrap(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: child),
  );

  group('the palette this surface accepts is narrower, and it says so', () {
    // **Derived, not chosen.** `boringAvatarSvg` passes a colour through to the
    // document and a browser draws it, so `red` works there. The rasterizer
    // reads `#RRGGBB` and nothing else yet (#62/#63 widen it), and measured on
    // the branch: `red` makes five variants draw a **blank** and `sunset`
    // throw. A blank is the "plausible wrong picture" `scene_raster.dart`'s
    // header names as the thing that seam exists to stop, and hidden-state #20
    // records that the narrow set is a **gap** rather than a contract — its own
    // premise was measured false in #62.
    //
    // So the widget rejects at the seam and names the argument, which is what
    // `avatar.dart:141` already does for `size` (S-4) and what S-2 does for an
    // empty `beam` palette. #62/#63 later *widen* what is accepted, which is
    // additive: a palette that works keeps working.
    for (final bad in const ['red', '#F00', 'rgb(255,0,0)', '#FF000080', '']) {
      testWidgets('"$bad" is refused, naming colors', (tester) async {
        await tester.pumpWidget(
          wrap(
            BoringAvatar(
              name: 'Clara Barton',
              colors: [bad],
              size: 80,
              version: BoringAvatarsVersion.v1_6_1,
            ),
          ),
        );
        final error = tester.takeException();
        expect(
          error,
          isA<ArgumentError>().having((e) => e.name, 'name', 'colors'),
          reason: 'a colour the raster path cannot read must not draw a blank',
        );
      });
    }

    testWidgets('the hex palette upstream ships is accepted', (tester) async {
      await tester.pumpWidget(
        wrap(
          BoringAvatar(
            name: 'Clara Barton',
            colors: palette,
            size: 80,
            version: BoringAvatarsVersion.v1_6_1,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty palette is not a bad colour', (tester) async {
      // Five variants render an avatar with colours missing and `beam` throws,
      // because upstream throws there — ruling S-2. The palette check must not
      // turn that into a *colours* error, which would rename a divergence the
      // ledger already settled.
      await tester.pumpWidget(
        wrap(
          BoringAvatar(
            name: 'Clara Barton',
            colors: const [],
            size: 80,
            version: BoringAvatarsVersion.v1_6_1,
            variant: BoringAvatarsVariant.pixel,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// Step 4's proof for this layer: the bytes the widget actually put on the
/// screen, against the goldens the rasterizer's own tests pin.
///
/// **`rawRgba`, and the golden premultiplied to meet it.** `Image.toByteData`'s
/// `rawRgba` is premultiplied and our buffer is straight, so this is where the
/// hand-off multiply is checked rather than assumed. `rawStraightRgba` is *not*
/// the comparison format: un-premultiplying a rounded byte is lossy
/// (`raster.dart:22-23`), which is hidden-state #29's trap wearing a different
/// hat.
///
/// **Why only the `clara-*` cases.** `goldenCases` holds *built scenes*, not the
/// inputs they were built from, so there is no way to hand the widget the same
/// name and palette for `alice-pair`, `empty-name`, `hangul` or
/// `empty-palette`. The eleven `clara-*` entries all share one pair, which is
/// why they are reachable. Putting the inputs beside the cases would cover the
/// rest and is a refactor of a file six raster tests and the golden generator
/// share — worth doing, not worth doing here.
void _bytesOnScreen() {
  const claraPalette = ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'];

  final clara = goldenCases.keys
      .where((k) => k.startsWith(RegExp(r'.*-clara-')))
      .toList();

  test('the sweep below is not empty and is every clara case', () {
    // A `where` that matched nothing would make every test below vanish
    // silently rather than fail.
    expect(clara, hasLength(11));
    expect(
      clara.where((k) => k.endsWith('-square')),
      hasLength(5),
      reason: 'pixel-clara-square does not exist — see #80',
    );
  });

  for (final key in clara) {
    final variantName = key.split('-').first;
    final square = key.endsWith('-square');

    testWidgets('$key reaches the screen byte-identical', (tester) async {
      // A device pixel ratio of exactly 1 is what makes the logical size and
      // the golden's own viewBox the same number. Every other ratio is #58's
      // scale, which has no golden to compare against.
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final (_, side) = goldenCases[key]!;
      final golden = File('test/goldens/$key.rgba').readAsBytesSync();

      // **`runAsync`, not `pumpAndSettle`.** The rasterisation is ordinary CPU
      // work and `decodeImageFromPixels` completes on a real engine callback;
      // neither is a fake-async timer, so the test binding's clock cannot
      // advance either. `pumpAndSettle` returns with the image still null and
      // the tree holding no `RawImage` at all.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: BoringAvatar(
              name: 'Clara Barton',
              colors: claraPalette,
              size: side.toDouble(),
              version: BoringAvatarsVersion.v1_6_1,
              variant: BoringAvatarsVariant.fromUpstreamName(variantName),
              square: square,
            ),
          ),
        ),
      );

      // **`pump` outside, waiting inside.** `pumpWidget` and `pump` drive the
      // binding's fake clock and must run in the test zone; calling either
      // inside `runAsync` deadlocks — measured, it hangs the whole file rather
      // than failing. So the tree is pumped here, the *real* async work is
      // awaited in `runAsync`, and a second pump picks up the `setState`.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      // **One pump, deliberately, and this test currently FAILS here.**
      //
      // Measured while writing it, and all three are dead ends:
      //   * `pumpWidget` inside `runAsync` deadlocks — a single test ran past
      //     seven minutes without failing.
      //   * one pump after `runAsync` reaches this line with no `RawImage`,
      //     which is the honest failure below.
      //   * a *second* pump hangs again — 3m30 to "did not complete".
      // And `decodeImageFromPixelsSync`, which would delete the async surface
      // entirely, is `not implemented on Skia` — measured, and the test backend
      // is Skia.
      //
      // So the widget's raster is started from `build()`, in the test zone,
      // while its completion needs the real one, and no arrangement of pumps
      // bridges that. Fixing it is a change to the *widget*, not to this test —
      // see #80. One pump is kept because a test that fails in a second is a
      // gate and a test that hangs is not.
      await tester.pump();

      expect(
        find.byType(RawImage),
        findsOneWidget,
        reason: 'the image never arrived',
      );

      final raw = tester.widget<RawImage>(find.byType(RawImage));
      final actual = (await raw.image!.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();

      expect(actual.length, golden.length, reason: 'size');
      var worst = 0;
      for (var i = 0; i < golden.length; i += 4) {
        final a = golden[i + 3];
        for (var c = 0; c < 3; c++) {
          final expected = (golden[i + c] * a + 127) ~/ 255;
          final d = (actual[i + c] - expected).abs();
          if (d > worst) worst = d;
        }
        expect(actual[i + 3], a, reason: 'pixel ${i ~/ 4} alpha');
      }
      expect(worst, 0, reason: 'worst premultiplied channel delta');
    });
  }
}
