import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:boring_avatars/boring_avatars.dart';
import 'package:boring_avatars/src/widget/boring_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
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
  _pixelSnap();
  _resampleFallback();

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

    // **This case builds what the widget actually builds.** It used to build a
    // `RawImage`, which stopped being the widget's path at #110 — leaving a
    // test of the SDK where a test of this package was meant to be. The
    // squeeze is the reason `PixelSnappedImage` takes its extent from the box
    // rather than from the buffer.
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
            child: PixelSnappedImage(image: image, devicePixelRatio: 1),
          ),
        ),
      );

      final render = tester.renderObject<RenderPixelSnappedImage>(
        find.byType(PixelSnappedImage),
      );
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
    expect(clara, hasLength(13));
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
    // The golden roster names the drawing, the widget names the version —
    // `pixel-clara-second-index` is the 1.10.1 colour index, which only
    // `v1_10_1` (or `latest`) reaches through the public surface.
    final version = key.endsWith('-second-index')
        ? BoringAvatarsVersion.v1_10_1
        : BoringAvatarsVersion.v1_6_1;

    testWidgets('$key is handed to Flutter byte-identical', (tester) async {
      final (_, side) = goldenCases[key]!;
      final golden = File('test/goldens/$key.rgba').readAsBytesSync();

      late Uint8List actual;
      await tester.runAsync(() async {
        final image = await rasterAvatarImage(
          name: 'Clara Barton',
          colors: claraPalette,
          pixels: side,
          version: version,
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

/// The avatar occupies exactly the physical pixels it was rasterised for,
/// wherever layout puts it (#110).
///
/// **The defect this pins, measured rather than described.** `pixels` is baked
/// at `(size * dpr).round()`, and the old arrangement painted that buffer into
/// a box of `size * dpr` *unrounded* device pixels. When those two disagree
/// **and** the box's origin lands on a fractional device pixel,
/// `FilterQuality.none` resolves the mismatch by nearest neighbour — which
/// drops or duplicates a whole column instead of blending it.
///
/// **Both halves are needed and neither is sufficient**, which is why the sweep
/// below carries the passing rows too. Measured at `size: 45`, as the painted
/// extent in device pixels:
///
/// | ratio | inset | buffer | before | after |
/// |---|---|---|---|---|
/// | 1.25 | 15.5 | 56 | **57** — a column duplicated | 56 |
/// | 1.5 | 15 | 68 | **67** — a column dropped | 68 |
/// | 1.75 | 15.25 | 79 | **78** — dropped | 79 |
/// | 2.625 | 15 | 118 | **119** — duplicated | 118 |
/// | 2.0 | 15.25 | 90 | 90 — `45 × 2` is already whole | 90 |
/// | 1.5 | 16 | 68 | 68 — `16 × 1.5` is already whole | 68 |
///
/// The last two rows are what make the condition a conjunction: a fractional
/// origin under a whole ratio is absorbed, and so is a fractional size at a
/// whole origin; only together do they cost a column.
///
/// A duplicated column at the leftmost point of a disc is a two-pixel constant
/// run where the true outline is a curve, and a dropped one is a hard cut —
/// both read on screen as the flat vertical chord #110 reported. Every
/// non-`square` variant is tangent to all four edges of its box with **zero**
/// margin, so this package has no interior padding to hide the loss in.
///
/// **The ancestor is a swept parameter, not a fixed backdrop, and that is the
/// correction this file's first draft needed.** The sweep originally held the
/// layer structure at its benign value — one repaint boundary, at the origin —
/// and so could not see that `paint`'s `offset` is relative to the enclosing
/// *layer* rather than the screen. `ListView` wraps every child in a
/// `RepaintBoundary`, and `Opacity` and `FadeTransition` push layers of their
/// own; under any of them the snap was reading zero and the defect was intact
/// while all thirteen rows stayed green. `lessons.md` names the shape: *"there
/// is no missing case in a list of cases; there is a parameter that was never
/// varied"* (#83).
void _pixelSnap() {
  /// An opaque `n × n` image.
  ///
  /// **Opaque and solid on purpose.** The assertions are a bounding box, a
  /// position and a partial-alpha count, and all three are exact only when
  /// every source pixel is 255; a disc would turn the same measurement into a
  /// question about alpha profiles, which is the harder thing to read and the
  /// weaker thing to assert.
  Future<ui.Image> opaqueSquare(int n) async {
    final bytes = Uint8List(n * n * 4);
    for (var i = 0; i < n * n; i++) {
      bytes[i * 4] = 255;
      bytes[i * 4 + 3] = 255;
    }
    final decoded = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      n,
      n,
      ui.PixelFormat.rgba8888,
      decoded.complete,
    );
    return decoded.future;
  }

  /// Every layer-creating ancestor an avatar realistically sits under.
  ///
  /// Each pushes a layer whose own origin carries the fractional part, leaving
  /// the child to be painted at a rounder offset than it really has. They are
  /// the parameter the first draft of this sweep held constant.
  const ancestors = <String, Widget Function(Widget child)>{
    'no layer between': _itself,
    'under a RepaintBoundary — what ListView gives every child':
        _underRepaintBoundary,
    'under an Opacity — what a fade-in gives it': _underOpacity,
  };

  /// The painted extent and top-left corner, in **device** pixels, of [image]
  /// drawn by [child] in a `size` box `inset` logical pixels from the corner.
  ///
  /// The image already exists, so this pump has no zone to bridge — the same
  /// reason the scaling group above is testable when the widget's own raster is
  /// not.
  Future<({int width, int height, int left, int top, int partial})> painted(
    WidgetTester tester, {
    required double dpr,
    required double size,
    required double inset,
    required ui.Image image,
    required Widget Function(ui.Image image) child,
    Widget Function(Widget child) ancestor = _itself,
  }) async {
    tester.view.devicePixelRatio = dpr;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: const ValueKey('boundary'),
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.only(left: inset, top: inset),
              child: ancestor(
                SizedBox(width: size, height: size, child: child(image)),
              ),
            ),
          ),
        ),
      ),
    );

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('boundary')),
    );
    late Uint8List bytes;
    late int stride;
    await tester.runAsync(() async {
      // **`pixelRatio: dpr`, so one pixel of this shot is one device pixel of
      // the real display** — the unit the whole defect lives in. At the default
      // of 1.0 the shot would be in logical pixels and the artefact would be
      // resampled away before it could be counted.
      final shot = await boundary.toImage(pixelRatio: dpr);
      stride = shot.width;
      bytes = (await shot.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      shot.dispose();
    });

    // **Partial coverage is counted against the *peak* alpha, not against
    // 255.** One of the swept ancestors is an `Opacity`, which multiplies every
    // pixel down uniformly — measuring against 255 would call the entire image
    // partial and say nothing about the edge. The peak is what a fully covered
    // pixel of this shot looks like; anything strictly between transparent and
    // that is a pixel the destination rect only half landed on.
    var peak = 0;
    for (var i = 3; i < bytes.length; i += 4) {
      if (bytes[i] > peak) peak = bytes[i];
    }

    var minX = stride, maxX = -1, minY = 1 << 30, maxY = -1, partial = 0;
    for (var y = 0; (y + 1) * stride * 4 <= bytes.length; y++) {
      for (var x = 0; x < stride; x++) {
        final alpha = bytes[(y * stride + x) * 4 + 3];
        if (alpha == 0) continue;
        if (alpha != peak) partial++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    return (
      width: maxX - minX + 1,
      height: maxY - minY + 1,
      left: minX,
      top: minY,
      partial: partial,
    );
  }

  // Every row the original sweep measured, the clean ones included: a guard
  // that only ever ran on broken input could not show it leaves the working
  // cases alone.
  const cases = <({double dpr, double inset, bool wasBroken})>[
    (dpr: 1.0, inset: 15.0, wasBroken: false),
    (dpr: 1.25, inset: 15.5, wasBroken: true),
    (dpr: 1.25, inset: 16.0, wasBroken: false),
    (dpr: 1.5, inset: 15.0, wasBroken: true),
    (dpr: 1.5, inset: 15.25, wasBroken: true),
    (dpr: 1.5, inset: 15.75, wasBroken: true),
    (dpr: 1.5, inset: 16.0, wasBroken: false),
    (dpr: 1.75, inset: 15.25, wasBroken: true),
    (dpr: 1.75, inset: 15.75, wasBroken: true),
    (dpr: 2.0, inset: 15.25, wasBroken: false),
    (dpr: 2.625, inset: 15.0, wasBroken: true),
    (dpr: 3.0, inset: 15.75, wasBroken: false),
  ];

  for (final entry in ancestors.entries) {
    group('the buffer lands on the device pixel grid whole, ${entry.key}', () {
      for (final row in cases) {
        final suffix = row.wasBroken ? ' — the sampler used to run here' : '';
        testWidgets('ratio ${row.dpr}, inset ${row.inset}$suffix', (
          tester,
        ) async {
          addTearDown(tester.view.reset);
          const size = 45.0;
          final pixels = (size * row.dpr).round();

          late final ui.Image image;
          await tester.runAsync(() async => image = await opaqueSquare(pixels));
          addTearDown(image.dispose);

          final got = await painted(
            tester,
            dpr: row.dpr,
            size: size,
            inset: row.inset,
            image: image,
            ancestor: entry.value,
            child: (image) =>
                PixelSnappedImage(image: image, devicePixelRatio: row.dpr),
          );

          expect(
            (got.width, got.height),
            (pixels, pixels),
            reason:
                'a $pixels-pixel buffer must occupy $pixels device pixels; any '
                'other extent is a column dropped or duplicated',
          );
          expect(
            got.partial,
            0,
            reason:
                'an opaque buffer landing on the grid leaves no partial pixel '
                '— one would be the destination rect antialiasing its own edge',
          );
          // **Where, not only how wide.** A snap that put the square somewhere
          // else entirely would satisfy both assertions above, so the extent
          // alone cannot price the fix's own stated cost — half a device pixel
          // of movement, and no more.
          final wanted = (row.inset * row.dpr).round();
          for (final (axis, at) in [('left', got.left), ('top', got.top)]) {
            expect(
              (at - wanted).abs(),
              lessThanOrEqualTo(1),
              reason:
                  'the $axis edge sits at $at device pixels where layout asked '
                  'for ${row.inset * row.dpr}; the snap may move it by half a '
                  'pixel, not by more',
            );
          }
        });
      }
    });
  }

  group('the snap is taken against the screen, not the enclosing layer', () {
    // **The one claim in this fix that no screenshot can price.** Skia with
    // `isAntiAlias` off already rounds a destination rectangle whose width is a
    // whole number of device pixels, so snapping against the layer offset
    // instead of the screen produces the same pixels in every arrangement this
    // suite can capture — and produces a sliced avatar inside a `ListView`,
    // where each child is painted at `Offset.zero` on a layer that carries the
    // real, unrounded position.
    //
    // So it is read where it is decided. `debugGlobalDestination` is written
    // under an `assert` and is the render object's own answer to "where did I
    // just put this".
    for (final ratio in const [1.25, 1.5, 1.75, 2.625]) {
      testWidgets('at ratio $ratio, under a layer at a fractional offset', (
        tester,
      ) async {
        addTearDown(tester.view.reset);
        tester.view.devicePixelRatio = ratio;
        const size = 45.0;
        final pixels = (size * ratio).round();

        late final ui.Image image;
        await tester.runAsync(() async {
          final bytes = Uint8List(pixels * pixels * 4);
          for (var i = 0; i < pixels * pixels; i++) {
            bytes[i * 4 + 3] = 255;
          }
          final decoded = Completer<ui.Image>();
          ui.decodeImageFromPixels(
            bytes,
            pixels,
            pixels,
            ui.PixelFormat.rgba8888,
            decoded.complete,
          );
          image = await decoded.future;
        });
        addTearDown(image.dispose);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                // An offset whose device position is fractional at every ratio
                // swept here, so the layer below carries a real fraction.
                padding: const EdgeInsets.only(left: 15.3, top: 22.7),
                // The layer. `ListView` gives one of these to every child.
                child: RepaintBoundary(
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: PixelSnappedImage(
                      image: image,
                      devicePixelRatio: ratio,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        final render = tester.renderObject<RenderPixelSnappedImage>(
          find.byType(PixelSnappedImage),
        );
        final destination = render.debugGlobalDestination;
        expect(
          destination,
          isNotNull,
          reason: 'paint records where it drew; a null means it never ran',
        );

        for (final (name, value) in [
          ('left', destination!.left),
          ('top', destination.top),
          ('width', destination.width),
          ('height', destination.height),
        ]) {
          final device = value * ratio;
          expect(
            (device - device.roundToDouble()).abs(),
            lessThan(1e-9),
            reason:
                'the drawing\'s global $name is $device device pixels. The box '
                'sits at (15.3, 22.7) logical, which is fractional here, and '
                'the repaint boundary hands paint an offset of zero — so this '
                'is only whole if the snap read the screen position',
          );
        }

        expect(
          destination.width * ratio,
          closeTo(pixels.toDouble(), 1e-9),
          reason: 'and it is the buffer\'s own $pixels pixels, one for one',
        );
      });
    }
  });

  group('the destination rectangle is on the grid by construction', () {
    // **Asserted here rather than through a screenshot, and that is a finding
    // rather than a preference.** Skia with `isAntiAlias` off already rounds a
    // destination whose width is a whole number of device pixels, so the sweep
    // above stays green with the snap removed entirely — measured, both by
    // deleting the origin correction and by computing it against the layer
    // offset. That makes a rendered pixel unable to price the snap.
    //
    // The snap is kept anyway, and the reason is `CLAUDE.md` invariant 4: the
    // output must not depend on Skia-versus-Impeller. Leaning on a backend's
    // rounding is that dependence; doing the rounding here is what makes the
    // placement this package's own. A claim no test can kill is not a claim, so
    // it is asserted where it is actually made.
    const ratios = [1.0, 1.25, 1.5, 1.75, 2.0, 2.625, 3.0];
    const origins = [0.0, 0.25, 0.5, 0.75, 15.0, 15.5, 22.4, 101.3];
    const boxes = [1.0, 20.0, 45.0, 72.0, 240.5];

    test('every edge lands on a whole device pixel', () {
      for (final ratio in ratios) {
        for (final origin in origins) {
          for (final box in boxes) {
            // **`global` and `local` differ on purpose.** Under a repaint
            // boundary the canvas is at the layer's origin and `local` is the
            // offset within it, so a version that snapped `local` would pass a
            // sweep where the two agree and fail on a scrolling list. Holding
            // them apart is what makes that mutation visible.
            final rect = snappedAvatarRect(
              global: Offset(origin, origin + 0.3),
              local: Offset(origin - 7, origin + 0.3 - 7),
              box: Size(box, box),
              devicePixelRatio: ratio,
            );

            // **Translated back to global space before it is judged.** The
            // function returns a rectangle in the canvas's own coordinates,
            // and it is the *screen* position that has to land on the grid —
            // the two differ by exactly the layer offset this whole correction
            // exists to see through.
            final global0 = Offset(origin, origin + 0.3);
            final local0 = Offset(origin - 7, origin + 0.3 - 7);
            for (final (name, value) in [
              ('left', global0.dx + (rect.left - local0.dx)),
              ('top', global0.dy + (rect.top - local0.dy)),
              ('width', rect.width),
              ('height', rect.height),
            ]) {
              final device = value * ratio;
              expect(
                (device - device.roundToDouble()).abs(),
                lessThan(1e-9),
                reason:
                    'at ratio $ratio, origin $origin, box $box the $name is '
                    '$device device pixels — the buffer would straddle two',
              );
            }
          }
        }
      }
    });

    test('and never moves further than half a device pixel to get there', () {
      for (final ratio in ratios) {
        for (final origin in origins) {
          const local = 7.0;
          final rect = snappedAvatarRect(
            global: Offset(origin, origin),
            local: const Offset(local, local),
            box: const Size(45, 45),
            devicePixelRatio: ratio,
          );
          expect(
            ((rect.left - local) * ratio).abs(),
            lessThanOrEqualTo(0.5 + 1e-9),
            reason:
                'the fix is priced at half a device pixel of movement; at '
                'ratio $ratio from origin $origin it moved '
                '${(rect.left - local) * ratio}',
          );
        }
      }
    });

    test('a non-finite global position corrects by nothing, not by NaN', () {
      // `localToGlobal` walks the ancestor transforms, and a degenerate one
      // hands back infinity or NaN. Carried into the destination rectangle that
      // is a drawing nobody sees and an exception nobody can place. Flutter's
      // own `RenderEditable._snapToPhysicalPixel` guards the identical
      // expression the identical way; this is that guard, and this is what
      // makes it a claim rather than a comment.
      for (final bad in [double.nan, double.infinity, -double.infinity]) {
        final rect = snappedAvatarRect(
          global: Offset(bad, bad),
          local: const Offset(12, 12),
          box: const Size(45, 45),
          devicePixelRatio: 1.5,
        );
        expect(
          rect.isFinite,
          isTrue,
          reason: 'a global position of $bad produced $rect',
        );
        expect(
          rect.topLeft,
          const Offset(12, 12),
          reason:
              'with nothing to snap against, the drawing stays where layout '
              'put it rather than moving by an unknown amount',
        );
      }
    });

    test('a box the parent squeezed still governs the extent', () {
      // The other half of the same function: the rectangle is the *box*
      // rounded, never the buffer, so a squeezed box keeps squeezing.
      final rect = snappedAvatarRect(
        global: Offset.zero,
        local: Offset.zero,
        box: const Size(20, 20),
        devicePixelRatio: 1,
      );
      expect(rect.size, const Size(20, 20));
    });
  });

  group('a box the parent squeezed keeps squeezing the drawing', () {
    // **The regression this replaced, caught by the completeness pass.** The
    // first version of `PixelSnappedImage` derived the drawn rectangle from the
    // *buffer* rather than from the box, which is right exactly while the two
    // agree. Under a parent that squeezes, a 240-pixel avatar painted at full
    // size across a 20-logical box — a twelvefold overflow, over whatever sat
    // beside it, with nothing to clip it.
    //
    // README promises the other behaviour in as many words: *"Layout that then
    // squeezes the box smaller than the size you asked for is outside the
    // package, and Flutter's sampler runs there like it would for any image."*
    testWidgets('a 240-pixel buffer in a 20-logical box is drawn scaled', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      late final ui.Image image;
      await tester.runAsync(() async => image = await opaqueSquare(240));
      addTearDown(image.dispose);

      final got = await painted(
        tester,
        dpr: 1,
        size: 20,
        inset: 15,
        image: image,
        child: (image) => PixelSnappedImage(image: image, devicePixelRatio: 1),
      );

      expect(
        (got.width, got.height),
        (20, 20),
        reason:
            'the box is 20 logical pixels at ratio 1, so the drawing is 20 '
            'device pixels however large the buffer is',
      );
    });
  });

  group('the avatar answers a hit test', () {
    // `RenderBox.hitTestSelf` is `false` and `RenderImage`'s is `true`, and the
    // difference is invisible until something defers to the child —
    // `GestureDetector` does that by default whenever it has one. Left at the
    // inherited `false`, every ancestor's hit test walked straight past the
    // avatar and taps stopped arriving.
    testWidgets('a tap on it reaches an enclosing GestureDetector', (
      tester,
    ) async {
      late final ui.Image image;
      await tester.runAsync(() async => image = await opaqueSquare(40));
      addTearDown(image.dispose);

      var taps = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: GestureDetector(
              onTap: () => taps++,
              child: SizedBox(
                width: 40,
                height: 40,
                child: PixelSnappedImage(image: image, devicePixelRatio: 1),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(PixelSnappedImage));
      await tester.pump();
      expect(taps, 1, reason: 'a `RawImage` in the same box delivers this tap');
    });
  });

  group('the reported case, on the picture that reported it', () {
    // #110's own verification idea, run on the configuration it named: `marble`
    // at 45 logical and 125% scaling, offset so the origin is fractional. A
    // disc's outline is **vertical** at its leftmost and rightmost points, so a
    // column lost or doubled there is a straight chord rather than a nibbled
    // corner — which is why this package cannot hide what an icon with interior
    // padding would.
    testWidgets('marble at 45 logical, ratio 1.25, fractional origin', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      late final ui.Image image;
      await tester.runAsync(() async {
        image = await rasterAvatarImage(
          name: 'Clara Barton',
          colors: const ['#4A1F9F', '#7B4CF5', '#EFEAFE', '#C3B4F8'],
          pixels: 56,
          version: BoringAvatarsVersion.v1_7_0,
          variant: BoringAvatarsVariant.marble,
          square: false,
        );
      });
      addTearDown(image.dispose);

      final got = await painted(
        tester,
        dpr: 1.25,
        size: 45,
        inset: 15.5,
        image: image,
        child: (image) =>
            PixelSnappedImage(image: image, devicePixelRatio: 1.25),
      );

      expect(
        (got.width, got.height),
        (56, 56),
        reason:
            'the palette and name #110 reported, at the ratio it reported, '
            'drawn across 56 device pixels and not 57',
      );
    });
  });
}

Widget _itself(Widget child) => child;
Widget _underRepaintBoundary(Widget child) => RepaintBoundary(child: child);
Widget _underOpacity(Widget child) => Opacity(opacity: 0.5, child: child);

/// `FilterQuality.none` is a promise about the *destination*, and #117 is what
/// happens when the promise is made where it does not hold.
///
/// **The invariant behind the unfiltered hand-off.** This package rasterises at
/// `(size × dpr).round()` physical pixels and draws with no filter at all,
/// because any sampling would be the backend's and `CLAUDE.md`'s invariant 4
/// refuses it. That is only *true* while the buffer and the rectangle it lands
/// in are the same number of device pixels, in the same axes — one buffer pixel
/// per device pixel. [snappedAvatarRect] buys the origin and the extent
/// (ADR-0002 R1/R2); it cannot buy the two conditions this predicate adds.
///
/// **And when the invariant fails, `none` is the worst available choice, not the
/// safest.** Nearest neighbour cannot spend a fraction of a pixel, so it drops
/// or duplicates whole columns — the fold #117 reported across `marble`'s
/// gradient. A filtered draw at the same misalignment is half a pixel of
/// softness instead.
///
/// **This does not trade invariant 4 away, and that is the whole argument for
/// the ruling.** In the misaligned case the output is *already* the backend's:
/// which source column nearest neighbour keeps is the sampler's rounding, so
/// Skia and Impeller need not agree and the bytes were never ours to promise.
/// The fallback narrows the claim to the cases where it is true and stops the
/// silent lie in the ones where it never was. Where the invariant does hold —
/// the overwhelming majority — the bytes are **identical to before**.
void _resampleFallback() {
  const palette = ['#C9B8FD', '#3B7BF0', '#2E33A0'];

  Matrix4 translated(double dx, double dy) =>
      Matrix4.translationValues(dx, dy, 0);

  group('the unfiltered hand-off is claimed only where it is true', () {
    // The predicate is pure, so these are the enumeration and not a sample of
    // it: identity, translation (whole and fractional), the two linear parts
    // that defeat a snap, both directions of a buffer/box disagreement, and a
    // transform that is not a number.

    test('an identity transform with a matching buffer lands one-for-one', () {
      expect(
        avatarLandsOnePixelPerPixel(
          toScreen: Matrix4.identity(),
          box: const Size(44, 44),
          buffer: const Size(66, 66),
          devicePixelRatio: 1.5,
        ),
        isTrue,
      );
    });

    test('a whole-pixel translation still lands one-for-one', () {
      expect(
        avatarLandsOnePixelPerPixel(
          toScreen: translated(12, 34),
          box: const Size(44, 44),
          buffer: const Size(66, 66),
          devicePixelRatio: 1.5,
        ),
        isTrue,
      );
    });

    // **The one that is easy to get wrong.** A fractional *translation* is not a
    // misalignment: `snappedAvatarRect` moves the drawing by the same fraction
    // in the opposite direction, so the pixels still land whole. Reporting this
    // as filtered would put a filter under every ordinary padding.
    test(
      'a fractional translation lands one-for-one, because the snap cancels it',
      () {
        expect(
          avatarLandsOnePixelPerPixel(
            toScreen: translated(35, 20),
            box: const Size(44, 44),
            buffer: const Size(66, 66),
            devicePixelRatio: 1.5,
          ),
          isTrue,
          reason:
              '35 x 1.5 is 52.5 device pixels and the snap already corrects '
              'the half; the drawing lands on 53',
        );
      },
    );

    test('a scale does not', () {
      expect(
        avatarLandsOnePixelPerPixel(
          toScreen: Matrix4.diagonal3Values(1.1, 1.1, 1),
          box: const Size(44, 44),
          buffer: const Size(66, 66),
          devicePixelRatio: 1.5,
        ),
        isFalse,
      );
    });

    // A mirror is a scale of -1, and it is worth its own line because it is the
    // one linear part that leaves the *extent* right — a predicate written
    // against sizes rather than against the matrix would pass it.
    test('nor does a mirror', () {
      expect(
        avatarLandsOnePixelPerPixel(
          toScreen: Matrix4.diagonal3Values(-1, 1, 1),
          box: const Size(44, 44),
          buffer: const Size(66, 66),
          devicePixelRatio: 1.5,
        ),
        isFalse,
      );
    });

    test('nor does a rotation', () {
      expect(
        avatarLandsOnePixelPerPixel(
          toScreen: Matrix4.rotationZ(0.2),
          box: const Size(44, 44),
          buffer: const Size(66, 66),
          devicePixelRatio: 1.5,
        ),
        isFalse,
      );
    });

    // ADR-0002 R2: the drawn extent comes from the box, so a parent that
    // squeezes keeps squeezing the drawing. That is deliberate — and it is also
    // a resample, which is exactly what this predicate is for.
    test('a box the parent squeezed does not', () {
      expect(
        avatarLandsOnePixelPerPixel(
          toScreen: Matrix4.identity(),
          box: const Size(20, 20),
          buffer: const Size(240, 240),
          devicePixelRatio: 1,
        ),
        isFalse,
      );
    });

    // The other direction, and it is not symmetric with the one above: this is
    // the transitional state `_sync` deliberately allows, where a ratio change
    // leaves an older buffer on screen until the new raster lands.
    test('a buffer from a different ratio does not', () {
      expect(
        avatarLandsOnePixelPerPixel(
          toScreen: Matrix4.identity(),
          box: const Size(44, 44),
          buffer: const Size(64, 64),
          devicePixelRatio: 1.5,
        ),
        isFalse,
        reason:
            '44 x 1.5 rounds to a 66-pixel destination and the buffer is 64',
      );
    });

    // `localToGlobal` walks the ancestor transforms and a degenerate one — a
    // `Transform.scale(scale: 0)`, a collapsed matrix — hands back infinities.
    // `snappedAvatarRect` already guards its own arithmetic against that; this
    // is the same guard on the same input, and it fails *safe*: a drawing whose
    // position cannot be computed is not one to promise anything about.
    test('a non-finite transform does not', () {
      expect(
        avatarLandsOnePixelPerPixel(
          toScreen: Matrix4.diagonal3Values(double.nan, 1, 1),
          box: const Size(44, 44),
          buffer: const Size(66, 66),
          devicePixelRatio: 1.5,
        ),
        isFalse,
      );
    });
  });

  group('and the predicate reaches the pixels', () {
    // **The rendered half.** The tests above pin the decision; this one pins
    // that `paint` asks. Under a scaled ancestor, nearest neighbour repeats
    // whole columns of the buffer — byte-identical neighbours, which a gradient
    // never produces on its own — so counting them is a test of the filter and
    // of nothing else. Measured with the fallback removed: **7** repeated
    // columns at this scale, and 0 with it.
    testWidgets('a scaled ancestor no longer repeats whole columns', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1;

      late final ui.Image image;
      await tester.runAsync(() async {
        image = await rasterAvatarImage(
          name: 'Clara Barton',
          colors: palette,
          pixels: 66,
          version: BoringAvatarsVersion.v1_7_0,
          variant: BoringAvatarsVariant.marble,
          // The extent is read off alpha, and a disc's topmost row can quantise
          // to no coverage at all — `pixel_snap_test.dart` squares its avatar
          // for the same reason.
          square: true,
        );
      });
      addTearDown(image.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: const ValueKey('shot'),
            child: Align(
              alignment: Alignment.topLeft,
              child: Transform.scale(
                scale: 1.1,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 66,
                  height: 66,
                  child: PixelSnappedImage(image: image, devicePixelRatio: 1),
                ),
              ),
            ),
          ),
        ),
      );

      late Uint8List bytes;
      late int stride;
      await tester.runAsync(() async {
        final shot = await tester
            .renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('shot')),
            )
            .toImage();
        stride = shot.width;
        bytes = (await shot.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        shot.dispose();
      });

      final rows = bytes.length ~/ (stride * 4);
      var repeated = 0;
      for (var x = 1; x < stride; x++) {
        var same = true;
        var opaque = false;
        for (var y = 0; y < rows && same; y++) {
          final here = (y * stride + x) * 4;
          final left = (y * stride + x - 1) * 4;
          if (bytes[here + 3] != 0) opaque = true;
          for (var k = 0; k < 4; k++) {
            if (bytes[here + k] != bytes[left + k]) {
              same = false;
              break;
            }
          }
        }
        if (same && opaque) repeated++;
      }

      expect(
        repeated,
        0,
        reason:
            'a filtered draw interpolates between source columns, so no two '
            'columns of a gradient come out byte-identical; a repeat is '
            'nearest neighbour landing twice on the same pixel (#117)',
      );
    });
  });
}
