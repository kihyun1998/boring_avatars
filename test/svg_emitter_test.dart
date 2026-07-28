import 'dart:convert';
import 'dart:io';

import 'package:boring_avatars/src/scene/scene.dart';
import 'package:boring_avatars/src/svg/emitter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Proves the scene model can hold real upstream output and the emitter can
/// reproduce it byte for byte.
///
/// The test is a **round-trip through the model**: parse a string React
/// actually produced into a scene, emit it, and require the result to be
/// identical. That is not circular — the parser only reads what is there,
/// while the model has to be *expressive enough* to hold it and the emitter has
/// to serialise it the same way. Any of the traps this layer has would break
/// it: a canonical attribute order, a self-closing tag, wrong escaping, a
/// number printed as `4.0`.
///
/// Run over every render in the fixture, so the claim covers all six variants
/// rather than a chosen example.
void main() {
  final svgFixture =
      jsonDecode(File('test/fixtures/v1_6_1/svg.json').readAsStringSync())
          as Map<String, dynamic>;
  final renders = (svgFixture['renders'] as Map<String, dynamic>);

  group('round-trip over every render upstream produced', () {
    test('all of them survive parse → emit unchanged', () {
      var checked = 0;
      for (final entry in renders.entries) {
        if (entry.value is! String) continue; // a recorded throw
        final original = entry.value as String;
        expect(emitSvg(_parse(original)), original, reason: entry.key);
        checked++;
      }
      expect(checked, greaterThan(400), reason: 'the sweep must be wide');
    });

    test('the sweep really covers all six variants', () {
      final variants = renders.keys.map((k) => k.split('|').first).toSet();
      expect(variants, hasLength(6));
    });
  });

  group('the traps this layer has, pinned individually', () {
    test('attribute order is the node\'s, not a canonical one', () {
      // The same element takes different orders at different call sites. If the
      // emitter imposed one, one of these two would come out wrong.
      const ringCircle = SvgNode(
        SvgElement.circle,
        attributes: [
          SvgAttribute('cx', 45),
          SvgAttribute('cy', 45),
          SvgAttribute('r', 23),
          SvgAttribute('fill', '#92A1C6'),
        ],
      );
      const bauhausCircle = SvgNode(
        SvgElement.circle,
        attributes: [
          SvgAttribute('cx', 40),
          SvgAttribute('cy', 40),
          SvgAttribute('fill', '#92A1C6'),
          SvgAttribute('r', 16),
          SvgAttribute('transform', 'translate(1 2)'),
        ],
      );
      expect(
        emitSvg(ringCircle),
        '<circle cx="45" cy="45" r="23" fill="#92A1C6"></circle>',
      );
      expect(
        emitSvg(bauhausCircle),
        '<circle cx="40" cy="40" fill="#92A1C6" r="16" '
        'transform="translate(1 2)"></circle>',
      );
    });

    test('nothing self-closes, even with no children', () {
      expect(emitSvg(const SvgNode(SvgElement.defs)), '<defs></defs>');
      expect(
        emitSvg(
          const SvgNode(
            SvgElement.stop,
            attributes: [SvgAttribute('offset', 1)],
          ),
        ),
        '<stop offset="1"></stop>',
      );
    });

    test('numbers print the JavaScript way, not the Dart way', () {
      expect(
        emitSvg(
          const SvgNode(
            SvgElement.rect,
            attributes: [SvgAttribute('width', 80.0)],
          ),
        ),
        '<rect width="80"></rect>',
        reason: 'Dart would say 80.0',
      );
      expect(
        emitSvg(
          const SvgNode(
            SvgElement.path,
            attributes: [SvgAttribute('transform', 'scale(1.3)')],
          ),
        ),
        '<path transform="scale(1.3)"></path>',
      );
    });

    test('text escaping matches React, apostrophe included', () {
      // Measured: upstream renders the corpus name O'Brien-Smith, Jr. with a
      // numeric reference, not &apos;.
      expect(
        emitSvg(const SvgNode(SvgElement.title, text: "O'Brien-Smith, Jr.")),
        '<title>O&#x27;Brien-Smith, Jr.</title>',
      );
      expect(
        emitSvg(const SvgNode(SvgElement.title, text: 'a & b < c > d "e"')),
        '<title>a &amp; b &lt; c &gt; d &quot;e&quot;</title>',
      );
    });

    test('tabs, newlines and non-ASCII pass through untouched', () {
      for (final raw in <String>[
        'line\nbreak',
        'tab\there',
        '👨‍💻',
        '  padded  ',
      ]) {
        expect(
          emitSvg(SvgNode(SvgElement.title, text: raw)),
          '<title>$raw</title>',
          reason: jsonEncode(raw),
        );
      }
    });

    test('an element name is never hyphenated, though an attribute may be', () {
      // `linearGradient` and `feGaussianBlur` keep their camel case in the
      // output, while `mask-type` and `stop-color` are hyphenated. The split is
      // a list, not a rule — so the caller supplies the emitted spelling.
      expect(
        emitSvg(const SvgNode(SvgElement.linearGradient)),
        '<linearGradient></linearGradient>',
      );
      expect(
        emitSvg(const SvgNode(SvgElement.feGaussianBlur)),
        '<feGaussianBlur></feGaussianBlur>',
      );
      expect(
        emitSvg(
          const SvgNode(
            SvgElement.mask,
            attributes: [SvgAttribute('mask-type', 'alpha')],
          ),
        ),
        '<mask mask-type="alpha"></mask>',
      );
    });
  });

  group('the scene is readable by name, so the rasterizer ignores order', () {
    test('attribute lookup does not depend on position', () {
      const node = SvgNode(
        SvgElement.rect,
        attributes: [
          SvgAttribute('x', 10),
          SvgAttribute('width', 80),
          SvgAttribute('fill', '#FFFFFF'),
        ],
      );
      expect(node.attribute('width'), 80);
      expect(node.attribute('fill'), '#FFFFFF');
      expect(node.attribute('height'), isNull);
    });
  });
}

