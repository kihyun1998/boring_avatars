/// An avatar style.
///
/// Six of these are drawn; the remaining two — [geometric] and [abstractStyle]
/// — are names upstream kept working after retiring the variants behind them,
/// and resolve to a drawn one via [resolved].
///
/// Upstream's own dead ends are absent. `turbulence` shipped a component file
/// from 1.2.0 to 1.5.2 that no version's dispatch ever referenced, and `eye`,
/// `dome` and `moholy` had all been dropped before 1.6.1 — the earliest version
/// this package supports.
enum BoringAvatarsVariant {
  /// Blurred organic shapes. Upstream's default.
  marble('marble'),

  /// A face.
  beam('beam'),

  /// An 8×8 mosaic of coloured tiles.
  pixel('pixel'),

  /// Two vertically stacked gradients.
  sunset('sunset'),

  /// Concentric arcs.
  ring('ring'),

  /// Bars, a circle and a rule.
  bauhaus('bauhaus'),

  /// Deprecated upstream — an alias for [beam].
  geometric('geometric'),

  /// Deprecated upstream — an alias for [bauhaus].
  ///
  /// Named `abstractStyle` because `abstract` is a Dart keyword; the upstream
  /// string is carried by [upstreamName].
  abstractStyle('abstract');

  const BoringAvatarsVariant(this.upstreamName);

  /// The string upstream's `variant` prop takes for this style.
  final String upstreamName;

  /// The variants upstream actually dispatches — everything else is an alias.
  static const Set<BoringAvatarsVariant> renderable = {
    pixel,
    bauhaus,
    ring,
    beam,
    sunset,
    marble,
  };

  /// What upstream falls back to when it does not recognise a variant.
  static const BoringAvatarsVariant fallback = marble;

  /// This variant, or the one it aliases.
  ///
  /// Always a member of [renderable].
  BoringAvatarsVariant get resolved => switch (this) {
    geometric => beam,
    abstractStyle => bauhaus,
    _ => this,
  };

  /// Resolves an upstream `variant` string the way upstream's `avatar.js` does.
  ///
  /// Aliases are checked first, then the dispatched set, and anything else
  /// degrades to [fallback] — upstream never throws here, so neither does this.
  /// That order is upstream's, and it matters if a future release ever gives a
  /// name both meanings.
  static BoringAvatarsVariant fromUpstreamName(String name) {
    for (final v in values) {
      if (v.upstreamName == name) return v.resolved;
    }
    return fallback;
  }
}
