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
import 'package:boring_avatars/src/variants/beam.dart';
import 'package:boring_avatars/src/variants/marble.dart';
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
      title: true,
      name: 'Clara Barton',
      colors: goldenDefaultPalette,
      size: 80,
    ),
    80,
  ),
  'pixel-alice-pair': (
    buildPixelScene(
      title: true,
      name: 'Alice',
      colors: ['#000000', '#FFFFFF'],
      size: 80,
    ),
    80,
  ),
  // **`pixel` had no square golden until #80.** Its square case was asserted
  // inline in `pixel_raster_test.dart` but never committed, so the widget's
  // "six variants x both square states" proof had one cell it could not reach —
  // and nothing said so, because a missing golden is invisible to a roster that
  // only checks the files it already lists against the cases it already has.
  'pixel-clara-square': (
    buildPixelScene(
      title: true,
      name: 'Clara Barton',
      colors: goldenDefaultPalette,
      size: 80,
      square: true,
    ),
    80,
  ),
  'pixel-empty-name': (
    buildPixelScene(title: true, name: '', colors: ['#FF0000'], size: 80),
    80,
  ),
  'ring-clara-default': (
    buildRingScene(
      title: true,
      name: 'Clara Barton',
      colors: goldenDefaultPalette,
      size: 90,
    ),
    90,
  ),
  'ring-alice-pair': (
    buildRingScene(
      title: true,
      name: 'Alice',
      colors: ['#000000', '#FFFFFF'],
      size: 90,
    ),
    90,
  ),
  'ring-clara-square': (
    buildRingScene(
      title: true,
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
      title: true,
      name: 'Clara Barton',
      colors: goldenDefaultPalette,
      size: 80,
    ),
    80,
  ),
  'sunset-empty-palette': (
    buildSunsetScene(
      title: true,
      name: 'Clara Barton',
      colors: const [],
      size: 80,
    ),
    80,
  ),
  'sunset-hangul': (
    buildSunsetScene(
      title: true,
      name: '박기현',
      colors: goldenDefaultPalette,
      size: 80,
    ),
    80,
  ),
  'sunset-clara-square': (
    buildSunsetScene(
      title: true,
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
      title: true,
      name: 'Clara Barton',
      colors: goldenDefaultPalette,
      size: 80,
    ),
    80,
  ),
  'bauhaus-alice-pair': (
    buildBauhausScene(
      title: true,
      name: 'Alice',
      colors: ['#000000', '#FFFFFF'],
      size: 80,
    ),
    80,
  ),
  'bauhaus-empty-name': (
    buildBauhausScene(
      title: true,
      name: '',
      colors: goldenDefaultPalette,
      size: 80,
    ),
    80,
  ),
  'bauhaus-clara-square': (
    buildBauhausScene(
      title: true,
      name: 'Clara Barton',
      colors: goldenDefaultPalette,
      size: 80,
      square: true,
    ),
    80,
  ),
  // `beam` rasterises at **36**, not 80 — its own viewBox, and the smallest in
  // the package. Hidden-state #26 said otherwise until #38 measured it, and a
  // golden generated at 80 would be a different picture that still looked
  // plausible.
  //
  // The three names split every branch that changes the drawing:
  //
  // | | mouth | card | scale | rotation |
  // |---|---|---|---|---|
  // | `Clara Barton` | **open** — a stroked cubic | rounded square, rx 6 | 1.2 | 191° |
  // | `Alice` | **closed** — the F.6.6 arc | circle, rx clamped to 18 | 1.1 | 88° |
  // | the empty name | open | circle | **1.0** | **0°** |
  //
  // The empty name hashes to 0, so every transform is the identity and every
  // edge lands on a pixel boundary — the same role it plays for `bauhaus`, and
  // the case that isolates the geometry from the transform composition.
  //
  // There is deliberately **no empty-palette golden**: `beam` is the one
  // variant that throws on one, so there is no image to freeze.
  'beam-clara-default': (
    buildBeamScene(
      title: true,
      name: 'Clara Barton',
      colors: goldenDefaultPalette,
      size: 36,
    ),
    36,
  ),
  'beam-alice-default': (
    buildBeamScene(
      title: true,
      name: 'Alice',
      colors: goldenDefaultPalette,
      size: 36,
    ),
    36,
  ),
  'beam-empty-name': (
    buildBeamScene(
      title: true,
      name: '',
      colors: goldenDefaultPalette,
      size: 36,
    ),
    36,
  ),
  'beam-clara-square': (
    buildBeamScene(
      title: true,
      name: 'Clara Barton',
      colors: goldenDefaultPalette,
      size: 36,
      square: true,
    ),
    36,
  ),
  // `marble` is the only variant with a filter and the only one with a blend
  // mode, and the four names below split what those two actually depend on:
  //
  // | | scale | sigma (device px) | d | branch | blend backdrop |
  // |---|---|---|---|---|---|
  // | the empty name | 1.2 | 8.4 | 16 | **even** | flat colours |
  // | `Clara Barton` | 1.3 | 9.1 | 17 | odd | flat colours |
  // | `Alice` | 1.2 | 8.4 | 16 | even | **saturating** black/white |
  //
  // The scale matters because the declared `stdDeviation="7"` is in the
  // *element's* user space, which includes its own `transform` — so the blur is
  // 8.4 or 9.1 device pixels and never 7. Getting that wrong measured 27/255
  // against Chrome; these two names put the three-box approximation's odd and
  // even branches on opposite sides of the roster so neither can rot unread.
  //
  // `Alice`'s two-colour palette is the case that makes the blend visible at
  // all: `overlay` against an opaque white backdrop returns white whatever the
  // source is, so a port that dropped the blend entirely still differs there
  // and nowhere else. It is also the only case whose mismatches against Chrome
  // land in the *interior* — a blurred variant has no 3×3-uniform pixel, so the
  // calibration's interior statistic is vacuous for `marble` except where the
  // blend saturates a region flat (hidden-state #42).
  //
  // `marble-clara-square` is not decoration: dropping the mask's corner radius
  // takes the worst edge disagreement from 71/255 to **5**, which is what
  // separates the blur's error from the mask curve's (hidden-state #27).
  //
  // There is deliberately **no empty-palette golden**: all three fills are
  // dropped and the result is a fully transparent image, and freezing a blank
  // as correct is the failure #40 found in `sunset`.
  'marble-clara-default': (
    buildMarbleScene(
      title: true,
      name: 'Clara Barton',
      colors: goldenDefaultPalette,
      size: 80,
    ),
    80,
  ),
  'marble-alice-pair': (
    buildMarbleScene(
      title: true,
      name: 'Alice',
      colors: ['#000000', '#FFFFFF'],
      size: 80,
    ),
    80,
  ),
  'marble-empty-name': (
    buildMarbleScene(
      title: true,
      name: '',
      colors: goldenDefaultPalette,
      size: 80,
    ),
    80,
  ),
  'marble-clara-square': (
    buildMarbleScene(
      title: true,
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
