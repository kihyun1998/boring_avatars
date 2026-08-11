// GENERATED from a Chrome measurement — do not hand-edit. (#95)
//
// **For system colours the measurement is the specification.** CSS Color 4
// §6.2 defines the keywords but leaves every value to the user agent, so
// there is no spec table to generate from the way `named_colours.dart` is
// generated from §6.1. These values are what Chrome **151.0.7922.108**
// resolves on macOS with `colorScheme: light`, taken through
// `getComputedStyle` — which returns exact channel values, with no PNG or
// premultiply rounding in the way — and cross-checked against a rendered
// swatch strip read back pixel by pixel. The two sources agree on every
// opaque entry; `highlight`'s blue channel read one low in the strip, which
// is the premultiply rounding hidden-state #29 describes, and the computed
// style is authoritative.
//
// **Freezing them is the point, and it has a cost worth naming.** A browser's
// system colours vary by OS, theme and user accent — the same keyword is
// *designed* to render differently on different machines, so "the same bytes
// as the browser" is unattainable across environments for these 42 names and
// nothing this package could do would attain it. What invariant 4 demands is
// determinism, and a frozen table is the only deterministic reading. Valid
// **as long as the claim stays "matches Chrome on the reference platform"**;
// forced-colors mode, dark mode and a non-default accent are deliberately not
// modelled.
//
// The 23 deprecated keywords are included because Chrome still accepts them,
// and their measured values are exactly the current-keyword mappings §6.2
// assigns them (ActiveBorder → ButtonBorder, ThreeDFace → ButtonFace, …) —
// measured, all 23, not inferred from the mapping.
//
// Packed `0xAARRGGBB` — unlike `named_colours.dart`'s `0xRRGGBB` — because
// `highlight` carries alpha 153 (`rgba(128, 188, 254, 0.6)`) and a second
// format for one entry would be a trap. `raster_colour4_test.dart` asserts
// the length is exactly 42, so an accidental addition is caught rather than
// absorbed.
library;

/// The CSS system colours, lower case: 19 current (§6.2) and 23 deprecated.
const systemColours = <String, int>{
  // current
  'canvas': 0xFFFFFFFF,
  'canvastext': 0xFF000000,
  'linktext': 0xFF0000EE,
  'visitedtext': 0xFF551A8B,
  'activetext': 0xFFFF0000,
  'buttonface': 0xFFEFEFEF,
  'buttontext': 0xFF000000,
  'buttonborder': 0xFF000000,
  'field': 0xFFFFFFFF,
  'fieldtext': 0xFF000000,
  'highlight': 0x9980BCFE,
  'highlighttext': 0xFF000000,
  'selecteditem': 0xFFB3D7FF,
  'selecteditemtext': 0xFF000000,
  'mark': 0xFFFFFF00,
  'marktext': 0xFF000000,
  'graytext': 0xFF808080,
  'accentcolor': 0xFF0075FF,
  'accentcolortext': 0xFFFFFFFF,
  // deprecated
  'activeborder': 0xFF000000,
  'activecaption': 0xFFFFFFFF,
  'appworkspace': 0xFFFFFFFF,
  'background': 0xFFFFFFFF,
  'buttonhighlight': 0xFFEFEFEF,
  'buttonshadow': 0xFFEFEFEF,
  'captiontext': 0xFF000000,
  'inactiveborder': 0xFF000000,
  'inactivecaption': 0xFFFFFFFF,
  'inactivecaptiontext': 0xFF808080,
  'infobackground': 0xFFFFFFFF,
  'infotext': 0xFF000000,
  'menu': 0xFFFFFFFF,
  'menutext': 0xFF000000,
  'scrollbar': 0xFFFFFFFF,
  'threeddarkshadow': 0xFF000000,
  'threedface': 0xFFEFEFEF,
  'threedhighlight': 0xFF000000,
  'threedlightshadow': 0xFF000000,
  'threedshadow': 0xFF000000,
  'window': 0xFFFFFFFF,
  'windowframe': 0xFF000000,
  'windowtext': 0xFF000000,
};
