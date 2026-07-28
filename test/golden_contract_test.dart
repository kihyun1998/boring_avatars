import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';

/// The rasterizer does not exist yet, so there is no avatar to compare. What
/// *can* be proved now is that the comparison itself behaves — that the two
/// bars differ in the way the bindings say they do, and that neither of them
/// passes on a difference it is supposed to catch.
///
/// A harness nobody has watched fail is not a harness. These use tiny synthetic
/// images for exactly that reason: the subject under test here is the
/// comparison, not the drawing.
void main() {
  /// A 4x4 image: a solid 2x2 block of [inner] at the top-left of [outer].
  RgbaImage block(List<int> outer, List<int> inner) {
    final bytes = <int>[];
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        bytes.addAll(x < 2 && y < 2 ? inner : outer);
      }
    }
    return RgbaImage(4, 4, bytes);
  }

  const white = [255, 255, 255, 255];
  const black = [0, 0, 0, 255];

  group('the regression bar allows nothing', () {
    test('identical images pass', () {
      expectGoldenIdentical(block(white, black), block(white, black));
    });

    test('a single channel off by one fails', () {
      final actual = block(white, black);
      actual.bytes[0] = 254;
      expect(
        () => expectGoldenIdentical(actual, block(white, black)),
        throwsA(isA<TestFailure>()),
      );
    });

    test('a size difference fails before any pixel is read', () {
      expect(
        () => expectGoldenIdentical(
          RgbaImage(2, 2, List.filled(16, 0)),
          RgbaImage(4, 4, List.filled(64, 0)),
        ),
        throwsA(isA<TestFailure>()),
      );
    });
  });

  group('the calibration bar allows one level, and only on an edge', () {
    test('an edge pixel off by one passes', () {
      // (1, 1) borders the block, so it is an edge by the neighbourhood test.
      final actual = block(white, black);
      final i = (1 * 4 + 1) * 4;
      actual.bytes[i] = 1;
      expectMatchesChromeRender(actual, block(white, black));
    });

    test('an edge pixel off by two fails', () {
      final actual = block(white, black);
      final i = (1 * 4 + 1) * 4;
      actual.bytes[i] = 2;
      expect(
        () => expectMatchesChromeRender(actual, block(white, black)),
        throwsA(isA<TestFailure>()),
      );
    });

    test(
      'an interior pixel off by one fails — the tolerance is edges only',
      () {
        // (3, 3) is surrounded by identical pixels, so it is interior.
        final actual = block(white, black);
        final i = (3 * 4 + 3) * 4;
        actual.bytes[i] = 254;
        expect(
          () => expectMatchesChromeRender(actual, block(white, black)),
          throwsA(isA<TestFailure>()),
        );
      },
    );

    test('the two bars really are different — the same input splits them', () {
      final actual = block(white, black);
      final i = (1 * 4 + 1) * 4;
      actual.bytes[i] = 1;
      // Calibration accepts it; regression does not. If these ever agreed, one
      // of the two gates would be redundant.
      expectMatchesChromeRender(actual, block(white, black));
      expect(
        () => expectGoldenIdentical(actual, block(white, black)),
        throwsA(isA<TestFailure>()),
      );
    });
  });
}
