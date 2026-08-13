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
  /// element, and there is no way to switch it off. Passing `title: false`
  /// with this value is an [ArgumentError] rather than a silent no-op. The
  /// prop arrives in [v1_7_0].
  v1_6_1(['1.6.1', '1.6.2', '1.6.3']),

  /// Upstream 1.7.0, 1.8.0, 1.9.0 and 1.10.0.
  ///
  /// The release where `<title>` became optional: upstream added a `title`
  /// prop, **defaulting to off**, and this value defaults to off with it. That
  /// is the only difference from [v1_6_1] — measured against the reference
  /// tree, the 1.6.3 → 1.7.0 diff touches 7 files and 14 lines, of which 6 are
  /// the title and 6 are whitespace inside a JSX expression that reaches no
  /// output. With `title: true` the two versions render byte-identical
  /// documents.
  ///
  /// **Why four releases share one value.** 1.8.0 renamed the mask id from a
  /// literal to React's `useId()`, and 1.8.0–1.10.0 are one unchanged source
  /// tree. A `useId()` value is not a property of the avatar — it depends on
  /// where the component sits in the render tree, so the same avatar comes out
  /// `:R0:` alone and `:R3:` as a third child. It is an internal reference that
  /// names nothing a reader sees, and this package emits the literal upstream
  /// used before and after it. Everything a caller can observe about the
  /// drawing is identical across the four.
  ///
  /// Two of them, 1.8.0 and 1.9.0, were **never runnable**: their npm tarballs
  /// contain no JavaScript at all (`main` points at a `build/index.js` that is
  /// not in the package — verified by downloading both). They are covered here
  /// because their source is 1.10.0's, byte for byte.
  v1_7_0(['1.7.0', '1.8.0', '1.9.0', '1.10.0']);

  const BoringAvatarsVersion(this.upstreamVersions);

  /// Every upstream release this value reproduces exactly.
  final List<String> upstreamVersions;

  /// The newest supported release.
  ///
  /// **This value moves, and it has already moved once.** It was [v1_6_1] in
  /// `0.1.0` and is [v1_7_0] as of `0.2.0`, so an avatar rendered with it can
  /// change when you upgrade this package — anyone who passed `latest` in
  /// `0.1.0` and relied on the `<title>` element loses it here, because
  /// `v1_7_0` defaults the title off as upstream does. `0.3.0` will redraw
  /// every `pixel` avatar the same way.
  ///
  /// That is why nothing defaults to it: `boringAvatarSvg` requires a
  /// `version`, and passing `latest` is a deliberate choice to track upstream's
  /// newest rather than to pin an avatar. Name a value to pin one.
  static const BoringAvatarsVersion latest = v1_7_0;
}
