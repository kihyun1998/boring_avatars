import 'package:boring_avatars/boring_avatars.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BoringAvatarsVersion', () {
    test('declares only the upstream versions this release supports', () {
      expect(BoringAvatarsVersion.values, <BoringAvatarsVersion>[
        BoringAvatarsVersion.v1_6_1,
      ]);
    });

    test('v1_6_1 covers upstream 1.6.1, 1.6.2 and 1.6.3', () {
      expect(BoringAvatarsVersion.v1_6_1.upstreamVersions, <String>[
        '1.6.1',
        '1.6.2',
        '1.6.3',
      ]);
    });

    test('latest is the newest supported version', () {
      expect(BoringAvatarsVersion.latest, BoringAvatarsVersion.v1_6_1);
    });
  });

  group('BoringAvatarsVariant', () {
    test('declares the six upstream variants plus its two aliases', () {
      expect(BoringAvatarsVariant.values, hasLength(8));
      expect(
        BoringAvatarsVariant.values.map((v) => v.upstreamName).toSet(),
        <String>{
          'pixel',
          'bauhaus',
          'ring',
          'beam',
          'sunset',
          'marble',
          'geometric',
          'abstract',
        },
      );
    });

    test('only the six upstream dispatches are renderable', () {
      expect(BoringAvatarsVariant.renderable, <BoringAvatarsVariant>{
        BoringAvatarsVariant.pixel,
        BoringAvatarsVariant.bauhaus,
        BoringAvatarsVariant.ring,
        BoringAvatarsVariant.beam,
        BoringAvatarsVariant.sunset,
        BoringAvatarsVariant.marble,
      });
    });

    test('carries the upstream string, including the reserved word', () {
      expect(BoringAvatarsVariant.abstractStyle.upstreamName, 'abstract');
      expect(BoringAvatarsVariant.marble.upstreamName, 'marble');
    });

    test('drops the variants upstream never dispatched at 1.6.1', () {
      final names = BoringAvatarsVariant.values.map((v) => v.upstreamName);
      for (final gone in <String>['turbulence', 'eye', 'dome', 'moholy']) {
        expect(names, isNot(contains(gone)), reason: gone);
      }
    });
  });

  group('variant resolution mirrors upstream avatar.js', () {
    test('the deprecated names resolve to their replacements', () {
      expect(
        BoringAvatarsVariant.geometric.resolved,
        BoringAvatarsVariant.beam,
      );
      expect(
        BoringAvatarsVariant.abstractStyle.resolved,
        BoringAvatarsVariant.bauhaus,
      );
    });

    test('a renderable variant resolves to itself', () {
      for (final v in BoringAvatarsVariant.renderable) {
        expect(v.resolved, v, reason: '$v');
      }
    });

    test('every variant resolves into the renderable set', () {
      for (final v in BoringAvatarsVariant.values) {
        expect(
          BoringAvatarsVariant.renderable,
          contains(v.resolved),
          reason: '$v left the renderable set',
        );
      }
    });

    test('resolution is idempotent', () {
      for (final v in BoringAvatarsVariant.values) {
        expect(v.resolved.resolved, v.resolved, reason: '$v');
      }
    });
  });

  group('fromUpstreamName degrades exactly as upstream does', () {
    test('accepts every upstream name, aliases included', () {
      for (final v in BoringAvatarsVariant.values) {
        expect(
          BoringAvatarsVariant.fromUpstreamName(v.upstreamName),
          v.resolved,
          reason: v.upstreamName,
        );
      }
    });

    test('an unknown name falls back to marble instead of throwing', () {
      for (final unknown in <String>[
        'turbulence',
        'eye',
        'dome',
        'moholy',
        '',
        'Marble',
        'nonsense',
      ]) {
        expect(
          BoringAvatarsVariant.fromUpstreamName(unknown),
          BoringAvatarsVariant.marble,
          reason: unknown,
        );
      }
    });

    test('an alias is checked before the renderable set — upstream order', () {
      // Upstream tests deprecatedVariants first, so a name that is both an
      // alias and a real variant would resolve as the alias. Neither name
      // currently collides; this pins the ordering so a future one cannot
      // silently take the wrong branch.
      expect(
        BoringAvatarsVariant.fromUpstreamName('geometric'),
        BoringAvatarsVariant.beam,
      );
    });
  });
}
