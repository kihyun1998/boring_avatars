// Enum values are named after upstream releases, which are dotted numbers.
// ignore_for_file: constant_identifier_names

/// An upstream `boring-avatars` release whose output this package reproduces.
///
/// One value is added per release of this package, and a value's output is
/// frozen once shipped — selecting one always yields the same avatar regardless
/// of which version of this package you are on.
///
/// **Upstream releases share a value when a caller gets the same thing out of
/// them** — not when their source happens to match. Several of upstream's
/// releases changed only how the component was written, and one changed the
/// source not at all across three releases; those collapse. Each value lists
/// every release it reproduces in [upstreamVersions].
///
/// One upstream release is deliberately absent: `1.11.0` writes its own props
/// onto the `<svg>` element (`colors="…" name="…"`), which no other release
/// does. Reproducing it would mean reproducing that. Upstream fixed it in
/// `1.11.1`, which is covered.
///
/// These track upstream's **git tags**, not its npm versions — the two
/// disagree. npm `1.2.1`, for instance, republished 0.1.4-era code.
enum BoringAvatarsVersion {
  /// Upstream 1.6.1, 1.6.2 and 1.6.3.
  ///
  /// The release where upstream replaced its `getNumber` character-code sum
  /// with the 32-bit `hashCode`, so it is the earliest version whose avatars
  /// match anything still in wide use. Earlier releases draw differently and
  /// are out of scope.
  ///
  /// Note that 1.6.x has no `title` prop — it always renders a `<title>`
  /// element. The prop arrives in 1.7.0.
  v1_6_1(['1.6.1', '1.6.2', '1.6.3']);

  const BoringAvatarsVersion(this.upstreamVersions);

  /// Every upstream release this value reproduces exactly.
  final List<String> upstreamVersions;

  /// The newest supported release — what you get unless you ask for an older
  /// one.
  static const BoringAvatarsVersion latest = v1_6_1;
}
