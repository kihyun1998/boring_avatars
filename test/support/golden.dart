/// The layer-3 comparison contract.
///
/// Two different bars, and the split is deliberate — see
/// `docs/agents/theflow.md`, Step 4.
///
/// * [expectGoldenIdentical] is the **regression** gate. It compares this
///   package's rasterizer against PNGs committed to this repo, and it allows
///   **no tolerance at all**. Both sides are our own deterministic output, so
///   any difference is a change we made.
/// * [expectMatchesChromeRender] is the **parity calibration**. It compares
///   against a real browser, where antialiasing is an approximation neither
///   side specifies, so edge pixels may differ by one level out of 255. It is
///   run deliberately, not per commit: a zero-tolerance gate against Chrome is
///   a gate that fails when *Chrome* changes and our code has not.
///
/// **Nothing calls these yet.** The rasterizer arrives with the tracer-bullet
/// slice, and until then there is no image to compare — a fact recorded here
/// rather than hidden behind a harness that silently passes on an empty set.
library;

import 'package:flutter_test/flutter_test.dart';

/// A decoded image as straight RGBA bytes, four per pixel, row-major.
class RgbaImage {
  const RgbaImage(this.width, this.height, this.bytes)
    : assert(bytes.length == width * height * 4, 'RGBA is four bytes a pixel');

  final int width;
  final int height;
  final List<int> bytes;

  /// The four channels at (x, y).
  List<int> pixel(int x, int y) {
    final i = (y * width + x) * 4;
    return bytes.sublist(i, i + 4);
  }
}

/// Regression bar: byte-identical, no exceptions.
void expectGoldenIdentical(
  RgbaImage actual,
  RgbaImage golden, {
  String? reason,
}) {
  expect(actual.width, golden.width, reason: reason);
  expect(actual.height, golden.height, reason: reason);

  for (var i = 0; i < golden.bytes.length; i++) {
    if (actual.bytes[i] != golden.bytes[i]) {
      final pixel = i ~/ 4;
      fail(
        'golden mismatch at pixel (${pixel % golden.width}, '
        '${pixel ~/ golden.width}) channel ${i % 4}: '
        'expected ${golden.bytes[i]}, got ${actual.bytes[i]}'
        '${reason == null ? '' : ' — $reason'}',
      );
    }
  }
}

/// Calibration bar: interior exact, antialiased edges within one level.
///
/// An edge pixel is one whose neighbourhood is not uniform in [reference] —
/// which is where coverage estimation happens and where two rasterizers are
/// allowed to disagree. Everywhere else the bar is the same as the regression
/// gate: exact.
void expectMatchesChromeRender(
  RgbaImage actual,
  RgbaImage reference, {
  int edgeTolerance = 1,
  String? reason,
}) {
  expect(actual.width, reference.width, reason: reason);
  expect(actual.height, reference.height, reason: reason);

  var interiorMismatches = 0;
  var edgeMismatches = 0;

  for (var y = 0; y < reference.height; y++) {
    for (var x = 0; x < reference.width; x++) {
      final a = actual.pixel(x, y);
      final b = reference.pixel(x, y);
      if (_sameBytes(a, b)) continue;

      if (_isEdge(reference, x, y)) {
        edgeMismatches++;
        for (var c = 0; c < 4; c++) {
          if ((a[c] - b[c]).abs() > edgeTolerance) {
            fail(
              'edge pixel ($x, $y) channel $c differs by '
              '${(a[c] - b[c]).abs()}, over the tolerance of $edgeTolerance'
              '${reason == null ? '' : ' — $reason'}',
            );
          }
        }
      } else {
        interiorMismatches++;
      }
    }
  }

  expect(
    interiorMismatches,
    0,
    reason:
        'interior and background pixels must match Chrome exactly; '
        '$edgeMismatches edge pixels were within tolerance'
        '${reason == null ? '' : ' — $reason'}',
  );
}

bool _sameBytes(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Whether (x, y) sits on a coverage boundary in [image].
bool _isEdge(RgbaImage image, int x, int y) {
  final centre = image.pixel(x, y);
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      final nx = x + dx;
      final ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= image.width || ny >= image.height) continue;
      if (!_sameBytes(centre, image.pixel(nx, ny))) return true;
    }
  }
  return false;
}
