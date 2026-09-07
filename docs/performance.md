# What drawing an avatar costs

Drawing happens off the frame — in a background isolate on native, and in
interruptible slices on web, where Flutter has no isolate to offer. Cutting the
drawing into slices is not a tax on it: measured back to back across eight runs
and five sizes, the interruptible drawing takes the same total time as the
uninterrupted one — the responsiveness is free.

Measured for `marble`, the most expensive variant, at its **physical** size:

| physical pixels a side | native | web |
|---|---|---|
| 80 (a 40-logical avatar at 2x) | 33 ms | |
| 120 (the same at 3x) | 80 ms | |
| 210 | 237 ms | |
| 480 | | 5.4 s |

The blanks are not measured. Cost grows with area and web runs the same drawing
about **four times slower** than native, which is enough to place them — but they
are arithmetic, and this table only states what was observed. They are also one
machine's: a busy machine moves the absolute numbers by several times, so read
them as an order of magnitude. The ratios below are the durable part, because a
ratio measured back to back cancels the conditions both halves shared.

Two things worth knowing before scaling from it. `pixel` is the cheapest variant
and `marble` and `beam` the dearest, but **the gap depends on the size**: `pixel`
is about eight times cheaper than `marble` at 80 physical pixels and only two to
three times cheaper at 480. The next section is why. And compiling to
WebAssembly does **not** help — measured, it is 2.2–2.6x slower than the
JavaScript build for this code.

## One size per variant is much cheaper than its neighbours

Each variant is drawn from a fixed-size design — 80 units for `marble`, `pixel`,
`sunset` and `bauhaus`, 90 for `ring`, 36 for `beam`. Ask for exactly that many
*physical* pixels and the scale is 1, which is the one case where an
axis-aligned rectangle stays a rectangle and takes an exact closed-form coverage
instead of going through the polygon integrator. The picture is the same either
way; the cost is not. Measured, `pixel` is **6.5x cheaper at 80 than at 81**, and
`bauhaus` about twice as cheap. `ring`, which has no axis-aligned rectangle in
it, does not move across the same step — which is what identifies the cause
rather than merely observing the dip.

So if you draw many avatars and can pick the number, a `size` where
`size × devicePixelRatio` lands exactly on the variant's own is worth having.
Nothing else about the avatar changes.

**One thing does change, and it is not a defect.** Away from that size, two
shapes that meet edge to edge can share a pixel, and neither fills it — so
`pixel` shows faint seams between its tiles at most scales. A browser does the
same thing with the same document: measured against Chrome at a 1.25 scale, both
leave **784** pixels partly covered and there is not one pixel Chrome fills that
this package leaves open. Reproducing the browser is the whole point, so the
seams stay.

Away from that one size the cost is O(area), so it is the physical size that
matters: doubling `size` is four times the work, and moving the same avatar from
a 2x display to a 3x one is 2.25 times.
