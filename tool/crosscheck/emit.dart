// Writes this package's SVG for every cross-check case.
//
//   dart run tool/crosscheck/emit.dart <work-dir>
//
// Step one of two. `crosscheck.mjs` renders upstream's own React output and
// this file's output in the *same* browser and compares the pixels; see its
// header for why that is the strong comparison.
//
// **Unnormalised, on purpose.** `test/fixtures/<version>/svg.json` stores the
// renders with `id="…"`, `url(#…)` and `mask="…"` replaced by placeholders, so
// a fixture entry cannot be handed to a browser at all — `mask="_"` has lost
// the `url()` wrapper and would render unmasked. Everything the byte gate
// normalises away is exactly what this comparison exists to see, so nothing
// here is normalised.
import 'dart:convert';
import 'dart:io';

import 'package:boring_avatars/src/scene/scene.dart';
import 'package:boring_avatars/src/svg/emitter.dart';
import 'package:boring_avatars/src/variants/bauhaus.dart';
import 'package:boring_avatars/src/variants/beam.dart';
import 'package:boring_avatars/src/variants/marble.dart';
import 'package:boring_avatars/src/variants/pixel.dart';
import 'package:boring_avatars/src/variants/ring.dart';
import 'package:boring_avatars/src/variants/sunset.dart';

/// **Every variant upstream dispatches at 1.6.1** — the full roster, not the
/// ported subset.
///
/// It is listed in full so the harness can say what it did *not* cover. A tool
/// that silently ran four of six reads as "everything agrees"; the two missing
/// names have to appear in its own output or nobody sees the hole. Same rule as
/// the fixture sweep's "the sweep covered every name and palette, not a subset".
const upstreamVariants = [
  'marble',
  'beam',
  'pixel',
  'sunset',
  'ring',
  'bauhaus',
];

/// The subset this package can build a scene for today.
///
/// All six as of #41 — `marble` was the last one missing, and the guard below
/// is what made adding it here part of that change rather than a later sweep.
const portedVariants = [
  'marble',
  'pixel',
  'sunset',
  'ring',
  'bauhaus',
  'beam',
];

/// The size both sides are rendered at.
///
/// Four times the natural 80, so a sub-pixel geometry difference becomes four
/// pixels wide instead of hiding inside one. Both documents carry the same
/// `width`/`height` and their own `viewBox`, so the browser scales them
/// identically — and a prop the fixture matrix never varies is a prop nobody
/// has compared to upstream (#37), which this incidentally does.
const renderSize = 320;

SvgNode build(
  String variant,
  String name,
  List<String> colors, {
  required bool square,
}) => switch (variant) {
  'pixel' => buildPixelScene(
    name: name,
    colors: colors,
    size: renderSize,
    square: square,
  ),
  'ring' => buildRingScene(
    name: name,
    colors: colors,
    size: renderSize,
    square: square,
  ),
  'sunset' => buildSunsetScene(
    name: name,
    colors: colors,
    size: renderSize,
    square: square,
  ),
  'bauhaus' => buildBauhausScene(
    name: name,
    colors: colors,
    size: renderSize,
    square: square,
  ),
  'beam' => buildBeamScene(
    name: name,
    colors: colors,
    size: renderSize,
    square: square,
  ),
  'marble' => buildMarbleScene(
    name: name,
    colors: colors,
    size: renderSize,
    square: square,
  ),
  _ => throw ArgumentError('no builder for "$variant"'),
};

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/crosscheck/emit.dart <work-dir>');
    exit(2);
  }
  final dir = Directory(args.first)..createSync(recursive: true);

  final corpus =
      jsonDecode(File('test/fixtures/corpus.json').readAsStringSync())
          as Map<String, dynamic>;
  final names = (corpus['names'] as List).cast<Map<String, dynamic>>();
  final palettes = (corpus['palettes'] as List).cast<Map<String, dynamic>>();

  // A variant that gains a file but not a line here would be compared by
  // nobody while the harness still printed a pass. Checked rather than trusted.
  final built = Directory('lib/src/variants')
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('.dart'))
      .map((n) => n.substring(0, n.length - '.dart'.length))
      .toSet();
  if (built.difference(portedVariants.toSet()).isNotEmpty ||
      portedVariants.toSet().difference(built).isNotEmpty) {
    stderr.writeln(
      'lib/src/variants holds ${built.toList()..sort()} but this harness '
      'lists ${portedVariants.toList()..sort()} — add the new one here, or '
      'it is verified by nobody',
    );
    exit(1);
  }

  final out = <String, String>{};
  // **Refusing is an outcome, not a crash.** `beam` throws on an empty palette
  // because upstream does (hidden-state #8), so for those inputs there is no
  // document on *either* side. Recording the refusal is what lets the browser
  // half treat "both refused" as agreement: letting it propagate would end the
  // run, and swallowing it would drop 40 renders and still print a pass.
  final refused = <String, String>{};
  // **Both `square` values.** The fixture matrix runs at one, and #37 recorded
  // what that costs: `pixel` shipped with `square` asserted only against itself
  // *and a golden committed for it*. A prop the matrix never varies is a prop
  // nobody has compared to upstream.
  for (final variant in portedVariants) {
    for (final n in names) {
      for (final p in palettes) {
        for (final square in [false, true]) {
          final key = '$variant|${n['id']}|${p['id']}|${square ? 'sq' : 'rd'}';
          try {
            out[key] = emitSvg(
              build(
                variant,
                n['value'] as String,
                (p['value'] as List).cast<String>(),
                square: square,
              ),
            );
          } on ArgumentError {
            refused[key] = 'ArgumentError';
          }
        }
      }
    }
  }

  File('${dir.path}/ours.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'renders': out,
      'refused': refused,
      'upstreamVariants': upstreamVariants,
      'portedVariants': portedVariants,
      'size': renderSize,
    }),
  );
  stdout.writeln(
    'wrote ${dir.path}/ours.json — ${out.length} renders, '
    '${refused.length} refused',
  );
  final uncovered = upstreamVariants
      .where((v) => !portedVariants.contains(v))
      .toList();
  if (uncovered.isNotEmpty) {
    stdout.writeln('NOT COVERED: ${uncovered.join(", ")} — not ported yet');
  }
}
