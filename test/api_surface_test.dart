import 'dart:io';

import 'package:boring_avatars/boring_avatars.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the barrel', () {
    test('exports four names and nothing else', () {
      // A test that only *uses* the surface cannot notice the scene model
      // leaking out beside it, and once published an accidental export is as
      // irreversible as a deliberate one. `show` is what keeps the dispatch —
      // which returns that model — off the public API.
      final barrel = File('lib/boring_avatars.dart').readAsStringSync();
      final exports = RegExp(
        r'^export .*;',
        multiLine: true,
      ).allMatches(barrel).map((m) => m.group(0)!).toList();
      expect(exports, <String>[
        "export 'src/avatar.dart' show boringAvatarSvg;",
        "export 'src/widget/boring_avatar.dart' show BoringAvatar;",
        "export 'src/variant.dart' show BoringAvatarsVariant;",
        "export 'src/version.dart' show BoringAvatarsVersion;",
      ]);
    });

    test('every export carries a show clause', () {
      // The assertion above pins three export *statements*; this pins the
      // property that makes them a complete list of *names*. Without a `show`,
      // a re-export added inside one of those libraries reaches the barrel
      // with this file unchanged — measured, an `export 'scene/scene.dart';`
      // in `version.dart` put `SvgNode`, `SvgAttribute`, `SvgElement` and
      // `escapeSvgText` on the public surface and the whole suite stayed
      // green. Once published, an accidental export is as irreversible as a
      // deliberate one.
      final barrel = File('lib/boring_avatars.dart').readAsStringSync();
      for (final line in RegExp(
        r'^export .*;',
        multiLine: true,
      ).allMatches(barrel).map((m) => m.group(0)!)) {
        expect(line, contains(' show '), reason: line);
      }
    });

    test('the SVG function takes no default version', () {
      // Not a style check. A default of `latest` would move the day a release
      // adds a selector value — `0.3.0` changes `pixel`'s colours — silently
      // redrawing every avatar in an app that upgraded. **Decided by the user
      // on 2026-08-08**, shown the three options and what each costs; theirs
      // to reverse, and not reversible by a passing argument alone.
      //
      // Asserted against the source because Dart offers no way to ask a
      // function whether a parameter has a default.
      final source = File('lib/src/avatar.dart').readAsStringSync();
      expect(
        source,
        contains('required BoringAvatarsVersion version,'),
        reason: 'version must stay required',
      );
      expect(
        source,
        isNot(contains('BoringAvatarsVersion version =')),
        reason: 'a default version would move under callers on upgrade',
      );
      // `size` is the same class of promise, recorded in theflow.md: the
      // 2.0.3/2.0.4 default-size change stays out of the version state only
      // because the caller always supplies one.
      expect(source, contains('required Object size,'));
    });

    test('and neither does the widget', () {
      // **The guard above reads `avatar.dart` and only that**, so a
      // `BoringAvatar({BoringAvatarsVersion version = ...})` passed the whole
      // suite until #80 — the 2026-08-08 ruling was unenforced the moment a
      // second public surface appeared. Measured before this test existed.
      final source = File(
        'lib/src/widget/boring_avatar.dart',
      ).readAsStringSync();
      expect(
        source,
        contains('required this.version,'),
        reason: 'version must stay required on the widget too',
      );
      expect(
        source,
        isNot(contains('this.version =')),
        reason: 'a default version would move under callers on upgrade',
      );
      // `size` is a `double` here rather than the SVG surface's num-or-String:
      // `'100%'` has no basis before layout, and a size read from constraints
      // could not be memoised on the widget's fields.
      expect(source, contains('required this.size,'));
      expect(source, contains('final double size;'));
    });
  });

  group('BoringAvatarsVersion', () {
    test('declares only the upstream versions this release supports', () {
      expect(BoringAvatarsVersion.values, <BoringAvatarsVersion>[
        BoringAvatarsVersion.v1_6_1,
        BoringAvatarsVersion.v1_7_0,
      ]);
    });

    test('v1_6_1 covers upstream 1.6.1, 1.6.2 and 1.6.3', () {
      expect(BoringAvatarsVersion.v1_6_1.upstreamVersions, <String>[
        '1.6.1',
        '1.6.2',
        '1.6.3',
      ]);
    });

    test('v1_7_0 covers upstream 1.7.0 through 1.10.0', () {
      expect(BoringAvatarsVersion.v1_7_0.upstreamVersions, <String>[
        '1.7.0',
        '1.8.0',
        '1.9.0',
        '1.10.0',
      ]);
    });

    test('a shipped selector never loses or gains a release', () {
      // `v1_6_1` is published. Its list is a contract in the same way its
      // pixels are: an app pinned to it and told it reproduces 1.6.3 must keep
      // being told that. The literal above already pins it — this states *why*
      // the literal may not be edited, since the reason is invisible from the
      // assertion and a future release will be tempted to "tidy" it.
      //
      // The general shape: every release appears under exactly one selector,
      // so a version cannot be quietly moved from one to another.
      final claimed = [
        for (final v in BoringAvatarsVersion.values) ...v.upstreamVersions,
      ];
      expect(claimed.toSet(), hasLength(claimed.length));
    });

    test('latest is the newest supported version', () {
      // Both assertions, because they fail on different things. The literal
      // catches `latest` moving to a value this release does not ship; the
      // positional one catches it *failing to move* when a value is added —
      // which nothing else does. The dispatch's exhaustive switch forces a new
      // selector to be rendered, but `latest` is a hand-maintained constant
      // and would sit on the old value with the suite green.
      expect(BoringAvatarsVersion.latest, BoringAvatarsVersion.v1_7_0);
      expect(BoringAvatarsVersion.latest, BoringAvatarsVersion.values.last);
    });

    test('title has no bool default, because the versions disagree', () {
      // `v1_6_1` renders `<title>` always; `v1_7_0` defaults it off, as
      // upstream does. Either literal default would therefore be wrong for one
      // of the two selectors, and wrong *silently* — the document would differ
      // by an element nobody asked about. `null` means "you did not ask" and
      // each version answers it its own way.
      //
      // Source text again: Dart cannot be asked at runtime whether a parameter
      // has a default.
      final source = File('lib/src/avatar.dart').readAsStringSync();
      expect(
        source,
        contains('bool? title,'),
        reason: 'title must stay nullable',
      );
      expect(
        source,
        isNot(contains('bool title = ')),
        reason: 'a bool default is wrong for one of the two selectors',
      );
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

    test('no upstream name carries two meanings — what makes one scan safe', () {
      // **This replaces a test that could not fail.** It was named "an alias is
      // checked before the renderable set — upstream order" and asserted
      // `fromUpstreamName('geometric') == beam`, which is true under *any*
      // iteration order, because `upstreamName` is unique: measured in #59's
      // completeness pass, `for (final v in values.reversed)` left the whole
      // suite green. It pinned an ordering the code does not implement.
      //
      // Uniqueness is the real condition. Upstream checks its alias map first,
      // so a name in both sets resolves as the alias; our single scan meets
      // the renderables first and would answer the other way. Nothing can
      // observe that while this holds — and the day it stops, this fails and
      // `fromUpstreamName` has to become two stages.
      final names = BoringAvatarsVariant.values
          .map((v) => v.upstreamName)
          .toList();
      expect(names.toSet(), hasLength(names.length));

      final aliases = BoringAvatarsVariant.values
          .where((v) => !BoringAvatarsVariant.renderable.contains(v))
          .map((v) => v.upstreamName)
          .toSet();
      final renderable = BoringAvatarsVariant.renderable
          .map((v) => v.upstreamName)
          .toSet();
      expect(
        aliases.intersection(renderable),
        isEmpty,
        reason: 'a name in both sets makes the scan order observable',
      );
      expect(aliases, hasLength(2));
    });
  });
}
