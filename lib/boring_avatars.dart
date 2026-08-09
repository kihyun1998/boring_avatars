/// A bit-exact Dart port of
/// [boring-avatars](https://github.com/boringdesigners/boring-avatars).
///
/// Given the same name, palette and variant, this package draws the avatar the
/// npm package draws — the same numbers, the same SVG, the same pixels.
///
/// Every *supported* upstream release is reachable at once: pick a
/// [BoringAvatarsVersion] and you get that release's algorithm, with no
/// downgrade and no second dependency. Support starts at upstream 1.6.1, where
/// the hash function reached its current form — see [BoringAvatarsVersion] for
/// the releases each value covers.
library;

/// **Every export names what it carries.** `avatar.dart` also holds the scene
/// dispatch, whose return type is the internal drawing model — exporting the
/// library would promise every element and ordering rule as API. The other two
/// carry a `show` for a reason that is not about them: without one, a
/// re-export added *inside* `variant.dart` or `version.dart` puts whatever it
/// names on this surface without a line of this file changing, and the guard
/// in `api_surface_test.dart` reads this file. Measured — an
/// `export 'scene/scene.dart';` in `version.dart` shipped the whole scene
/// model with the suite green.
export 'src/avatar.dart' show boringAvatarSvg;
export 'src/widget/boring_avatar.dart' show BoringAvatar;
export 'src/variant.dart' show BoringAvatarsVariant;
export 'src/version.dart' show BoringAvatarsVersion;
