/// The dispatch — upstream's `avatar.js`, and the SVG string a caller reaches.
///
/// Two things live here because they are two halves of one seam. Everything
/// below the seam already exists per variant; what this file adds is the choice
/// of *which* one runs, which is exactly what upstream's `Avatar` component is
/// and nothing more.
///
/// [buildAvatarScene] is **not exported** by the package barrel. Its return
/// type is the scene model, and putting that on the public surface would ship
/// every element, attribute and ordering rule as API — a far larger promise
/// than `0.1.0` makes. The barrel exports [boringAvatarSvg] alone.
library;

import 'scene/scene.dart';
import 'svg/emitter.dart';
import 'variant.dart';
import 'variants/bauhaus.dart';
import 'variants/beam.dart';
import 'variants/marble.dart';
import 'variants/pixel.dart';
import 'variants/ring.dart';
import 'variants/sunset.dart';
import 'version.dart';

/// The avatar for [name], as an SVG document.
///
/// The string is what upstream's React component renders for the same
/// arguments — the same elements, the same attributes, in the same order,
/// byte for byte. Hand it to an SVG renderer, write it to a file, or inline it
/// in a web page.
///
/// **One exception, and it is deliberate.** With
/// [BoringAvatarsVariant.sunset], a [name] containing `'`, `"`, `(`, `)`, `\`
/// or a control character produces a gradient reference that differs from
/// upstream's. Upstream builds that reference out of the name without escaping
/// it, so the result is not a valid CSS url token and **the browser paints
/// nothing** — a blank avatar, reproduced in Chrome. This package
/// percent-encodes the reference so the avatar renders. Every other name, and
/// every other variant, is byte-identical.
///
/// ```dart
/// final svg = boringAvatarSvg(
///   name: 'Clara Barton',
///   colors: const ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'],
///   size: 80,
///   version: BoringAvatarsVersion.v1_6_1,
///   variant: BoringAvatarsVariant.beam,
/// );
/// ```
///
/// **Flutter cannot draw an SVG on its own.** Rendering this string in a
/// Flutter app needs a third-party package such as `flutter_svg`, and the
/// pixels you get are then that package's, not this one's. This package's
/// "same bytes everywhere" guarantee covers what it produces — this document —
/// and will cover its own rasterizer when that ships; it says nothing about a
/// renderer it does not own.
///
/// ## The arguments are all yours
///
/// Nothing here has a palette, a size or an upstream release baked in.
///
/// * [name] is the only input the drawing is derived from. The same name always
///   yields the same avatar.
/// * [colors] is your palette, used exactly as upstream uses it. An **empty**
///   palette is not an error in general: five variants degrade the way upstream
///   does and render an avatar with colours missing, while
///   [BoringAvatarsVariant.beam] throws an [ArgumentError] — because upstream
///   throws there too, and a version of `beam` that degraded would be an image
///   upstream has never produced.
/// * [size] lands on the `<svg>` element's `width` and `height` and reaches
///   nothing else — the drawing's own coordinate space is a per-variant
///   constant. Pass a [num] for `width="80"` or a [String] for anything CSS
///   accepts, such as `'100%'`. Anything else is an [ArgumentError]: upstream
///   would quietly coerce it, and this package would rather tell you. It has
///   no default on purpose — what an unspecified size should mean is
///   upstream's own moving target, and this package would rather not answer it
///   for you.
/// * [version] names the upstream release to reproduce, and has **no default**.
///   That is deliberate: a default of "newest" would silently redraw every
///   avatar in your app the day you upgraded this package. Pass
///   [BoringAvatarsVersion.latest] if that is genuinely what you want.
/// * [variant] is the style, defaulting to [BoringAvatarsVariant.marble] as
///   upstream does. The two deprecated names resolve to their replacements.
/// * [square] removes the mask's corner radius, giving a square avatar instead
///   of a round one.
///
/// Throws an [ArgumentError] if [size] is neither a [num] nor a [String], and
/// for [BoringAvatarsVariant.beam] with an empty [colors].
String boringAvatarSvg({
  required String name,
  required List<String> colors,
  required Object size,
  required BoringAvatarsVersion version,
  BoringAvatarsVariant variant = BoringAvatarsVariant.marble,
  bool square = false,
}) => emitSvg(
  buildAvatarScene(
    name: name,
    colors: colors,
    size: size,
    version: version,
    variant: variant,
    square: square,
  ),
);

