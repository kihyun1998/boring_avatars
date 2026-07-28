/// An avatar style.
///
/// Every value here is a variant a caller could actually select in at least one
/// upstream release. Which ones are selectable depends on the
/// [BoringAvatarsVersion] you ask for — see `reachableVariants`.
///
/// `turbulence` is deliberately absent. `avatar-turbulence.js` shipped from
/// upstream 1.2.0 to 1.5.2 with an unchanging blob, but no version's dispatch
/// ever referenced it, so no caller could render it and there is no output to
/// reproduce.
enum BoringAvatarsVariant {
  /// Blurred organic shapes. The default from upstream 1.3.0 onward.
  marble('marble'),

  /// A face — the variant `geometric` became an alias for.
  beam('beam'),

  /// An 8×8 mosaic of coloured tiles.
  pixel('pixel'),

  /// Two vertically stacked gradients.
  sunset('sunset'),

  /// Concentric arcs.
  ring('ring'),

  /// Bars, a circle and a rule — the variant `abstract` became an alias for.
  bauhaus('bauhaus'),

  /// A distinct variant at upstream 1.2.0, unreachable through 1.4.2, and a
  /// deprecated alias for [beam] from 1.5.3 onward.
  geometric('geometric'),

  /// A distinct variant at upstream 1.2.0, unreachable through 1.4.2, and a
  /// deprecated alias for [bauhaus] from 1.5.3 onward.
  ///
  /// Named `abstractStyle` because `abstract` is a Dart keyword; the upstream
  /// string is carried by [upstreamName].
  abstractStyle('abstract'),

  /// Selectable only at upstream 1.2.0. Its file survived to 1.5.2 unreferenced.
  eye('eye'),

  /// Selectable from upstream 1.3.0 to 1.4.2.
  dome('dome'),

  /// Selectable from upstream 1.3.0 to 1.4.2.
  moholy('moholy');

  const BoringAvatarsVariant(this.upstreamName);

  /// The string upstream's `variant` prop takes for this style.
  final String upstreamName;
}
