// Enum values are named after upstream releases, which are dotted numbers.
// ignore_for_file: constant_identifier_names

import 'variant.dart';

/// Which roster of variants an upstream release dispatches.
///
/// Upstream's `avatar.js` rewrote its dispatch three times before settling.
/// Several [BoringAvatarsVersion] states share a roster, so this is factored
/// out rather than repeated per state.
enum VariantEra {
  /// Upstream 1.2.0 — `geometric` is the default and a real variant.
  original,

  /// Upstream 1.3.0–1.3.1 — `dome`, `moholy` and `ring` arrive; `geometric`
  /// and `abstract` become unreachable without yet being aliases.
  reshuffled,

  /// Upstream 1.4.0–1.4.2 — `bauhaus`, `pixel` and `sunset` arrive alongside
  /// `dome`.
  expanded,

  /// Upstream 1.5.3 onward — the six current variants, plus the deprecated
  /// aliases `geometric` → `beam` and `abstract` → `bauhaus`.
  modern,
}

/// A distinct upstream `boring-avatars` algorithm state.
///
/// Upstream publishes 28 git tags from 1.2.0, but most change nothing that
/// affects a drawn avatar. They collapse to the 17 states below; each value
/// lists every upstream release it reproduces exactly.
///
/// The states are additive: a value's output is frozen once released, so
/// selecting one always yields the same avatar regardless of this package's
/// own version.
///
/// Note that these track upstream's **git tags**, not its npm versions. The two
/// disagree — npm `1.2.1`, for instance, republished 0.1.4-era code and does not
/// match [v1_2_0].
enum BoringAvatarsVersion {
  /// Upstream 1.2.0. `getNumber` hashing; `geometric` is the default.
  v1_2_0(['1.2.0'], VariantEra.original),

  /// Upstream 1.3.0, 1.3.1.
  v1_3_0(['1.3.0', '1.3.1'], VariantEra.reshuffled),

  /// Upstream 1.4.0 — `bauhaus`, `pixel` and `sunset` arrive.
  v1_4_0(['1.4.0'], VariantEra.expanded),

  /// Upstream 1.4.1.
  v1_4_1(['1.4.1'], VariantEra.expanded),

  /// Upstream 1.4.2.
  v1_4_2(['1.4.2'], VariantEra.expanded),

  /// Upstream 1.5.3, 1.5.4, 1.5.5 — the six current variants settle.
  v1_5_3(['1.5.3', '1.5.4', '1.5.5'], VariantEra.modern),

  /// Upstream 1.5.6. Reverted by 1.6.0; kept because it was released.
  v1_5_6(['1.5.6'], VariantEra.modern),

  /// Upstream 1.5.7, 1.5.8. Reverted by 1.6.0; kept because it was released.
  v1_5_7(['1.5.7', '1.5.8'], VariantEra.modern),

  /// Upstream 1.6.0 — restores [v1_5_3]'s components byte for byte.
  v1_6_0(['1.6.0'], VariantEra.modern),

  /// Upstream 1.6.1, 1.6.2, 1.6.3 — `hashCode` replaces `getNumber`. Every
  /// name draws a different avatar from here on.
  v1_6_1(['1.6.1', '1.6.2', '1.6.3'], VariantEra.modern),

  /// Upstream 1.7.0. The last release usable on React 17.
  v1_7_0(['1.7.0'], VariantEra.modern),

  /// Upstream 1.8.0, 1.9.0, 1.10.0. (1.8.0 and 1.9.0 shipped no JavaScript to
  /// npm; 1.10.0 published the same code.)
  v1_8_0(['1.8.0', '1.9.0', '1.10.0'], VariantEra.modern),

  /// Upstream 1.10.1 — `pixel`'s tile index is fixed from `% i` to `% (i + 1)`.
  v1_10_1(['1.10.1'], VariantEra.modern),

