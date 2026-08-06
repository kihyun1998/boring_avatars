import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';
import 'support/golden_cases.dart';

/// The golden **mechanism** — the two comparison bars, and the roster.
///
/// The bars are proved on tiny synthetic images, because the subject here is
/// the comparison rather than any drawing: a harness nobody has watched fail is
/// not a harness. (This file predates the rasterizer, which is why it says so.)
///
/// The roster group is the one that ties the three lists together. Each
/// variant's raster test reads back its own prefix, `tool/golden/generate.dart`
/// writes a file per entry, and `test/goldens/` holds the results — and until
/// #39 nothing compared them. Measured then: dropping a stray `.rgba` into the
/// directory left all 469 tests green, so a golden could be generated,
/// committed, and read by nobody.
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

  group('the roster is the same in all three places', () {
    /// Every `.rgba` actually sitting in `test/goldens/`.
    Set<String> onDisk() => Directory('test/goldens')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.rgba'))
        .map((n) => n.substring(0, n.length - '.rgba'.length))
        .toSet();

    test('the directory holds exactly the declared cases', () {
      // Both directions matter and they fail for different reasons. A file with
      // no case is a golden nobody reads — it was generated, reviewed as a diff,
      // committed, and proves nothing. A case with no file is a test that cannot
      // run, which the per-variant groups already catch by throwing on the
      // missing read; this says so in one place and by name.
      expect(onDisk(), goldenCases.keys.toSet());
    });

    test('every case is claimed by exactly one variant prefix', () {
      // `goldenCasesFor` filters by `<variant>-`, so a case whose name does not
      // begin with a known prefix would be generated and compared by nobody
      // while still passing the directory check above.
      const variants = ['pixel', 'ring', 'sunset', 'bauhaus', 'beam'];
      final claimed = <String>{
        for (final v in variants) ...goldenCasesFor(v).keys,
      };
      expect(claimed, goldenCases.keys.toSet());
    });

    test('the roster is not empty, which would make both checks vacuous', () {
      expect(goldenCases, isNotEmpty);
      expect(onDisk(), isNotEmpty);
    });
  });
}
