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
/// * [title] decides whether the document carries a `<title>` element — the
///   accessible name a screen reader announces. **It means different things at
///   different versions, because upstream changed it.** See below.
///
/// ## `title`, and why it is nullable
///
/// [BoringAvatarsVersion.v1_6_1] renders `<title>` unconditionally: upstream
/// 1.6.x has no such prop and offers no way to switch the element off.
/// [BoringAvatarsVersion.v1_7_0] added the prop and **defaults it off**, and
/// this package defaults with it.
///
/// So the argument's default cannot be a `bool`: `true` would be wrong for one
/// version and `false` for the other. `null` means "you did not ask", and each
/// version answers it the way upstream does.
///
/// Asking for something a version cannot do is an [ArgumentError] rather than a
/// silent no-op — `title: false` with `v1_6_1` throws. Upstream would ignore
/// it (an unknown prop reaches a component that never reads it) and leave you
/// believing the element was gone. Same reasoning as the [size] ruling.
///
/// Throws an [ArgumentError] if [size] is neither a [num] nor a [String], if
/// [title] is `false` at a version with no `title` prop, and for
/// [BoringAvatarsVariant.beam] with an empty [colors].
String boringAvatarSvg({
  required String name,
  required List<String> colors,
  required Object size,
  required BoringAvatarsVersion version,
  BoringAvatarsVariant variant = BoringAvatarsVariant.marble,
  bool square = false,
  bool? title,
}) => emitSvg(
  buildAvatarScene(
    name: name,
    colors: colors,
    size: size,
    version: version,
    variant: variant,
    square: square,
    title: title,
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
  required bool? title,
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

  // **The first of the two questions a version answers.** Upstream 1.7.0 put
  // `<title>` behind a prop defaulting to off; 1.6.x emits it unconditionally
  // and has no prop at all. Every later release keeps 1.7.0's answer —
  // `title = false` sits in the destructuring at every tag through master.
  //
  // The switch is exhaustive on purpose, and it is exhaustive over *this*
  // question rather than over the whole dispatch: a release that adds a
  // selector will not compile until it says what its `<title>` does.
  final emitsTitle = switch (version) {
    BoringAvatarsVersion.v1_6_1 => switch (title) {
      // `true` is what happens anyway, so asking for it is not an error.
      // `false` cannot be honoured, and a silent no-op would leave the caller
      // believing the element was gone. Upstream would ignore it: an unknown
      // prop reaches a component that never reads it.
      null || true => true,
      false => throw ArgumentError.value(
        title,
        'title',
        'upstream 1.6.x renders <title> unconditionally and has no title prop '
            '— it cannot be switched off. The prop arrives in 1.7.0, so pass '
            'BoringAvatarsVersion.v1_7_0 to control it',
      ),
    },
    // Upstream's own default, from `avatar.js`'s `title = false`.
    BoringAvatarsVersion.v1_7_0 ||
    BoringAvatarsVersion.v1_10_1 => title ?? false,
  };

  // **The second question a new selector has to answer, and the reason it is a
  // type rather than a comment.** Flattening the dispatch bought one copy of
  // the six-arm switch instead of one per version — but it also narrowed the
  // guard `avatar.js`'s port used to have: before #43, adding a selector made
  // the *whole dispatch* non-exhaustive, so nobody could add a version without
  // looking at every variant. With only `emitsTitle` above, a version that
  // draws differently would compile and silently render its neighbour's
  // picture. `0.3.0` is exactly that version — it moves `pixel`'s colour index.
  //
  // So the drawing is named. A new selector must say which drawing it uses; a
  // selector that draws differently must add a value here, and adding one makes
  // the switch below non-exhaustive — which is the original guard, restored
  // without the duplication that paid for it.
  final drawing = switch (version) {
    // The first two selectors draw the same picture. That is `0.2.0`'s entire
    // claim, and it is measured: with `title: true` the two render
    // byte-identical documents for all six variants (`title_test.dart`).
    BoringAvatarsVersion.v1_6_1 ||
    BoringAvatarsVersion.v1_7_0 => _Drawing.v1_6_1,
    // 1.10.1 moved `pixel`'s colour index — the only drawing change in the
    // whole supported range. The other five variants are untouched, which is
    // `0.3.0`'s measured claim the way the sentence above is `0.2.0`'s.
    BoringAvatarsVersion.v1_10_1 => _Drawing.v1_10_1,
  };

  // **What each drawing decides, spelled per variant.** Only `pixel` varies
  // today; the switch over `drawing` is *here*, at the one knob that moves,
  // so a third `_Drawing` value fails to compile at exactly the decision it
  // has to take. A future drawing that moves another variant adds its own
  // switch at that variant's knob the same way.
  final pixelColourIndex = switch (drawing) {
    _Drawing.v1_6_1 => PixelColourIndex.loopIndex,
    _Drawing.v1_10_1 => PixelColourIndex.loopIndexPlusOne,
  };

  return switch (variant.resolved) {
    BoringAvatarsVariant.marble => buildMarbleScene(
      name: name,
      colors: colors,
      size: size,
      square: square,
      title: emitsTitle,
    ),
    BoringAvatarsVariant.beam => buildBeamScene(
      name: name,
      colors: colors,
      size: size,
      square: square,
      title: emitsTitle,
    ),
    BoringAvatarsVariant.pixel => buildPixelScene(
      name: name,
      colors: colors,
      size: size,
      square: square,
      title: emitsTitle,
      colourIndex: pixelColourIndex,
    ),
    BoringAvatarsVariant.sunset => buildSunsetScene(
      name: name,
      colors: colors,
      size: size,
      square: square,
      title: emitsTitle,
    ),
    BoringAvatarsVariant.ring => buildRingScene(
      name: name,
      colors: colors,
      size: size,
      square: square,
      title: emitsTitle,
    ),
    BoringAvatarsVariant.bauhaus => buildBauhausScene(
      name: name,
      colors: colors,
      size: size,
      square: square,
      title: emitsTitle,
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
  };
}

/// Which picture a selector draws.
///
/// Two values as of `0.3.0`: the 1.6.1 drawing (upstream 1.6.1 – 1.10.0) and
/// the 1.10.1 drawing, which differs from it in exactly one place — `pixel`'s
/// colour index. The type exists so that a selector which draws differently
/// cannot compile until it says which picture it draws: adding a value here
/// breaks every switch over the drawing, and those switches sit at the knobs
/// that vary. A comment saying "remember to split this" would not.
enum _Drawing { v1_6_1, v1_10_1 }