/// Picks the scene [version] and [variant] describe. Internal — see the library
/// doc for why this is not exported.
///
/// This is upstream's `avatar.js` and carries its two rules, both of them in
/// [BoringAvatarsVariant] rather than restated here: a deprecated name resolves
/// to its replacement, and a name upstream does not recognise degrades to
/// `marble` instead of throwing.
///
/// **Nothing here has a default**, including the two that do on the public
/// function. Upstream's defaults are part of its *API*, so they belong on the
/// surface a caller meets; repeating them here gave [boringAvatarSvg] — the
/// only caller, which always passes both — a second copy that nothing could
/// read. The mutation that changed it survived the whole suite, which is what
/// unreachable code looks like from the outside (`lessons.md`, Step 3).
SvgNode buildAvatarScene({
  required String name,
  required List<String> colors,
  required Object size,
  required BoringAvatarsVersion version,
  required BoringAvatarsVariant variant,
  required bool square,
}) {
  // **Upstream does not reject this, and throwing anyway is a ruling** — S-4
  // in the divergence ledger, decided by the user on 2026-08-08. Measured at
  // 1.6.1: `true`/`false`/`null` make React drop `width` and `height`
  // entirely, `[80]` coerces to `width="80"`, and `{}` renders
  // `width="[object Object]"`. Reproducing that means implementing JS's
  // `String()` coercion and React's attribute-dropping rules in order to emit
  // a value React itself warns the author about. Every input a caller can
  // plausibly mean — any number, any CSS length string — stays byte-identical.
  //
  // The scene's own check is an `assert`, which is compiled out of a release
  // build — so the value would otherwise reach `SvgAttribute.formattedValue`
  // and fail there as a cast, naming an internal type at a caller who passed a
  // `bool`. A public seam rejects, and says which argument.
  if (size is! num && size is! String) {
    throw ArgumentError.value(
      size,
      'size',
      'must be a num (rendered as width="80") or a String (width="100%")',
    );
  }

  return switch (version) {
    // One arm today. The switch is exhaustive on purpose: the release that adds
    // the second selector value will not compile until it is dispatched, which
    // is the failure mode a `default` arm would turn into a silently wrong
    // avatar in a caller's app.
    BoringAvatarsVersion.v1_6_1 => switch (variant.resolved) {
      BoringAvatarsVariant.marble => buildMarbleScene(
        name: name,
        colors: colors,
        size: size,
        square: square,
      ),
      BoringAvatarsVariant.beam => buildBeamScene(
        name: name,
        colors: colors,
        size: size,
        square: square,
      ),
      BoringAvatarsVariant.pixel => buildPixelScene(
        name: name,
        colors: colors,
        size: size,
        square: square,
      ),
      BoringAvatarsVariant.sunset => buildSunsetScene(
        name: name,
        colors: colors,
        size: size,
        square: square,
      ),
      BoringAvatarsVariant.ring => buildRingScene(
        name: name,
        colors: colors,
        size: size,
        square: square,
      ),
      BoringAvatarsVariant.bauhaus => buildBauhausScene(
        name: name,
        colors: colors,
        size: size,
        square: square,
      ),
      // Unreachable: `resolved` is documented and tested to land in
      // `BoringAvatarsVariant.renderable`, which these two are not in. The arm
      // exists so the switch stays exhaustive over the enum — a new variant
      // value then fails to compile here rather than falling through to a
      // default and drawing the wrong thing. It is dead code by construction,
      // not an unchecked guard: `api_surface_test.dart` pins the contract that
      // makes it dead.
      BoringAvatarsVariant.geometric ||
      BoringAvatarsVariant.abstractStyle => throw StateError(
        '$variant resolved to itself — BoringAvatarsVariant.resolved is broken',
      ),
    },
  };
}
