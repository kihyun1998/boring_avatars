// The layer-3 parity calibration: our rasterizer against a real Chrome render.
//
//   dart run tool/calibrate/compare.dart <work-dir>     # writes scenes.json
//   node tool/calibrate/render.mjs      <work-dir>      # drives Chrome
//   dart run tool/calibrate/compare.dart <work-dir>     # reports the diff
//
// The first pass emits the SVG our own emitter produces, so Chrome and the
// rasterizer are handed the *same document* — otherwise the comparison could
// pass while the two backends disagreed about what to draw.
//
// A TOOL, not a gate. See tool/calibrate/render.mjs for why.
import 'dart:convert';
import 'dart:io';

import 'package:boring_avatars/src/raster/scene_raster.dart';
import 'package:boring_avatars/src/scene/scene.dart';
import 'package:boring_avatars/src/svg/emitter.dart';
import 'package:boring_avatars/src/variants/bauhaus.dart';
import 'package:boring_avatars/src/variants/marble.dart';
import 'package:boring_avatars/src/variants/pixel.dart';
import 'package:boring_avatars/src/variants/ring.dart';
import 'package:boring_avatars/src/variants/sunset.dart';

const _default = ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'];

final _cases = <String, (SvgNode, int)>{
  // `bauhaus` is the first variant with a rotated shape and the first with a
  // stroke, so the two names below separate the branches: `Clara Barton` has
  // `isSquare` true and turns its bar 22° and its rule 44°; `Alice` has it
  // false and turns them 176° and 352° — nearly horizontal, which is where a
  // rasterizer and a browser disagree most. The empty name hashes to 0, so
  // every transform is the identity and every edge lands on a pixel boundary.
  //
  // Read the drawn angles off the fixture, not off `properties[0]`: element 0
  // contributes a colour and nothing else, and its rotation — 191° for Clara,
  // 88° for Alice — reaches no pixel. Three comments in this repo cited those
  // two numbers as the reason for this case selection; the #39 completeness
  // pass caught it.
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
  'pixel-clara-default': (
    buildPixelScene(name: 'Clara Barton', colors: _default, size: 80),
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
  'ring-clara-square': (
    buildRingScene(
      name: 'Clara Barton',
      colors: _default,
      size: 90,
      square: true,
    ),
    90,
  ),
  // `marble` is the first variant with a filter and the first with a blend
  // mode, and it is the one case in this harness where the recorded ≤1/255 bar
  // is **not** obviously unmeetable: SVG 1.1 §15.17 specifies the blur as an
  // exact three-box algorithm rather than leaving it to the renderer, so both
  // sides compute the same convolution. Measured separately at sigma 56 device
  // px: 0/255 across a step edge. Contrast hidden-state #27, where Chrome's own
  // curve tessellation puts the bar out of reach whatever we do.
  //
  // The empty name hashes to 0, so both blobs take `rotate(0)` and
  // `translate(0 0)` — the identity — and the only thing under test is the blur
  // and the blend. The other two carry rotation and a non-unit scale.
  'marble-empty-name': (
    buildMarbleScene(name: '', colors: _default, size: 80),
    80,
  ),
  'marble-clara-default': (
    buildMarbleScene(name: 'Clara Barton', colors: _default, size: 80),
    80,
  ),
  'marble-alice-pair': (
    buildMarbleScene(name: 'Alice', colors: ['#000000', '#FFFFFF'], size: 80),
    80,
  ),
  'marble-clara-square': (
    buildMarbleScene(
      name: 'Clara Barton',
      colors: _default,
      size: 80,
      square: true,
    ),
    80,
  ),
};

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/calibrate/compare.dart <work-dir>');
    exit(2);
  }
  final dir = Directory(args.first)..createSync(recursive: true);

  final scenes = <String, Map<String, Object>>{};
  for (final entry in _cases.entries) {
    final (scene, size) = entry.value;
    scenes[entry.key] = {'svg': emitSvg(scene), 'size': size};
  }
  File('${dir.path}/scenes.json').writeAsStringSync(jsonEncode(scenes));

  var missing = 0;
  var worstEdge = 0;
  var totalInterior = 0;

  for (final entry in _cases.entries) {
    final reference = File('${dir.path}/${entry.key}.rgba');
    if (!reference.existsSync()) {
      missing++;
      continue;
    }
    final (scene, size) = entry.value;
    final ours = rasterizeScene(scene, width: size, height: size);
    final theirs = reference.readAsBytesSync();

    var interior = 0;
    var edges = 0;
    var worst = 0;
    var worstAt = '';
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final i = (y * size + x) * 4;
        // Compared **premultiplied**, which is the only representation where a
        // nearly-transparent pixel's colour means anything. Both sides store
        // straight alpha, and there the RGB of an alpha-3 pixel is the full
        // undiluted colour — so a pixel we cover by 3/255 and Chrome does not
        // cover at all reads as a delta of 240 on a difference nobody could
        // see. Premultiplied, the same pixel differs by 3.
        var delta = 0;
        for (var c = 0; c < 4; c++) {
          final o = c == 3
              ? ours.bytes[i + 3]
              : (ours.bytes[i + c] * ours.bytes[i + 3] / 255).round();
          final t = c == 3
              ? theirs[i + 3]
              : (theirs[i + c] * theirs[i + 3] / 255).round();
          final d = (o - t).abs();
          if (d > delta) delta = d;
        }
        if (delta == 0) continue;
        if (_isEdge(theirs, size, x, y)) {
          edges++;
          if (delta > worst) {
            worst = delta;
            worstAt = '($x, $y)';
          }
        } else {
          interior++;
          if (interior <= 5) {
            stdout.writeln(
              '  interior ($x, $y): ours '
              '${ours.bytes.sublist(i, i + 4)} vs Chrome '
              '${theirs.sublist(i, i + 4)}',
            );
          }
        }
      }
    }
    worstEdge = worst > worstEdge ? worst : worstEdge;
    totalInterior += interior;
    stdout.writeln(
      '${entry.key.padRight(22)} interior mismatches $interior, '
      'edge mismatches $edges, worst edge delta $worst'
      '${worstAt.isEmpty ? '' : ' at $worstAt'}',
    );
  }

  if (missing > 0) {
    stdout.writeln(
      '\nwrote ${dir.path}/scenes.json — now run\n'
      '  node tool/calibrate/render.mjs ${dir.path}\n'
      'and re-run this command. ($missing reference renders missing)',
    );
    return;
  }

  stdout.writeln(
    '\nbar: interior 0, edge <= 1  ->  '
    '${totalInterior == 0 && worstEdge <= 1 ? "PASS" : "FAIL"} '
    '(interior $totalInterior, worst edge $worstEdge)',
  );
  if (totalInterior != 0 || worstEdge > 1) exit(1);
}

/// Whether (x, y) sits on a coverage boundary in the reference.
///
/// **This classifier is defeated by a gradient.** It asks whether the pixel's
/// 3×3 neighbourhood is uniform, which is a good proxy for "antialiasing
/// happens here" on a flat-filled shape and useless on `sunset`, where every
/// pixel differs from the one above it by design. Every gradient pixel is
/// therefore counted as an edge, and "interior mismatches 0" says nothing at
/// all for that variant.
///
/// Measured separately for `sunset`, excluding the mask rim: all 4548 gradient
/// pixels are within **1/255** of Chrome — 58.6% exact, 41.4% off by one, which
/// is Chrome's gradient dither. The bar is met there; what fails is the mask's
/// curve, which is hidden-state #27 and the same failure `pixel` has.
bool _isEdge(List<int> bytes, int size, int x, int y) {
  int at(int px, int py, int c) => bytes[(py * size + px) * 4 + c];
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      final nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= size || ny >= size) continue;
      for (var c = 0; c < 4; c++) {
        if (at(nx, ny, c) != at(x, y, c)) return true;
      }
    }
  }
  return false;
}
