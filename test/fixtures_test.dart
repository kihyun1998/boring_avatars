import 'dart:convert';
import 'dart:io';

import 'package:boring_avatars/boring_avatars.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the parity fixtures themselves.
///
/// Nothing here exercises this package's own logic — that arrives with the
/// tickets that consume these files. What it does is make a truncated, stale or
/// partially regenerated fixture fail the gate *now*, rather than silently
/// weakening a later test that reads it.
void main() {
  final corpus =
      jsonDecode(File('test/fixtures/corpus.json').readAsStringSync())
          as Map<String, dynamic>;
  final names = (corpus['names'] as List).cast<Map<String, dynamic>>();
  final palettes = (corpus['palettes'] as List).cast<Map<String, dynamic>>();

  group('corpus', () {
    test('is reachable from the package root', () {
      expect(File('test/fixtures/corpus.json').existsSync(), isTrue);
    });

    test(
      'name and palette ids are unique — a collision would silently drop a case',
      () {
        final nameIds = names.map((n) => n['id']).toList();
        final paletteIds = palettes.map((p) => p['id']).toList();
        expect(nameIds.toSet(), hasLength(nameIds.length));
        expect(paletteIds.toSet(), hasLength(paletteIds.length));
      },
    );

    test('covers the inputs the hidden-state list calls out', () {
      final values = {
        for (final n in names) n['id'] as String: n['value'] as String,
      };
      expect(values['empty'], '');
      // Surrogate pairs are the case where iterating code units and iterating
      // code points diverge.
      expect(
        values['emoji-zwj']!.runes.length,
        lessThan(values['emoji-zwj']!.length),
      );
      expect(values['long-200-mixed']!.length, greaterThan(150));
      expect(values.values.any((v) => v.contains(' ')), isTrue);
    });

    test('includes a single-colour palette — the modulus edge', () {
      expect(palettes.map((p) => (p['value'] as List).length), contains(1));
    });
  });

  for (final version in BoringAvatarsVersion.values) {
    final dir = 'test/fixtures/${version.name}';

    group('fixtures for ${version.name}', () {
      test('both fixture files exist', () {
        expect(File('$dir/utilities.json').existsSync(), isTrue, reason: dir);
        expect(File('$dir/svg.json').existsSync(), isTrue, reason: dir);
      });

      test('they declare the upstream releases this version claims', () {
        for (final file in ['utilities.json', 'svg.json']) {
          final json =
              jsonDecode(File('$dir/$file').readAsStringSync())
                  as Map<String, dynamic>;
          expect(
            (json['upstreamReleases'] as List).cast<String>(),
            version.upstreamVersions,
            reason: file,
          );
        }
      });

      test('utilities cover every corpus name', () {
        final json =
            jsonDecode(File('$dir/utilities.json').readAsStringSync())
                as Map<String, dynamic>;
        final hashCodes = json['hashCode'] as Map<String, dynamic>;
        final derived = json['derived'] as Map<String, dynamic>;
        for (final n in names) {
          expect(hashCodes, contains(n['id']), reason: '${n['id']}');
          expect(derived, contains(n['id']), reason: '${n['id']}');
        }
        expect(hashCodes, hasLength(names.length));
      });

      test('hashCode values are non-negative 32-bit-derived integers', () {
        final json =
            jsonDecode(File('$dir/utilities.json').readAsStringSync())
                as Map<String, dynamic>;
        for (final entry
            in (json['hashCode'] as Map<String, dynamic>).entries) {
          final v = entry.value as int;
          expect(v, greaterThanOrEqualTo(0), reason: entry.key);
          // Math.abs of a 32-bit signed value cannot exceed 2^31.
          expect(v, lessThanOrEqualTo(2147483648), reason: entry.key);
        }
      });

      test('renders cover every renderable variant x name x palette', () {
        final json =
            jsonDecode(File('$dir/svg.json').readAsStringSync())
                as Map<String, dynamic>;
        final renders = json['renders'] as Map<String, dynamic>;
        for (final variant in BoringAvatarsVariant.renderable) {
          for (final n in names) {
            for (final p in palettes) {
              final key = '${variant.upstreamName}|${n['id']}|${p['id']}';
              expect(renders, contains(key), reason: key);
            }
          }
        }
        expect(
          renders,
          hasLength(
            BoringAvatarsVariant.renderable.length *
                names.length *
                palettes.length,
          ),
        );
      });

      test('every rendered entry is a complete svg element', () {
        final json =
            jsonDecode(File('$dir/svg.json').readAsStringSync())
                as Map<String, dynamic>;
        for (final entry in (json['renders'] as Map<String, dynamic>).entries) {
          if (entry.value is! String) continue; // a recorded throw
          final svg = entry.value as String;
          expect(svg, startsWith('<svg '), reason: entry.key);
          expect(svg, endsWith('</svg>'), reason: entry.key);
        }
      });

      test('generated ids are normalised away, but <title> is not', () {
        final json =
            jsonDecode(File('$dir/svg.json').readAsStringSync())
                as Map<String, dynamic>;
        final rendered = (json['renders'] as Map<String, dynamic>).values
            .whereType<String>()
            .toList();
        for (final svg in rendered) {
          expect(svg, isNot(matches(RegExp('id="(?!_")'))));
        }
        // 1.6.x emits <title> unconditionally and offers no prop to stop it, so
        // it has to survive into the fixture — see hidden-state #16.
        expect(
          rendered.where((s) => s.contains('<title>')),
          hasLength(rendered.length),
        );
      });

      test(
        'the two fixtures agree, though they come from different sources',
        () {
          // utilities.json is imported from the git tag's source; svg.json is
          // rendered from the npm package. Those can disagree — npm 1.8.0 and
          // 1.9.0 shipped no JavaScript at all, so their fixtures have to come
          // from the tag instead. This pins the two together.
          //
          // marble's background rect is the first rect inside the masked group,
          // and upstream fills it with getRandomColor(hash + 0, colors, range),
          // which is colors[hash % range].
          final utilities =
              jsonDecode(File('$dir/utilities.json').readAsStringSync())
                  as Map<String, dynamic>;
          final hashCodes = (utilities['hashCode'] as Map<String, dynamic>);
          final renders =
              ((jsonDecode(File('$dir/svg.json').readAsStringSync())
                          as Map<String, dynamic>)['renders']
                      as Map<String, dynamic>)
                  .cast<String, String>();

          var checked = 0;
          for (final n in names) {
            for (final p in palettes) {
              // The empty palette has no colour to predict — upstream indexes it
              // with NaN. Its degrade is pinned by its own test below.
              if ((p['value'] as List).isEmpty) continue;
              final svg = renders['marble|${n['id']}|${p['id']}']!;
              final body = svg.substring(svg.indexOf('<g mask='));
              final fill = RegExp(
                r'<rect[^>]*fill="([^"]+)"',
              ).firstMatch(body)!.group(1);
              final colours = (p['value'] as List).cast<String>();
              final hash = hashCodes[n['id']] as int;
              expect(
                fill,
                colours[hash % colours.length],
                reason: '${n['id']} / ${p['id']}',
              );
              checked++;
            }
          }
          expect(
            checked,
            names.length *
                palettes.where((p) => (p['value'] as List).isNotEmpty).length,
          );
        },
      );

      test('an empty palette degrades everywhere except beam, which throws', () {
        // hidden-state #8, measured rather than assumed. Upstream indexes
        // colours with `n % 0`, which is NaN, so `colors[NaN]` is undefined.
        //
        // Five variants put that undefined straight into a fill, and React
        // drops the attribute. `beam` does not: it feeds the same undefined to
        // getContrast, which calls `.slice` on it and throws. So "empty palette
        // degrades" is true per variant, not in general — and a port has to
        // reproduce both halves.
        final emptyPalette = palettes
            .where((p) => (p['value'] as List).isEmpty)
            .toList();
        expect(
          emptyPalette,
          hasLength(1),
          reason: 'the empty-palette edge must stay in the corpus',
        );
        final id = emptyPalette.single['id'];

        final renders =
            ((jsonDecode(File('$dir/svg.json').readAsStringSync())
                    as Map<String, dynamic>)['renders']
                as Map<String, dynamic>);

        for (final variant in BoringAvatarsVariant.renderable) {
          for (final n in names) {
            final entry = renders['${variant.upstreamName}|${n['id']}|$id'];
            final where = '${variant.upstreamName}/${n['id']}';

            if (variant == BoringAvatarsVariant.beam) {
              expect(entry, isA<Map<String, dynamic>>(), reason: where);
              expect(
                (entry as Map<String, dynamic>)['__throws'],
                'TypeError',
                reason: where,
              );
            } else {
              expect(entry, isA<String>(), reason: where);
              expect(
                RegExp(
                  r'<(rect|path|circle|line)(?![^>]*fill=)',
                ).hasMatch(entry as String),
                isTrue,
                reason: '$where should have lost a fill attribute',
              );
            }
          }
        }
      });

      test('size is a passthrough — only width and height move with it', () {
        final json =
            jsonDecode(File('$dir/svg.json').readAsStringSync())
                as Map<String, dynamic>;
        final bySize = (json['sizePassthrough'] as Map<String, dynamic>)
            .cast<String, String>();
        expect(bySize.length, greaterThanOrEqualTo(2));

        // **Grouped by everything except the size itself.** The section held
        // one variant from #33 to #59, so "every entry strips to one string"
        // was the whole check; it now varies variant, name and `square` too,
        // and those renders are *supposed* to differ. What survives unchanged
        // is the question — did `size` reach anything but the svg element's
        // own width and height — asked once per (variant, name, square).
        final byCase = <String, Set<String>>{};
        for (final e in bySize.entries) {
          final parts = e.key.split('|');
          expect(
            parts,
            hasLength(4),
            reason: 'a key is <variant>|<name>|<size>|<sq|rd>',
          );
          (byCase['${parts[0]}|${parts[1]}|${parts[3]}'] ??= <String>{}).add(
            e.value.replaceAll(RegExp(r'(width|height)="\d+"'), r'$1="_"'),
          );
        }
        expect(
          byCase.keys.map((k) => k.split('|').first).toSet(),
          hasLength(6),
          reason: 'every variant carries its own size renders, not just one',
        );
        expect(
          byCase,
          hasLength(6 * 2 * 2),
          reason: 'variant × name × square, each at both sizes',
        );
        for (final e in byCase.entries) {
          expect(
            e.value,
            hasLength(1),
            reason:
                '${e.key}: size reached the drawing, not just the svg '
                'attributes',
          );
        }
      });

      test('a string size is a passthrough too, and no \\d+ strip sees it', () {
        final json =
            jsonDecode(File('$dir/svg.json').readAsStringSync())
                as Map<String, dynamic>;
        final byString =
            (json['sizePassthroughStrings'] as Map<String, dynamic>)
                .cast<String, String>();
        expect(byString, hasLength(30));

        // The attribute is **read**, not rebuilt from the key: React escapes
        // the value like any other, so the `a"b` case reaches the document as
        // `a&quot;b` and a guard that reconstructed it would be asserting its
        // own copy of the escaper. What matters here is the shape — width and
        // height carry the same value, and nothing else moved.
        final stripped = <String>{};
        for (final e in byString.entries) {
          final pair = RegExp(
            r'^<svg [^>]*? width="([^"]*)" height="([^"]*)"',
          ).firstMatch(e.value);
          expect(pair, isNotNull, reason: e.key);
          expect(pair!.group(2), pair.group(1), reason: e.key);
          stripped.add(
            '${e.key.split('|').first}::'
            '${e.value.replaceFirst(pair.group(0)!, '_')}',
          );
        }
        expect(
          stripped,
          hasLength(6),
          reason: 'a string size moved something other than width/height',
        );
      });
    });
  }
}
