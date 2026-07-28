/// The backend-neutral description of what an avatar draws.
///
/// Both the SVG emitter and the rasterizer read this, so the geometry exists in
/// exactly one place. Two emitters deriving it independently is the divergence
/// seed this seam exists to prevent.
///
/// ## Why attributes are an ordered list and not named fields
///
/// Byte parity with upstream means reproducing the attribute order React emits,
/// and that order is **the order the JSX author wrote the props at each call
/// site** — it is not a property of the element type. Measured across the
/// fixture, one element takes several different orders:
///
/// ```
/// circle   cx cy fill r transform      (bauhaus)
///          cx cy r fill                (ring)
/// rect     x y width height rx stroke fill        (beam's eyes)
///          x y width height transform fill rx     (beam's wrapper)
/// path     d fill  ·  fill d  ·  d stroke fill stroke-linecap
/// ```
///
/// So a node cannot render named fields in a canonical order. It carries the
/// attributes in the order its call site supplies them, and the rasterizer
/// looks them up by name — which it can do regardless of order.
library;

import '../js/js_number.dart';

/// The SVG elements the six variants use, and nothing else.
///
/// Enumerated from the rendered fixture rather than from the components, since
/// what matters is the element name that actually reaches the output.
enum SvgElement {
  svg,
  title,
  mask,
  g,
  rect,
  circle,
  line,
  path,
  defs,
  linearGradient,
  stop,
  filter,
  feFlood,
  feBlend,
  feGaussianBlur;

  /// The tag as it appears in the output. Element names are *not* hyphenated
  /// the way some attribute names are — `linearGradient` and `feGaussianBlur`
  /// keep their camel case.
  String get tag => name;
}

/// One attribute, carrying its position.
///
/// [value] is a `num` or a `String`. Numbers are formatted with [jsNum] at
/// emit time, so an integral double prints as `4` and not `4.0` — the same
/// rule that governs every number upstream concatenates into a string.
class SvgAttribute {
  const SvgAttribute(this.name, this.value)
    : assert(
        value is num || value is String,
        'an attribute is a number or a string',
      );

  /// The attribute name **as it appears in the output**.
  ///
  /// React lowercases and hyphenates some prop names and leaves others alone,
  /// and the split is a list rather than a rule: `maskType` becomes
  /// `mask-type` while `maskUnits` stays as it is. Callers pass the emitted
  /// spelling so the translation is never re-derived.
  final String name;

  /// A `num` or a `String`.
  final Object value;

  /// This attribute's value as it will be serialised.
  String get formattedValue =>
      value is num ? jsNum(value as num) : escapeSvgText(value as String);
}

/// A node in the drawing.
///
/// Either a container with [children], or a leaf. `<title>` is the only
/// element that carries [text].
class SvgNode {
  const SvgNode(
    this.element, {
    this.attributes = const [],
    this.children = const [],
    this.text,
  });

  final SvgElement element;

  /// In the order the call site wrote them — see the library doc.
  final List<SvgAttribute> attributes;

  final List<SvgNode> children;

  /// Character data, for `<title>`.
  final String? text;

  /// The value of [name], or `null` if this node does not carry it.
  ///
  /// This is how the rasterizer reads a node: by name, so the ordering that
  /// the emitter depends on is invisible to it.
  Object? attribute(String name) {
    for (final a in attributes) {
      if (a.name == name) return a.value;
    }
    return null;
  }
}

/// Escapes text the way React's `escapeTextForBrowser` does.
///
/// Five characters, and the apostrophe is the surprising one: it becomes the
/// numeric reference `&#x27;` rather than `&apos;`. Measured — the corpus name
/// `O'Brien-Smith, Jr.` renders as `O&#x27;Brien-Smith, Jr.` upstream.
///
/// Tabs and newlines are **not** escaped, and non-ASCII passes through
/// untouched, so an emoji stays an emoji.
String escapeSvgText(String value) {
  if (!value.contains(RegExp('[&><"\']'))) return value;
  final out = StringBuffer();
  for (final unit in value.codeUnits) {
    out.write(switch (unit) {
      0x26 => '&amp;',
      0x3E => '&gt;',
      0x3C => '&lt;',
      0x22 => '&quot;',
      0x27 => '&#x27;',
      _ => String.fromCharCode(unit),
    });
  }
  return out.toString();
}
