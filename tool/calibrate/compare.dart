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
  // #83 — hidden-state #24, live for the first time since it was written.
  //
  // **Every case above renders at the variant's own viewBox side**, which is the
  // one target where the row is inert: `pixel`'s 10-unit tiles land exactly on
  // pixel boundaries and no two shapes meet *inside* a pixel. So this harness
  // has never been in a position to see the row, and its 0s never said anything
  // about it.
  //
  // Asking for a different number costs nothing structural: `size` reaches
  // `width`/`height` only and the viewBox is a per-variant constant
  // (`pixel.dart:25`), so both sides are handed the *same document* at a device
  // scale of 100/80. That is the whole point of the harness and it still holds.
  //
  // 100 is the number hidden-state #24 nominated. 210 is the one a widget
  // actually asks for — a 80-logical avatar at the 2.625 device pixel ratio
  // #58's derivation names — and it is where the row measured its worst count.
  'pixel-clara-100': (
    buildPixelScene(name: 'Clara Barton', colors: _default, size: 100),
    100,
  ),
  // **The discriminating case.** Without the rounded mask every edge in the
  // render is axis-aligned, and hidden-state #27 measured Chrome *exact* there
  // (0.003 px at fractional edges) where its curves are up to 0.13 px off. The
  // 71/255 that five rows of the table above carry is the mask's own curve, so
  // removing it removes the noise this question would otherwise be buried in.
  'pixel-clara-square-100': (
    buildPixelScene(
      name: 'Clara Barton',
      colors: _default,
      size: 100,
      square: true,
    ),
    100,
  ),
  'pixel-clara-210': (
    buildPixelScene(name: 'Clara Barton', colors: _default, size: 210),
    210,
  ),
  // The second variant the row names. `ring` abuts along `y=45` in four places,
  // which is a pixel boundary at 90 and is not at 101.
  'ring-clara-101': (
    buildRingScene(name: 'Clara Barton', colors: _default, size: 101),
    101,
  ),
  // #62 — a translucent palette, which nothing in this harness had before and
  // upstream's own palettes cannot produce.
  //
  // `bauhaus` because it is the variant that genuinely **stacks**: a
  // full-canvas background rect with three shapes drawn on top of it, so a
  // translucent colour composites against something rather than against the
  // void. That is the case #62's acceptance criteria name, and it is the one
  // that separates "alpha reached the parser" from "alpha reached the
  // compositor".
  //
  // `sunset` because its colours arrive through `stop-color` and a gradient,
  // which interpolates alpha on a different code path from a solid fill — and
  // the interpolation model was itself a measured question (straight, not
  // premultiplied).
  'bauhaus-translucent': (
    buildBauhausScene(name: 'Clara Barton', colors: _translucent, size: 80),
    80,
  ),
  'sunset-translucent': (
    buildSunsetScene(name: 'Clara Barton', colors: _translucent, size: 80),
    80,
  ),
  // #63 — a palette written in the notations the parser learned here.
  //
  // **Not a six-variant × per-notation matrix, and that is deliberate.** A
  // notation decides what colour a string *is*; once parsed it is the same
  // `RasterColour` the hex path produces and takes the same code. The
  // notation→colour mapping is verified far more sharply than a variant render
  // could: all 148 names against the spec table *and* against Chrome, and every
  // function form measured directly. What these two cases add is the end of the
  // chain — that a scene carrying such a palette draws what Chrome draws — on
  // the variant that stacks and the variant that runs a gradient, which are the
  // two paths a colour can reach a pixel through.
  'bauhaus-named': (
    buildBauhausScene(name: 'Clara Barton', colors: _named, size: 80),
    80,
  ),
  'sunset-named': (
    buildSunsetScene(name: 'Clara Barton', colors: _named, size: 80),
    80,
  ),
  // #64 — a palette with truly invalid entries, which ADR-0001's invalid-value
  // rule answers: an unreadable `fill` or `stroke` paints nothing, an
  // unreadable `stop-color` paints black. Same two variants as #62/#63 and for
  // the same reason — the two paths a colour reaches a pixel through — plus the
  // property split is exactly what these two separate: `bauhaus` puts the bad
  // entries into `fill`/`stroke`, `sunset` into `stop-color`.
  //
  // The palette is **mixed** on purpose. All-invalid would render `bauhaus`
  // blank and `sunset` as a solid black disc — and a blank agrees with a
  // harness that drew nothing at all, while the black disc is byte-identical
  // to the empty-palette case, so neither could tell the invalid-value rule
  // from an accident. With valid neighbours the picture discriminates: the
  // shapes that drew prove the scene ran, beside the ones the rule erased or
  // blackened.
  'bauhaus-invalid': (
    buildBauhausScene(name: 'Clara Barton', colors: _invalid, size: 80),
    80,
  ),
  'sunset-invalid': (
    buildSunsetScene(name: 'Clara Barton', colors: _invalid, size: 80),
    80,
  ),
  // #95 — a palette in the Color 4 notations learned there, same two-variant
  // pattern as `-named` and `-invalid` and for the same reason. One entry per
  // family, including a wide-gamut `color()` (so the clip runs end-to-end)
  // and a system colour (the frozen-table path).
  'bauhaus-colour4': (
    buildBauhausScene(name: 'Clara Barton', colors: _colour4, size: 80),
    80,
  ),
  'sunset-colour4': (
    buildSunsetScene(name: 'Clara Barton', colors: _colour4, size: 80),
    80,
  ),
};