  /// Upstream 1.10.2 — `marble` changes.
  v1_10_2(['1.10.2'], VariantEra.modern),

  /// Upstream 1.11.0.
  v1_11_0(['1.11.0'], VariantEra.modern),

  /// Upstream 1.11.1, 1.11.2 — `defaultProps` moved to destructuring defaults
  /// with the same values, so the two releases draw identically.
  v1_11_1(['1.11.1', '1.11.2'], VariantEra.modern),

  /// Upstream 2.0.0 through 2.0.4 — the TypeScript rewrite.
  v2_0_0(['2.0.0', '2.0.1', '2.0.2', '2.0.3', '2.0.4'], VariantEra.modern);

  const BoringAvatarsVersion(this.upstreamVersions, this.variantEra);

  /// Every upstream release this state reproduces exactly.
  final List<String> upstreamVersions;

  /// Which variant roster this state dispatches.
  final VariantEra variantEra;

  /// The newest state — what you get unless you ask for an older one.
  static const BoringAvatarsVersion latest = v2_0_0;
}

/// How a state resolves the variant it is handed.
///
/// This mirrors upstream's `avatar.js` exactly, including its habit of
/// degrading rather than failing: an unknown or not-yet-existing variant falls
/// back to the state's default instead of throwing.
extension BoringAvatarsVersionVariants on BoringAvatarsVersion {
  /// The variants this state actually dispatches.
  Set<BoringAvatarsVariant> get reachableVariants => switch (variantEra) {
    VariantEra.original => const {
      BoringAvatarsVariant.geometric,
      BoringAvatarsVariant.abstractStyle,
      BoringAvatarsVariant.beam,
      BoringAvatarsVariant.eye,
      BoringAvatarsVariant.marble,
    },
    VariantEra.reshuffled => const {
      BoringAvatarsVariant.marble,
      BoringAvatarsVariant.dome,
      BoringAvatarsVariant.moholy,
      BoringAvatarsVariant.beam,
      BoringAvatarsVariant.ring,
    },
    VariantEra.expanded => const {
      BoringAvatarsVariant.marble,
      BoringAvatarsVariant.pixel,
      BoringAvatarsVariant.bauhaus,
      BoringAvatarsVariant.ring,
      BoringAvatarsVariant.beam,
      BoringAvatarsVariant.sunset,
      BoringAvatarsVariant.dome,
    },
    VariantEra.modern => const {
      BoringAvatarsVariant.pixel,
      BoringAvatarsVariant.bauhaus,
      BoringAvatarsVariant.ring,
      BoringAvatarsVariant.beam,
      BoringAvatarsVariant.sunset,
      BoringAvatarsVariant.marble,
    },
  };

  /// What an unrecognised variant falls back to.
  BoringAvatarsVariant get defaultVariant => variantEra == VariantEra.original
      ? BoringAvatarsVariant.geometric
      : BoringAvatarsVariant.marble;

  /// Names upstream kept working after retiring the variant behind them.
  ///
  /// Empty before upstream 1.5.3 — in the eras between, `geometric` and
  /// `abstract` were simply unreachable, not redirected.
  Map<BoringAvatarsVariant, BoringAvatarsVariant> get deprecatedAliases =>
      variantEra == VariantEra.modern
      ? const {
          BoringAvatarsVariant.geometric: BoringAvatarsVariant.beam,
          BoringAvatarsVariant.abstractStyle: BoringAvatarsVariant.bauhaus,
        }
      : const {};

  /// Resolves [variant] to what this state would actually draw.
  ///
  /// Aliases are checked before reachability — the order upstream uses — so a
  /// deprecated name resolves to its replacement rather than to the default.
  BoringAvatarsVariant resolveVariant(BoringAvatarsVariant variant) {
    final alias = deprecatedAliases[variant];
    if (alias != null) return alias;
    if (reachableVariants.contains(variant)) return variant;
    return defaultVariant;
  }
}
