// The #110 placement check, on a **real engine** rather than the test binding.
//
// **Why this exists beside `test/widget_test.dart`.** Every measurement behind
// #110 went through `flutter test`'s Skia, and the fix's whole justification is
// that the placement must not depend on which backend draws it (`CLAUDE.md`,
// invariant 4). A claim about backend independence checked on one backend is an
// argument, not a measurement. This runs the same assertion on whatever engine
// the device actually has — Impeller or Angle on Windows, CanvasKit in a real
// browser.
//
// **The size is computed from the ratio rather than fixed, and that is the
// trick that makes this runnable anywhere.** The defect needs
// `size × devicePixelRatio` to be fractional — *not* a fractional ratio. A
// machine at 100% scaling would make every integer `size` land whole and the
// test would pass without ever entering the condition (`lessons.md`: a harness
// that never ran in the condition cannot have cleared it). So the size is
// derived to put the box's device width exactly half a pixel past an integer,
// whatever the ratio is, and the same for the origin.
import 'dart:ui' as ui;

import 'package:boring_avatars/boring_avatars.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the avatar occupies whole device pixels on this engine', (
    tester,
  ) async {
    final ratio = tester.view.devicePixelRatio;

    // `x.5` device pixels for both the extent and the origin: the case where
    // the two edges of a fractional rectangle round independently.
    const wantedDeviceSide = 60.5;
    const wantedDeviceInset = 20.5;
    final size = wantedDeviceSide / ratio;
    final inset = wantedDeviceInset / ratio;

    // What the widget bakes, and therefore what has to land on screen.
    final pixels = (size * ratio).round();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        // **The capture boundary is outside the padding, and that is not
        // cosmetic.** `toImage` renders `Offset.zero & size` of the boundary it
        // is called on, so a boundary wrapped tightly around the avatar *is* a
        // clip at the box — and the drawing is deliberately up to one device
        // pixel wider than the box. Measured that way it reported 61x60 at
        // (0, 1) and the harness, not the engine, had eaten the row.
        home: RepaintBoundary(
          key: const ValueKey('boundary'),
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.only(left: inset, top: inset),
              // `ListView` gives every child one of these, and it is what made
              // the first version of the fix a no-op in a list. Here it is the
              // condition under test, not the capture.
              child: RepaintBoundary(
                child: BoringAvatar(
                  name: 'Clara Barton',
                  colors: const ['#4A1F9F', '#7B4CF5', '#EFEAFE', '#C3B4F8'],
                  size: size,
                  version: BoringAvatarsVersion.v1_7_0,
                  variant: BoringAvatarsVariant.marble,
                  // **`square`, and it is the measurement talking, not taste.**
                  // The extent is read off the alpha channel, so it is exact only
                  // when the drawing is opaque to all four edges. A disc's
                  // topmost row can round to zero coverage — the scanline
                  // integrator quantises the vertical direction — and the
                  // measurement would then report a lost row that nothing lost.
                  // Measured: the disc reads 61x60 here where the square reads
                  // 61x61, on the same engine and the same buffer.
                  square: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('boundary')),
    );

    // The raster is asynchronous and this binding is real, so pump until the
    // picture lands rather than assuming a frame count.
    ({int width, int height, int left, int top})? painted;
    for (var attempt = 0; attempt < 200 && painted == null; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      final shot = await boundary.toImage(pixelRatio: ratio);
      final data = await shot.toByteData(format: ui.ImageByteFormat.rawRgba);
      final bytes = data!.buffer.asUint8List();
      final stride = shot.width;
      shot.dispose();

      var minX = stride, maxX = -1, minY = 1 << 30, maxY = -1;
      for (var y = 0; (y + 1) * stride * 4 <= bytes.length; y++) {
        for (var x = 0; x < stride; x++) {
          if (bytes[(y * stride + x) * 4 + 3] == 0) continue;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
      if (maxX >= 0) {
        painted = (
          width: maxX - minX + 1,
          height: maxY - minY + 1,
          left: minX,
          top: minY,
        );
      }
    }

    expect(
      painted,
      isNotNull,
      reason: 'the avatar never arrived; nothing was drawn to measure',
    );

    debugPrint(
      'PIXELSNAP ratio=$ratio size=$size inset=$inset buffer=$pixels '
      'painted=${painted!.width}x${painted.height} '
      'at (${painted.left}, ${painted.top})',
    );

    expect(
      (painted.width, painted.height),
      (pixels, pixels),
      reason:
          'a $pixels-pixel buffer must occupy $pixels device pixels on this '
          'engine too; any other extent is a column dropped or duplicated',
    );

    final wantedOrigin = (inset * ratio).round();
    for (final (axis, at) in [('left', painted.left), ('top', painted.top)]) {
      expect(
        (at - wantedOrigin).abs(),
        lessThanOrEqualTo(1),
        reason:
            'the $axis edge is at $at where layout asked for ${inset * ratio}',
      );
    }
  });
}