/// One of each notation, so a single run exercises the whole grammar: a name,
/// both function families, both separators, a percentage channel, an alpha as
/// a number and as a percentage, and a hue in a unit that is not degrees.
const _named = [
  'rebeccapurple',
  'rgb(20, 106, 124)',
  'hsl(38 87% 59%)',
  'rgba(194, 113, 180, 0.75)',
  'hsl(0.85turn 88% 40% / 60%)',
];

/// Both invalid rows of #64's Chrome table — a token no grammar admits and
/// the empty string — interleaved with valid neighbours so the render
/// discriminates (see the case comment).
const _invalid = ['zzz', '#146A7C', '', '#C20D90', 'rgb(255,0)'];

/// One of each family #95 learned: hwb, a Lab, an OKLCh, a wide-gamut
/// `color()` that leaves sRGB (the gamut clip, end-to-end), a system colour.
const _colour4 = [
  'hwb(210 20% 15%)',
  'lab(52.2% 40 -30)',
  'oklch(0.7 0.15 200)',
  'color(display-p3 1 0.2 0.1)',
  'accentcolor',
];

/// Five colours that all carry their own alpha, in the two short forms and the
/// long one, so a run exercises the expansion as well as the compositing.
const _translucent = [
  '#92A1C680',
  '#146A7C40',
  '#FA3', // #FFAA33, opaque — the three-digit form
  '#C271B4C0',
  '#C098', // #CC009988
];

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
    var worstInterior = 0;
    var worstInteriorAt = '';
    var edges = 0;
    var worst = 0;
    var worstAt = '';
    // Hidden-state #24's own shape, counted **without going through
    // [_isEdge]**: pixels Chrome fills solid that we leave translucent.
    //
    // The interior/edge split cannot answer this question on its own, and
    // hidden-state #42 is the general warning. Where two abutting tiles differ
    // in colour, Chrome's own 3x3 neighbourhood is non-uniform whatever it does
    // about the seam, so the pixel is filed as an edge and its delta lands
    // beside the mask curve's 71/255 — invisible. Only same-coloured neighbours
    // reach the interior bucket. This counter has no such blind spot: it asks
    // the row's question directly, in the row's own terms.
    var seams = 0;
    var worstSeam = 0;
    var seamAt = '';
    // **And the count that stops the one above from being tautological.** A
    // zero in `seams` means one of two opposite things — the seam exists and
    // Chrome conflates the same way, or there is no seam here to disagree
    // about — and only these two numbers separate them. Reported side by side
    // for that reason, never alone.
    var partialOurs = 0;
    var partialTheirs = 0;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final i = (y * size + x) * 4;
        if (theirs[i + 3] == 255 && ours.bytes[i + 3] < 255) {
          seams++;
          final deficit = 255 - ours.bytes[i + 3];
          if (deficit > worstSeam) {
            worstSeam = deficit;
            seamAt = '($x, $y)';
          }
          // Listed, not just aggregated: the row's prediction names a *place*
          // (`ring` abuts along y=45, `pixel` along its 10-unit tile grid), so
          // a count cannot tell the row's own mechanism apart from the curve
          // error hidden-state #27 already measures. Where they are is the
          // answer; how many there are is not.
          if (seams <= 12) stdout.writeln('    seam ($x, $y) -$deficit/255');
        }
        if (ours.bytes[i + 3] > 0 && ours.bytes[i + 3] < 255) partialOurs++;
        if (theirs[i + 3] > 0 && theirs[i + 3] < 255) partialTheirs++;
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
          // **The worst interior delta, not only the count.** The recorded bar
          // is interior *zero*, so until #62 a count was all anyone needed —
          // any non-zero was a failure and its size did not change that. A
          // translucent palette makes the size the whole question: 417 pixels
          // out by 1/255 and 417 out by 40 are different findings, and five
          // printed samples cannot tell them apart.
          if (delta > worstInterior) {
            worstInterior = delta;
            worstInteriorAt = '($x, $y)';
          }
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
      '${entry.key.padRight(24)} interior mismatches $interior'
      '${worstInteriorAt.isEmpty ? '' : ' (worst $worstInterior/255 at $worstInteriorAt)'}'
      ', edge mismatches $edges, worst edge delta $worst'
      '${worstAt.isEmpty ? '' : ' at $worstAt'}',
    );
    stdout.writeln(
      '${' '.padRight(24)} opaque in Chrome, translucent here: $seams'
      '${seamAt.isEmpty ? '' : ' (worst $worstSeam/255 at $seamAt)'}'
      '   [partial px — ours $partialOurs, Chrome $partialTheirs]',
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
