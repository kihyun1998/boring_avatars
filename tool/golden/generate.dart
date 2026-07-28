// Writes the committed golden images. The test suite only ever READS them —
// a fixture that can rewrite the expectation it just failed against is not a
// gate. Run this deliberately when the rasterizer changes, and review the diff.
//
//   dart run tool/golden/generate.dart
import 'dart:io';

import 'package:boring_avatars/src/raster/scene_raster.dart';
import 'package:boring_avatars/src/variants/pixel.dart';

const cases = <String, (String, List<String>)>{
  'pixel-clara-default': (
    'Clara Barton',
    ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'],
  ),
  'pixel-alice-pair': ('Alice', ['#000000', '#FFFFFF']),
  'pixel-empty-name': ('', ['#FF0000']),
};

void main() {
  for (final entry in cases.entries) {
    final (name, colours) = entry.value;
    final image = rasterizeScene(
      buildPixelScene(name: name, colors: colours, size: 80),
      width: 80,
      height: 80,
    );
    final path = 'test/goldens/${entry.key}.rgba';
    File(path).writeAsBytesSync(image.bytes);
    stdout.writeln('wrote $path (${image.bytes.length} bytes)');
  }
}
