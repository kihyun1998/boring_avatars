// Writes the committed golden images. The test suite only ever READS them —
// a fixture that can rewrite the expectation it just failed against is not a
// gate. Run this deliberately when the rasterizer changes, and review the diff.
//
//   dart run tool/golden/generate.dart
import 'dart:io';

import 'package:boring_avatars/src/raster/scene_raster.dart';
import 'package:boring_avatars/src/scene/scene.dart';
import 'package:boring_avatars/src/variants/pixel.dart';
import 'package:boring_avatars/src/variants/ring.dart';

const _default = ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'];

/// Each case names the scene it renders and the square it renders it into.
///
/// The size is per variant, not global — a scene is rasterised at its own
/// viewBox and `ring`'s is 90 where the others are 80.
final cases = <String, (SvgNode, int)>{
  'pixel-clara-default': (
    buildPixelScene(name: 'Clara Barton', colors: _default, size: 80),
    80,
  ),
  'pixel-alice-pair': (
    buildPixelScene(name: 'Alice', colors: ['#000000', '#FFFFFF'], size: 80),
    80,
  ),
  'pixel-empty-name': (
    buildPixelScene(name: '', colors: ['#FF0000'], size: 80),
    80,
  ),
  'ring-clara-default': (
    buildRingScene(name: 'Clara Barton', colors: _default, size: 90),
    90,
  ),
  'ring-alice-pair': (
    buildRingScene(name: 'Alice', colors: ['#000000', '#FFFFFF'], size: 90),
    90,
  ),
  'ring-clara-square': (
    buildRingScene(
      name: 'Clara Barton',
      colors: _default,
      size: 90,
      square: true,
    ),
    90,
  ),
};

void main() {
  for (final entry in cases.entries) {
    final (scene, size) = entry.value;
    final image = rasterizeScene(scene, width: size, height: size);
    final path = 'test/goldens/${entry.key}.rgba';
    File(path).writeAsBytesSync(image.bytes);
    stdout.writeln('wrote $path (${image.bytes.length} bytes)');
  }
}
