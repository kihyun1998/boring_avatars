import 'package:boring_avatars/boring_avatars.dart';
import 'package:flutter_test/flutter_test.dart';

/// The one thing that changes between `v1_6_1` and `v1_7_0`.
///
/// Upstream 1.7.0 replaced `<title>{props.name}</title>` with
/// `{props.title && <title>{props.name}</title>}` in all six components and
/// added `title = false` to `avatar.js`'s destructured defaults. Measured
/// against the pinned reference tree: that diff is 7 files and 14 lines, of
/// which **6 lines are the title and 6 are whitespace inside a JSX expression**
/// (`rx={props.square ?  undefined : SIZE * 2 }` losing two spaces), which
/// reaches no output. So the release's entire observable change is here.
///
/// **The sweep at the bottom is the real assertion.** Checking that `v1_7_0`
/// omits a `<title>` proves the flag is read; checking that the two versions
/// agree on **every other byte** is what proves nothing *else* moved — which is
/// the claim the release is named after, and the one a targeted test cannot
/// make.
void main() {
  const palette = ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'];
  const name = 'Clara Barton';

  String render(
    BoringAvatarsVersion version,
    BoringAvatarsVariant variant, {
    bool? title,
  }) => boringAvatarSvg(
    name: name,
    colors: palette,
    size: 80,
    version: version,
    variant: variant,
    title: title,
  );

  group('v1_6_1 renders the title unconditionally', () {
    for (final variant in BoringAvatarsVariant.renderable) {
      test('${variant.name} emits it with no argument at all', () {
        expect(
          render(BoringAvatarsVersion.v1_6_1, variant),
          contains('<title>Clara Barton</title>'),
        );
      });
    }

    test('asking for it explicitly is allowed — that is what happens', () {
      expect(
        render(
          BoringAvatarsVersion.v1_6_1,
          BoringAvatarsVariant.beam,
          title: true,
        ),
        contains('<title>Clara Barton</title>'),
      );
    });

    test('asking to switch it off throws, naming the argument', () {
      // 1.6.x has no `title` prop — there is no way to switch the element off,
      // and upstream would silently ignore the request (an unknown prop reaches
      // a component that never reads it). Silently ignoring is the one answer
      // that leaves the caller believing something happened. Same reasoning as
      // the `size` ruling, S-4 in the divergence ledger.
      expect(
        () => render(
          BoringAvatarsVersion.v1_6_1,
          BoringAvatarsVariant.beam,
          title: false,
        ),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.name, 'name', 'title')
              .having(
                (e) => e.message.toString(),
                'message',
                contains('1.7.0'),
              ),
        ),
      );
    });
  });

  group('v1_7_0 gates the title behind the prop', () {
    for (final variant in BoringAvatarsVariant.renderable) {
      test('${variant.name} omits it by default, as upstream does', () {
        final svg = render(BoringAvatarsVersion.v1_7_0, variant);
        expect(svg, isNot(contains('<title>')));
        // The side condition: an avatar with no title is still an avatar. A
        // builder that returned an empty document would satisfy the line above.
        expect(svg, startsWith('<svg'));
        expect(svg, contains('<mask'));
      });

      test('${variant.name} emits it when asked', () {
        expect(
          render(BoringAvatarsVersion.v1_7_0, variant, title: true),
          contains('<title>Clara Barton</title>'),
        );
      });
    }

    test('passing false is the default, not an error', () {
      expect(
        render(
          BoringAvatarsVersion.v1_7_0,
          BoringAvatarsVariant.beam,
          title: false,
        ),
        isNot(contains('<title>')),
      );
    });

    test('the title stays the first child when it is emitted', () {
      // Upstream writes it above the mask, and a document that carries the
      // right elements in the wrong order is not byte parity.
      final svg = render(
        BoringAvatarsVersion.v1_7_0,
        BoringAvatarsVariant.pixel,
        title: true,
      );
      expect(svg.indexOf('<title>'), lessThan(svg.indexOf('<mask')));
    });
  });

  group('the title is the only thing that moved', () {
    for (final variant in BoringAvatarsVariant.renderable) {
      test('${variant.name} is byte-identical across the two versions', () {
        // With the title on at both versions the documents must agree
        // completely — same elements, same attributes, same order, same ids.
        // Nothing is normalised here: at 1.6.1 and 1.7.0 every id is a literal
        // in the JSX, so there is nothing generated to erase. (`useId` arrives
        // at 1.8.0, which this selector also covers — see the parity harness
        // for why that does not reach our output.)
        expect(
          render(BoringAvatarsVersion.v1_7_0, variant, title: true),
          render(BoringAvatarsVersion.v1_6_1, variant),
        );
      });

      test('${variant.name} differs from it by exactly the title element', () {
        final withTitle = render(
          BoringAvatarsVersion.v1_7_0,
          variant,
          title: true,
        );
        final without = render(BoringAvatarsVersion.v1_7_0, variant);
        expect(
          withTitle.replaceFirst('<title>Clara Barton</title>', ''),
          without,
        );
      });
    }

    test('a name that needs escaping is escaped the same way', () {
      // The title is the one element carrying character data, so it is the one
      // place an escaping rule can differ — and it only becomes reachable now
      // that the element is optional and therefore separately tested.
      final svg = boringAvatarSvg(
        name: '<Ampersand & Co>',
        colors: palette,
        size: 80,
        version: BoringAvatarsVersion.v1_7_0,
        variant: BoringAvatarsVariant.marble,
        title: true,
      );
      expect(svg, contains('<title>&lt;Ampersand &amp; Co&gt;</title>'));
    });
  });

  group('square and size are untouched by the flag', () {
    test('square still drops the corner radius with the title off', () {
      final svg = boringAvatarSvg(
        name: name,
        colors: palette,
        size: 80,
        version: BoringAvatarsVersion.v1_7_0,
        variant: BoringAvatarsVariant.pixel,
        square: true,
      );
      expect(svg, isNot(contains('rx=')));
      expect(svg, isNot(contains('<title>')));
    });

    test('size still lands on width and height with the title off', () {
      final svg = render(
        BoringAvatarsVersion.v1_7_0,
        BoringAvatarsVariant.ring,
      );
      expect(svg, contains('width="80"'));
      expect(svg, contains('height="80"'));
    });
  });
}
