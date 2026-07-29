// Writes the committed golden images. The test suite only ever READS them —
// a fixture that can rewrite the expectation it just failed against is not a
// gate. Run this deliberately when the rasterizer changes, and review the diff.
//
//   dart run tool/golden/generate.dart
import 'dart:io';

import 'package:boring_avatars/src/raster/scene_raster.dart';
import 'package:boring_avatars/src/scene/scene.dart';
import 'package:boring_avatars/src/variants/bauhaus.dart';
import 'package:boring_avatars/src/variants/pixel.dart';
import 'package:boring_avatars/src/variants/ring.dart';
import 'package:boring_avatars/src/variants/sunset.dart';

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
  'sunset-clara-default': (
    buildSunsetScene(name: 'Clara Barton', colors: _default, size: 80),
    80,
  ),
  'sunset-empty-palette': (
    buildSunsetScene(name: 'Clara Barton', colors: const [], size: 80),
    80,
  ),
  'sunset-hangul': (
    buildSunsetScene(name: '박기현', colors: _default, size: 80),
    80,
  ),
  'sunset-clara-square': (
    buildSunsetScene(
      name: 'Clara Barton',
      colors: _default,
      size: 80,
      square: true,
    ),
    80,
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
  // `bauhaus`: the two names separate `isSquare`'s branches — `Clara Barton`
  // is true and rotates 191°, `Alice` is false and rotates 88° — and the empty
  // name hashes to 0, so every transform is the identity and every edge lands
  // on a pixel boundary. There is deliberately **no empty-palette golden**: it
  // would be a fully transparent image, and freezing a blank as correct is the
  // failure #40 found in `sunset`. `bauhaus_raster_test.dart` asserts the blank
  // as behaviour instead.
  'bauhaus-clara-default': (
    buildBauhausScene(name: 'Clara Barton', colors: _default, size: 80),
    80,
  ),
  'bauhaus-alice-pair': (
    buildBauhausScene(name: 'Alice', colors: ['#000000', '#FFFFFF'], size: 80),
    80,
  ),
  'bauhaus-empty-name': (
    buildBauhausScene(name: '', colors: _default, size: 80),
    80,
  ),
  'bauhaus-clara-square': (
    buildBauhausScene(
      name: 'Clara Barton',
      colors: _default,
      size: 80,
      square: true,
    ),
    80,
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
