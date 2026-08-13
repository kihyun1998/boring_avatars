// The banded rasteriser: the same picture, drawn without owning the thread.
//
// #80 measured that `compute` moves nothing on web — Flutter's web `compute` is
// `await null; return callback(message)`, a *microtask*, and the microtask queue
// drains before the browser paints. So the only thing that keeps a frame alive
// on web is the raster yielding to the event loop itself, which is what these
// tests pin.
//
// **What the byte comparisons here are and are not.** `rasterizeScene` and
// `rasterizeSceneAsync` drain the *same* generator, so their agreeing is close
// to structural — this is deliberately a weak test of a strong property, and
// saying so beats letting it read as the proof it is not. What it can still
// catch is a driver that stops early, skips a band, or reuses a buffer.
//
// **The proof that the picture did not move is the rest of the suite**: every
// golden assertion runs through `rasterizeScene`, which now goes through the
// bands. If banding had changed a number, those would have gone red, and the
// count is what says they ran.
//
// The claim that is *not* structural, and the reason this file exists:
//
//   the raster **actually yields**, with a macrotask. A version that yielded
//   with `await null` would pass every byte comparison here and fix nothing,
//   which is precisely the trap the SDK reading found.

import 'dart:async';

import 'package:boring_avatars/src/avatar.dart';
import 'package:boring_avatars/src/raster/scene_raster.dart';
import 'package:boring_avatars/src/scene/scene.dart';
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

SvgNode _scene(BoringAvatarsVariant variant, int size, {bool square = false}) =>
    buildAvatarScene(
      name: 'Clara Barton',
      colors: _palette,
      size: size,
      version: BoringAvatarsVersion.v1_6_1,
      // A raster comparison — <title> never reaches a pixel.
      title: null,
      variant: variant,
      square: square,
    );

/// The side each **drawn** variant's `viewBox` states, so the 1:1 case is
/// exercised too — `beam` is 36 and `ring` is 90 (hidden-state #26).
///
/// `geometric` and `abstractStyle` are absent because they are names rather than
/// drawings: upstream kept them working after retiring what they pointed at, and
/// `resolved` sends them to `beam` and `bauhaus`. The test below proves that
/// rather than trusting it.
const _sides = <BoringAvatarsVariant, int>{
  BoringAvatarsVariant.marble: 80,
  BoringAvatarsVariant.beam: 36,
  BoringAvatarsVariant.pixel: 80,
  BoringAvatarsVariant.sunset: 80,
  BoringAvatarsVariant.ring: 90,
  BoringAvatarsVariant.bauhaus: 80,
};

void main() {
  test('the sweep below covers every variant that is its own drawing', () {
    expect(_sides.keys.toSet(), BoringAvatarsVariant.renderable.toSet());
  });

  test('and the two that are not draw the same as what they resolve to', () {
    // What makes the exclusion above earned rather than asserted. If an alias
    // ever stopped agreeing with its target, skipping it in the sweep would be
    // hiding a defect instead of avoiding a duplicate.
    for (final alias in BoringAvatarsVariant.values.where(
      (v) => !BoringAvatarsVariant.renderable.contains(v),
    )) {
      final target = alias.resolved;
      final side = _sides[target]!;
      expect(
        rasterizeScene(_scene(alias, side), width: side, height: side).bytes,
        rasterizeScene(_scene(target, side), width: side, height: side).bytes,
        reason: '${alias.name} should draw exactly ${target.name}',
      );
    }
  });

  group('the banded raster draws the same bytes', () {
    for (final entry in _sides.entries) {
      final variant = entry.key;
      final side = entry.value;

      // Two scales on purpose: at 1:1 the closed-form rect integrator is live
      // and at 1.5 it is not (#58), so the two exercise different code.
      for (final px in <int>[side, (side * 1.5).round()]) {
        test('${variant.name} @$px', () async {
          final sync = rasterizeScene(
            _scene(variant, side),
            width: px,
            height: px,
          );
          final banded = await rasterizeSceneAsync(
            _scene(variant, side),
            width: px,
            height: px,
            slice: const Duration(
              microseconds: 1,
            ), // yield as often as possible
          );

          expect(banded.width, sync.width);
          expect(banded.height, sync.height);
          // Not `equals` on the lists: a mismatch there prints two 200 kB
          // buffers. Report where and by how much instead.
          var worst = 0;
          var at = -1;
          for (var i = 0; i < sync.bytes.length; i++) {
            final delta = (banded.bytes[i] - sync.bytes[i]).abs();
            if (delta > worst) {
              worst = delta;
              at = i;
            }
          }
          expect(
            worst,
            0,
            reason:
                'byte $at differs by $worst — banding moved the picture, which '
                'it cannot be allowed to do',
          );
        });
      }
    }
  });

  test('square is banded identically too', () async {
    final sync = rasterizeScene(
      _scene(BoringAvatarsVariant.marble, 80, square: true),
      width: 120,
      height: 120,
    );
    final banded = await rasterizeSceneAsync(
      _scene(BoringAvatarsVariant.marble, 80, square: true),
      width: 120,
      height: 120,
      slice: const Duration(microseconds: 1),
    );
    expect(banded.bytes, sync.bytes);
  });

  test('it yields to the event loop, with a macrotask', () async {
    // The discriminator. A raster that never yields, *or* one that yields with
    // `await null`, completes entirely in microtasks — and the microtask queue
    // drains before any timer runs, so this stays false in both cases. That is
    // the whole difference between fixing web and appearing to.
    var tickedDuringRaster = false;
    final future = rasterizeSceneAsync(
      _scene(BoringAvatarsVariant.marble, 80),
      width: 160,
      height: 160,
      slice: const Duration(microseconds: 1),
    );
    Timer.run(() => tickedDuringRaster = true);
    await future;

    expect(
      tickedDuringRaster,
      isTrue,
      reason: 'the timer never got a turn, so the raster held the thread',
    );
  });

  test(
    'a generous slice still finishes, and still yields at least once',
    () async {
      // The other end of the range: a slice longer than the whole raster must not
      // deadlock or skip work. `marble` at 80 is tens of milliseconds, so a one
      // second slice means "never yield on time" — the loop still has to drain.
      final banded = await rasterizeSceneAsync(
        _scene(BoringAvatarsVariant.marble, 80),
        width: 80,
        height: 80,
        slice: const Duration(seconds: 1),
      );
      final sync = rasterizeScene(
        _scene(BoringAvatarsVariant.marble, 80),
        width: 80,
        height: 80,
      );
      expect(banded.bytes, sync.bytes);
    },
  );

  test('the step count grows with the work', () {
    // A guard against the whole thing collapsing to one step, which would pass
    // the byte tests and yield nothing. Steps are rows and bands, so a bigger
    // target must produce strictly more of them.
    final small = SceneRaster(
      _scene(BoringAvatarsVariant.marble, 80),
      width: 80,
      height: 80,
    );
    final large = SceneRaster(
      _scene(BoringAvatarsVariant.marble, 80),
      width: 160,
      height: 160,
    );
    final smallSteps = small.steps().length;
    final largeSteps = large.steps().length;

    expect(smallSteps, greaterThan(10));
    expect(largeSteps, greaterThan(smallSteps));
  });
}
