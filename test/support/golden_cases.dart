/// The golden roster — **one list, three consumers**.
///
/// `tool/golden/generate.dart` writes a file per entry, each variant's raster
/// test reads back the entries with its prefix, and `golden_contract_test.dart`
/// asserts that `test/goldens/` holds exactly these names and no others.
///
/// It lives here because the three used to be three separate lists and nothing
/// compared them. They happened to agree; nothing made them. Measured before
/// this file existed: dropping a stray `.rgba` into `test/goldens/` left all
/// 469 tests green, so a golden could be generated, committed and never read.
/// The other direction — a test naming a file that is absent — already failed.
///
/// **What is shared is the case list, not the bytes.** Each test still builds
/// the scene and rasterises it, then compares against the committed file. A
/// harness that could regenerate the expectation it just failed against would
/// not be a gate, which is why `generate.dart` stays a separate, deliberate
/// run.
///
/// The size is per variant, not global: a scene is rasterised at its own
/// viewBox, and `ring`'s is 90 where the others are 80.
library;

import 'package:boring_avatars/src/scene/scene.dart';
import 'package:boring_avatars/src/variants/bauhaus.dart';
import 'package:boring_avatars/src/variants/pixel.dart';
import 'package:boring_avatars/src/variants/ring.dart';
import 'package:boring_avatars/src/variants/sunset.dart';

/// Upstream's own default palette.
const goldenDefaultPalette = [
  '#92A1C6',
  '#146A7C',
  '#F0AB3D',
  '#C271B4',
  '#C20D90',
];

/// Every committed golden: name → the scene it draws and the square it draws
/// it into.
final Map<String, (SvgNode, int)> goldenCases = {
  'pixel-clara-default': (
    buildPixelScene(
      name: 'Clara Barton',
      colors: goldenDefaultPalette,
      size: 80,
    ),
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
    buildRingScene(
      name: 'Clara Barton',
      colors: goldenDefaultPalette,
      size: 90,
    ),
    90,
  ),
  'ring-alice-pair': (
    buildRingScene(name: 'Alice', colors: ['#000000', '#FFFFFF'], size: 90),
    90,
  ),
  'ring-clara-square': (
    buildRingScene(
      name: 'Clara Barton',
      colors: goldenDefaultPalette,
      size: 90,
      square: true,
    ),
    90,
  ),
  // A second name, because `sunset` was rasterised for one only — and the
  // corpus name that would have caught the url-fragment divergence is not
  // `Clara Barton`.
  'sunset-clara-default': (
    buildSunsetScene(
      name: 'Clara Barton',
      colors: goldenDefaultPalette,
      size: 80,
    ),
    80,
  ),
  'sunset-empty-palette': (
    buildSunsetScene(name: 'Clara Barton', colors: const [], size: 80),
    80,
  ),
  'sunset-hangul': (
    buildSunsetScene(name: '박기현', colors: goldenDefaultPalette, size: 80),
    80,
  ),
  'sunset-clara-square': (
    buildSunsetScene(
      name: 'Clara Barton',
      colors: goldenDefaultPalette,
      size: 80,
      square: true,
    ),
    80,
  ),
  // `bauhaus`: the two names separate `isSquare`'s branches — `Clara Barton` is
  // true, turning its bar 22° and its rule 44°; `Alice` is false, turning them
  // 176° and 352° — and the empty name hashes to 0, so every transform is the
  // identity and every edge lands on a pixel boundary. (The angles are the
  // *drawn* ones. `properties[0].rotate` is 191° and 88°, and element 0
  // contributes only a colour — a distinction the #39 completeness pass caught
  // in three comments at once.)
  //
  // There is deliberately **no empty-palette golden** here: it would be a fully
  // transparent image, and freezing a blank as correct is the failure #40 found
  // in `sunset`. `bauhaus_raster_test.dart` asserts the blank as behaviour.
  'bauhaus-clara-default': (
    buildBauhausScene(
      name: 'Clara Barton',
      colors: goldenDefaultPalette,
      size: 80,
    ),
    80,
  ),
  'bauhaus-alice-pair': (
    buildBauhausScene(name: 'Alice', colors: ['#000000', '#FFFFFF'], size: 80),
    80,
  ),
  'bauhaus-empty-name': (
    buildBauhausScene(name: '', colors: goldenDefaultPalette, size: 80),
    80,
  ),
  'bauhaus-clara-square': (
    buildBauhausScene(
      name: 'Clara Barton',
      colors: goldenDefaultPalette,
      size: 80,
      square: true,
    ),
    80,
  ),
};

/// The cases whose name starts with `<variant>-`, in declaration order.
Map<String, (SvgNode, int)> goldenCasesFor(String variant) => {
  for (final e in goldenCases.entries)
    if (e.key.startsWith('$variant-')) e.key: e.value,
};
