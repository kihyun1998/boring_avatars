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

export 'src/variant.dart';
export 'src/version.dart';
