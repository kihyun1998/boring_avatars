import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:boring_avatars/boring_avatars.dart';
import 'package:boring_avatars/src/widget/boring_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderImage;
import 'package:flutter_test/flutter_test.dart';

import 'support/golden_cases.dart';

/// `BoringAvatar` — the consumer seam (#80).
///
/// **What this file cannot reach, named rather than left blank.** Everything the
/// widget does *after* its raster starts is unpumpable under the test binding:
/// the raster lives in the fake-async zone while `compute` and
/// `decodeImageFromPixels` complete on real callbacks, and all three pump
/// arrangements were measured shut (see [_bytesOnScreen] below for the numbers).
/// Four behaviours therefore have no test here and are verified by reading:
///
/// - `_rasterFailed` — that a failed raster is reported through
///   `FlutterError.reportError` and that the **stale image is dropped**, so a
///   widget whose fields say `beam` stops drawing the `pixel` it used to be. The
///   error itself surviving the isolate hop *is* tested, one group down.
/// - `_drawLatest`'s **one-raster-at-a-time** bound. Before the raster moved off
///   `build()` this was structural; now it is a flag, and a flag is the kind of
///   thing a test should hold.
/// - Dropping the on-screen image when the *picture* changes but keeping it when
///   only the resolution does. Both branches need an `_image` to exist first,
///   and one never arrives here.
/// - The widget-level leak proof, which [_noLeak] already records as covering
///   the function and not the widget.
///
/// Tracked on #80 rather than quietly assumed. The seam that would make them
/// testable — an injected decoder, or a test-only hook in `lib/` — is a
/// judgement about public surface and is not taken here.
void main() {
  _bytesOnScreen();
  _noLeak();

  const palette = ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'];

  Widget wrap(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: child),
  );

  group('the palette this surface accepts is narrower, and it says so', () {
    // **Derived, not chosen.** A colour the raster path cannot read would draw
    // a **blank** avatar rather than fail — the "plausible wrong picture"
    // `scene_raster.dart`'s header names as the thing that seam exists to stop
    // — so the widget rejects at the seam and names the argument, which is what
    // `avatar.dart:141` already does for `size` (S-4) and what S-2 does for an
    // empty `beam` palette.
    //
    // **The gap this guarded is now closed, in three additive steps.** #62
    // took the hex forms, #63 the names and the legacy functions, and #95 the
    // Color 4 remainder — `hwb()`, `lab()`/`lch()`, `oklab()`/`oklch()`,
    // `color()` and the system colours — so what stays refused is only what
    // no grammar admits, plus the `none`-component forms #95 recorded as out
    // of scope. Hidden-state #20 called the narrow set a *gap* rather than a
    // contract, and it was: no palette that worked at any point stopped
    // working.
    for (final bad in const ['zzz', 'rgb(255,0)', 'hsv(0,100%,50%)', '']) {
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

    // **The other half of the widening, and the half a shorter reject-list
    // cannot state.** Dropping two entries above proves only that nothing
    // throws where it used to; it does not say the widget now *accepts* them,
    // which is the behaviour a caller actually gets. A build that widened
    // `parseHexColour` and forgot to widen this guard would pass the list above
    // and fail here.
    for (final good in const [
      '#F00',
      '#f00',
      '#FF000080',
      '#F008',
      '#FF00',
      'red',
      'REBECCAPURPLE',
      ' transparent ',
      'currentColor',
      'rgb(255, 0, 0)',
      'rgba(255 0 0 / 50%)',
      'hsl(120, 100%, 25%)',
      'hsla(0 100% 50% / 0.5)',
      // #95's families — the guard reads `parseCssColour`, so learning them
      // widened this seam with no widget change; this is the pin that says so.
      'hwb(120 30% 20%)',
      'lab(50% 40 59.5)',
      'lch(52.2% 72.2 50)',
      'oklab(0.7 0.1 0.1)',
      'oklch(0.7 0.15 200)',
      'color(display-p3 1 0 0)',
      'AccentColor',
      'Highlight',
    ]) {
      testWidgets('"$good" is accepted, because a browser draws it', (
        tester,
      ) async {
        await tester.pumpWidget(
          wrap(
            BoringAvatar(
              name: 'Clara Barton',
              colors: [good],
              size: 80,
              version: BoringAvatarsVersion.v1_6_1,
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: good);
      });
    }

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

  group('a parent tighter than `size` puts Flutter\'s sampler back in', () {
    // **Measured, because the README makes a claim next to it.** The
    // determinism guarantee is about the image this package *produces*: drawn
    // at the box's own physical size and handed over with `FilterQuality.none`,
    // so nothing resamples it. A parent that squeezes the box is a different
    // thing, and it is outside the package — but "outside the package" is worth
    // nothing as an assertion if the boundary was never located.
    //
    // `rendering/image.dart:352` is where it happens:
    // `BoxConstraints.tightFor(width: _width, height: _height).enforce(constraints)`
    // — `enforce` lets the *parent* win, so a 240-pixel image asked to live in
    // 20 logical pixels lays out at 20 and is drawn scaled. There is no identity
    // fast path in `paintImage`; it always goes through `drawImageRect`.

    testWidgets('the widget yields its own size to a tighter parent', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 20,
            height: 20,
            child: BoringAvatar(
              name: 'Clara Barton',
              colors: palette,
              size: 240,
              version: BoringAvatarsVersion.v1_6_1,
              variant: BoringAvatarsVariant.pixel,
            ),
          ),
        ),
      );
      // Not 240. The widget asks; the parent decides.
      expect(tester.getSize(find.byType(BoringAvatar)), const Size(20, 20));
    });

    testWidgets('and a real image in that box is drawn scaled, not clipped', (
      tester,
    ) async {
      late final ui.Image image;
      await tester.runAsync(() async {
        image = await rasterAvatarImage(
          name: 'Clara Barton',
          colors: palette,
          pixels: 240,
          version: BoringAvatarsVersion.v1_6_1,
          variant: BoringAvatarsVariant.pixel,
          square: false,
        );
      });
      addTearDown(image.dispose);

      // The image already exists, so this pump has no zone to bridge — which is
      // why this case is testable when the widget's own raster is not.
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 20,
            height: 20,
            child: RawImage(
              image: image,
              width: 240,
              height: 240,
              filterQuality: FilterQuality.none,
            ),
          ),
        ),
      );

      final render = tester.renderObject<RenderImage>(find.byType(RawImage));
      expect(image.width, 240, reason: 'the image really is 240 physical');
      expect(
        render.size,
        const Size(20, 20),
        reason:
            '240 physical pixels into a 20-logical box is a 12:1 downscale, '
            'and that resampling is Flutter\'s, not ours',
      );
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
