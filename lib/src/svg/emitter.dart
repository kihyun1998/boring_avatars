/// Serialises a scene to the exact bytes upstream's React render produces.
///
/// This is the layer-2 parity surface. `test/fixtures/<version>/svg.json` holds
/// what `renderToStaticMarkup` actually emitted, and the bar is byte equality —
/// so the details below are not stylistic choices, they are measurements.
library;

import '../scene/scene.dart';

/// Renders [root] as `renderToStaticMarkup` would.
///
/// Three properties of that output are easy to get wrong and invisible on
/// screen when you do:
///
/// * **No self-closing tags.** Every element comes out as an open/close pair,
///   `<rect …></rect>`, never `<rect … />`. Across the 480 renders in the
///   fixture, `/>` appears zero times.
/// * **No whitespace between elements.** React emits no indentation or
///   newlines of its own.
/// * **Attribute order is the node's**, not this function's — see
///   `SvgNode.attributes`.
String emitSvg(SvgNode root) {
  final out = StringBuffer();
  _write(root, out);
  return out.toString();
}

void _write(SvgNode node, StringBuffer out) {
  out
    ..write('<')
    ..write(node.element.tag);
  for (final a in node.attributes) {
    out
      ..write(' ')
      ..write(a.name)
      ..write('="')
      ..write(a.formattedValue)
      ..write('"');
  }
  out.write('>');

  if (node.text != null) out.write(escapeSvgText(node.text!));
  for (final child in node.children) {
    _write(child, out);
  }

  out
    ..write('</')
    ..write(node.element.tag)
    ..write('>');
}
