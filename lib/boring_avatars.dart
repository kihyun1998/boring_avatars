/// A bit-exact Dart port of
/// [boring-avatars](https://github.com/boringdesigners/boring-avatars).
///
/// Given the same name, palette and variant, this package draws the avatar the
/// npm package draws — the same numbers, the same SVG, the same pixels.
///
/// Upstream's whole history is reachable: pick a [BoringAvatarsVersion] and you
/// get that release's algorithm. npm needs a downgrade to render a 1.4.0
/// avatar; this needs a parameter.
library;

export 'src/variant.dart';
export 'src/version.dart';
