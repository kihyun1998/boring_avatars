# Physical pixel rounding

## The fact
The widget's buffer side and the destination it is painted into must round
`logical × devicePixelRatio` **the same way**, half away from zero. There are
three sites:
- `_BoringAvatarState.build` sizes the buffer as `(widget.size * dpr).round()`;
- `snappedAvatarRect` places it at `(value * devicePixelRatio).roundToDouble() / devicePixelRatio`;
- `avatarLandsOnePixelPerPixel` decides `FilterQuality` by comparing
  `(box.width * devicePixelRatio).roundToDouble()` with `buffer.width`.

All of them are in `lib/src/widget/boring_avatar.dart`.

## Why it is cross-cutting
No helper is shared. Each site writes its own expression, and they agree only
because `int.round()` and `double.roundToDouble()` happen to share a tie rule.
The three decisions are separate:
- the buffer size decides what is rasterized;
- the destination decides where it lands;
- the predicate decides whether nearest-neighbour sampling is honest.

If one site switched to `floor` or `ceil`, or rounded `size` before
multiplying, the buffer would be one pixel off the destination at exactly the
fractional sizes ADR-0002 is about. `avatarLandsOnePixelPerPixel` would then
report a 1:1 landing that is not one, or refuse one that is.

## Territories it holds in
- [widget-lifecycle](../territory/widget-lifecycle.md) — `_BoringAvatarState.build`, the buffer side
- [pixel-placement](../territory/pixel-placement.md) — `snappedAvatarRect`, `avatarLandsOnePixelPerPixel`, `RenderPixelSnappedImage`

## What a violation looks like
Take a 45-logical avatar at 150%, which is 67.5 physical pixels. A 68-pixel
buffer drawn into a 67-pixel destination, or the reverse, makes
nearest-neighbour sampling drop or duplicate a whole column. On a disc that
touches all four edges of its box, that reads as a flat, shaved edge: the
pre-`0.3.1` symptom #110 reported. If the predicate disagrees with the other
two, `FilterQuality.none` is chosen for a scaled copy, which folds a smooth
`marble` gradient (#117).

## Discovery history
- [ADR-0002](../../adr/0002-when-the-box-and-the-pixel-grid-disagree.md) R1–R2
  (#110, 2026-08-18) fixed the rounding of the box. R5 (#117) added the
  predicate as a third reader of the same rounding.
- Promoted to an invariant at map init (maintainer, 2026-10-22). It was found
  by reading the three sites side by side; no incident.

## Where it will recur
If code converts a logical length to device pixels anywhere in the widget, it
is subject to this: a new placement path, a cache keyed on physical size, or a
debug overlay. Round the same way as the three sites above, or better, make
them call one helper.