// ---------------------------------------------------------------------------
// A minimal SVG reader, for the round-trip above only. It is deliberately not
// shipped: the package emits SVG and never consumes it.
//
// It assumes what the fixture demonstrates — no self-closing tags, no comments,
// no CDATA, no processing instructions.
// ---------------------------------------------------------------------------

SvgNode _parse(String source) {
  var pos = 0;

  String unescape(String s) => s
      .replaceAll('&#x27;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');

  SvgNode node() {
    if (source[pos] != '<') throw StateError('expected < at $pos');
    pos++;
    final nameEnd = _indexWhere(source, pos, (c) => c == ' ' || c == '>');
    final tag = source.substring(pos, nameEnd);
    pos = nameEnd;

    final attributes = <SvgAttribute>[];
    while (source[pos] != '>') {
      pos++; // the space
      if (source[pos] == '>') break;
      final eq = source.indexOf('=', pos);
      final attrName = source.substring(pos, eq);
      final valueStart = eq + 2; // skip ="
      final valueEnd = source.indexOf('"', valueStart);
      attributes.add(
        SvgAttribute(
          attrName,
          unescape(source.substring(valueStart, valueEnd)),
        ),
      );
      pos = valueEnd + 1;
    }
    pos++; // the >

    final children = <SvgNode>[];
    String? text;
    while (true) {
      if (source.startsWith('</', pos)) {
        pos = source.indexOf('>', pos) + 1;
        break;
      }
      if (source[pos] == '<') {
        children.add(node());
      } else {
        final next = source.indexOf('<', pos);
        text = unescape(source.substring(pos, next));
        pos = next;
      }
    }

    return SvgNode(
      SvgElement.values.firstWhere((e) => e.tag == tag),
      attributes: attributes,
      children: children,
      text: text,
    );
  }

  return node();
}

int _indexWhere(String s, int from, bool Function(String) test) {
  for (var i = from; i < s.length; i++) {
    if (test(s[i])) return i;
  }
  return s.length;
}
