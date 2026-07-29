// Writes the committed golden images. The test suite only ever READS them —
// a fixture that can rewrite the expectation it just failed against is not a
// gate. Run this deliberately when the rasterizer changes, and review the diff.
//
//   dart run tool/golden/generate.dart
//
// The roster lives in `test/support/golden_cases.dart`, shared with the tests
// that read the files back and with the one that asserts the directory holds
// exactly these names. It used to live here, and nothing compared the three
// lists: a golden could be generated, committed, and read by nobody.
import 'dart:io';

import 'package:boring_avatars/src/raster/scene_raster.dart';

import '../../test/support/golden_cases.dart';

void main() {
  for (final entry in goldenCases.entries) {
    final (scene, size) = entry.value;
    final image = rasterizeScene(scene, width: size, height: size);
    final path = 'test/goldens/${entry.key}.rgba';
    File(path).writeAsBytesSync(image.bytes);
    stdout.writeln('wrote $path (${image.bytes.length} bytes)');
  }
}
