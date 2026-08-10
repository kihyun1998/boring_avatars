import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:boring_avatars/boring_avatars.dart';
import 'package:boring_avatars/src/widget/boring_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden_cases.dart';

/// `BoringAvatar` — the consumer seam (#80).
void main() {
  _bytesOnScreen();
  _noLeak();

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

    testWidgets('an empty beam palette still reaches the caller', (
      tester,
    ) async {
      // **S-2's only cell, and it was the one the sweep above never ran.**
      // `avatar.dart` promises an `ArgumentError` for `beam` with an empty
      // palette; before this, the widget's raster threw into the zone and the
      // caller learned nothing. Taken through `rasterAvatarImage` because that
      // is where the error now has to survive an isolate hop — `compute`
      // forwards it, and this is what says so rather than assuming it.
      await tester.runAsync(() async {
        await expectLater(
          rasterAvatarImage(
            name: 'Clara Barton',
            colors: const [],
            pixels: 36,
            version: BoringAvatarsVersion.v1_6_1,
            variant: BoringAvatarsVariant.beam,
            square: false,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
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

  group('a size that is not a size is refused, naming the argument', () {
    Widget atRatio(double dpr, Widget child) => MediaQuery(
      data: MediaQueryData(devicePixelRatio: dpr),
      child: wrap(child),
    );

    Widget avatar(double size) => BoringAvatar(
      name: 'Clara Barton',
      colors: palette,
      size: size,
      version: BoringAvatarsVersion.v1_6_1,
      variant: BoringAvatarsVariant.pixel,
    );

    // **These reached `.round()` before the guard.** `Infinity` and `NaN` came
    // out as `UnsupportedError: Infinity or NaN toInt` — an internal conversion,
    // no argument named — which is the exact counterexample to S-4, whose whole
    // reason was that otherwise it blows up deeper down naming an internal type.
    // An unbounded `BoxConstraints.maxWidth` is where a caller gets one.
    for (final (label, bad) in const <(String, double)>[
      ('infinity', double.infinity),
      ('negative infinity', double.negativeInfinity),
      ('NaN', double.nan),
      ('zero', 0.0),
      ('negative', -80.0),
    ]) {
      testWidgets('$label is refused', (tester) async {
        await tester.pumpWidget(atRatio(3, avatar(bad)));
        expect(
          tester.takeException(),
          isA<ArgumentError>().having((e) => e.name, 'name', 'size'),
        );
      });
    }

    testWidgets('a positive size that rounds away says *that*', (tester) async {
      // Not "must be positive" — it is positive. The device is what makes it
      // vanish, and a message that misdescribes the input sends the reader to
      // the wrong argument.
      await tester.pumpWidget(atRatio(1, avatar(0.1)));
      final error = tester.takeException();
      expect(error, isA<ArgumentError>().having((e) => e.name, 'name', 'size'));
      expect((error as ArgumentError).message, contains('rounds to'));
      expect(error.message, isNot(contains('must be positive')));
    });

    testWidgets('a size that survives the ratio is accepted', (tester) async {
      await tester.pumpWidget(atRatio(2.625, avatar(40)));
      expect(tester.takeException(), isNull);
    });
  });
}

/// Step 4's proof for this layer: the bytes the hand-off actually produces,
/// against the goldens the rasterizer's own tests pin.
///
/// **Through [rasterAvatarImage], not through the widget, and that is not a
/// dodge.** What Step 4 asks to see is the `ui.Image` this layer hands to
/// Flutter; the widget is the thing that decides *when* to make one. Taking the
/// proof through `pumpWidget` is not merely awkward, it was measured
/// impossible: a raster started from `build()` lives in the test binding's
/// fake-async zone while `decodeImageFromPixels` completes on a real callback.
/// `pumpWidget` inside `runAsync` deadlocked past seven minutes; one pump after
/// it arrived with no image; two pumps hung again at 3m30. And
/// `decodeImageFromPixelsSync`, which would have removed the callback, is
/// "not implemented on Skia" — the test backend. A future *created inside*
/// `runAsync` has none of that, which is what this does.
///
/// **`rawRgba`, and the golden premultiplied to meet it.** `toByteData`'s
/// `rawRgba` is premultiplied and our buffer is straight, so this is where the
/// hand-off multiply is checked rather than assumed. `rawStraightRgba` is not
/// the comparison format: un-premultiplying a rounded byte is lossy
/// (`raster.dart:22-23`), hidden-state #29's trap in another hat.
///
/// **Why only the `clara-*` cases.** `goldenCases` holds *built scenes*, not the
/// inputs they were built from, so `alice-pair`, `empty-name`, `hangul` and
/// `empty-palette` cannot be reproduced from here. The twelve `clara-*` entries
/// share one pair, and they are the whole six-by-two grid. Putting the inputs beside the cases would reach the rest and
/// is a refactor of a file six raster tests and the golden generator share.
void _bytesOnScreen() {
  const claraPalette = ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'];

  final clara = goldenCases.keys.where((k) => k.contains('-clara-')).toList();

  test('the sweep below is not empty and is every clara case', () {
    // A `where` that matched nothing would make every case below vanish
    // silently rather than fail.
    expect(clara, hasLength(12));
    expect(
      clara.where((k) => k.endsWith('-square')),
      hasLength(6),
      reason:
          'six variants, both square states — pixel-clara-square was the '
          'missing one and #80 generated it',
    );
  });

  for (final key in clara) {
    final variantName = key.split('-').first;
    final square = key.endsWith('-square');

    testWidgets('$key is handed to Flutter byte-identical', (tester) async {
      final (_, side) = goldenCases[key]!;
      final golden = File('test/goldens/$key.rgba').readAsBytesSync();

      late Uint8List actual;
      await tester.runAsync(() async {
        final image = await rasterAvatarImage(
          name: 'Clara Barton',
          colors: claraPalette,
          pixels: side,
          version: BoringAvatarsVersion.v1_6_1,
          variant: BoringAvatarsVariant.fromUpstreamName(variantName),
          square: square,
        );
        actual = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        image.dispose();
      });

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

/// The hand-off does not leak a `ui.Image` (#80).
///
/// `ui.Image.onCreate` and `onDispose` are static hooks the engine calls, so
/// the count needs no framework support.
///
/// **This proves the function, not the widget, and the gap is deliberate.**
/// A widget-level leak test would have to pump one, and a raster started from
/// `build()` never completes under the test binding — the same zone wall the
/// byte proof above documents. So what is asserted here is that an image
/// obtained from [rasterAvatarImage] is releasable and released; that the
/// *widget* releases the ones it holds across a rebuild and an unmount is
/// still unproven, and is tracked on #80 rather than quietly assumed.
void _noLeak() {
  testWidgets('every image the hand-off creates can be released', (
    tester,
  ) async {
    var created = 0, disposed = 0;
    final priorCreate = ui.Image.onCreate;
    final priorDispose = ui.Image.onDispose;
    ui.Image.onCreate = (_) => created++;
    ui.Image.onDispose = (_) => disposed++;
    addTearDown(() {
      ui.Image.onCreate = priorCreate;
      ui.Image.onDispose = priorDispose;
    });

    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        final image = await rasterAvatarImage(
          name: 'Clara Barton',
          colors: const ['#92A1C6', '#146A7C'],
          pixels: 40,
          version: BoringAvatarsVersion.v1_6_1,
          variant: BoringAvatarsVariant.pixel,
          square: false,
        );
        image.dispose();
      }
    });

    // A hook that never fired would leave both at zero and pass a `==`.
    expect(created, 3, reason: 'the hooks did not fire');
    expect(disposed, created, reason: 'an image outlived its caller');
  });
}
