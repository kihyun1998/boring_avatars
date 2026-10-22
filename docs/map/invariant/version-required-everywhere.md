# Version is required everywhere

## The fact
Every public entry point that draws an avatar takes `version` as a **required**
argument with no default. Today that is `boringAvatarSvg`
(`required BoringAvatarsVersion version,` in `lib/src/avatar.dart`) and
`BoringAvatar` (`required this.version,` in
`lib/src/widget/boring_avatar.dart`). `BoringAvatarsVersion.latest` stays on the
enum, but a caller must pass it explicitly.

## Why it is cross-cutting
The ruling is about what a caller can be handed silently. The two surfaces are
separate classes that do not call each other for their parameter lists. Each
is guarded by its own source-text test in `api_surface_test.dart`, because
Dart cannot be asked at runtime whether a parameter has a default:
- "the SVG function takes no default version";
- the widget's "version must stay required on the widget too".

A default on either one makes the effective selector move when the package is
upgraded. That is the failure the
[frozen-selector-output](frozen-selector-output.md) invariant exists to
prevent, reached by another route. For example, `0.2.0` silently drops
`<title>` for anyone on `latest`, and `0.3.0` redraws every `pixel` avatar.

## Territories it holds in
- [public-svg-surface](../territory/public-svg-surface.md) — `boringAvatarSvg`, and the ruling's event (maintainer, 2026-08-08)
- [widget-lifecycle](../territory/widget-lifecycle.md) — `BoringAvatar`
- [version-selectors](../territory/version-selectors.md) — `latest`, which moves with each release

## What a violation looks like
A caller who omitted `version` gets a different avatar after `flutter pub
upgrade`, with no line of their code changed.

## Discovery history
- Ruled required by the maintainer on 2026-08-08: they were shown three options
  (required / `latest` / `v1_6_1` fixed) with their costs. The event is carried
  in public-svg-surface.
- The first guard read only `boringAvatarSvg`. The widget arrived in #80 and
  the guard did not cover it until a second test was added (theflow.md @
  0593e28; the guard's own reason strings).
- `size` is required for the same reason. Upstream's default `size` changed
  three times across the covered range (40, none, `'40px'`), and it stays out
  of the version state only because the caller always supplies one.
- Promoted to an invariant at map init (maintainer, 2026-10-22).

## Where it will recur
Any new public surface that draws an avatar — an `ImageProvider`, a
`CustomPainter` helper, a cache API — is subject to this. It needs `version`
required and its own source-text test, since the existing tests read only the
two signatures they name.
