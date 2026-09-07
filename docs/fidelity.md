# What "bit-exact" is measured to mean

Given the same name, palette and variant, this package produces the avatar the
npm package produces — the same numbers, the same SVG, the same bytes. This
document is the evidence behind that sentence, and the three places it stops.

## Releases share a selector when a caller gets the same thing out of them

Not when their source happens to match. `1.6.1`, `1.6.2` and `1.6.3` collapse
into one value because all three were measured to render byte-identical
documents, not because the code looked similar. The nine releases behind
`v1_10_1` are the sharper case of the same rule: their *sources* differ plenty
— a props rework, a full TypeScript rewrite — and rendering every one of them
side by side is what shows a caller gets the same document out of all nine.

For `v1_10_1`, each of the other eight releases is rendered and compared to
1.10.1 across **2,400 documents — variant × name × palette × title × square —
zero differ**. For `v1_7_0`, the same comparison covers 1.10.0; 1.8.0 and 1.9.0
cannot be rendered by anybody — their npm tarballs contain no JavaScript at all
(`main` points at a `build/index.js` that is not in the package — 0 files,
counted) — so their evidence is that their source tree *is* 1.10.0's, byte for
byte. `2.0.3` and `2.0.4` have no git tag; they are covered from the npm
packages themselves, whose recorded publish commits resolve in upstream's
history (both to the same source tree as `master`), and that resolution is
recorded in the fixture.

The emitted documents are pinned by the test suite against fixtures generated
from the real npm package — 600 per selector, across six variants, twenty names
and five palettes, plus title, square and size variations. Both the parity
harness and the browser tooling live in this repository, so any of it can be
re-measured rather than taken on trust.

## `1.11.0` is the one hole in the table, and it is deliberate

It sits between two supported releases, so it deserves its own sentence: 1.11.0
spreads the component's own props onto the `<svg>` element — the markup carries
`colors="…" name="…"` attributes no other release emits — and upstream fixed it
in 1.11.1. Supporting it would mean reproducing those attributes. A caller
pinned to 1.11.0 is told it is unsupported rather than quietly handed a
neighbour's output.

## These are upstream's git tags, not its npm versions

The two disagree in both directions. npm `1.2.1` republished 0.1.4-era code — a
tag's worth of history under a number that suggests otherwise. And going the
other way, upstream's **two most recent npm releases have no tag at all**: the
tags stop at `v2.0.2`, while npm carries `2.0.3` and `2.0.4`, and `2.0.4` is
what `npm install boring-avatars` gives you today.

So when you pin a version here you are naming a tag in
[the upstream repository](https://github.com/boringdesigners/boring-avatars/tags),
and for the newest releases this package will name the source it read instead.
Where the two numbering schemes point at the same code, they agree; where they
do not, the tag is what a selector means.

## The three things that are not reproduced

### 1. A `sunset` name containing quotes or brackets

With `variant: sunset`, a name containing `'`, `"`, `(`, `)`, `\` or a control
character makes upstream build a gradient reference that is not a valid CSS url
token — so the browser resolves nothing and **paints a blank avatar**.
Reproduced in Chrome: `O'Brien-Smith, Jr.` renders as fully transparent pixels.
This package percent-encodes that reference, so the avatar renders. The
gradient's own `id` stays byte-identical to upstream, and so does every other
name and every other variant.

An apostrophe in a name is common enough that reproducing the blank was judged
the wrong trade. If you need upstream's exact bytes including its blanks, this
is the one place you will not get them. **The other five variants are
unaffected** — `sunset` is the only one that puts the caller's name inside an id.

### 2. A `size` that is not a size

`size` accepts a `num` (`80` → `width="80"`) or a `String` (`'100%'`). Anything
else throws an `ArgumentError` naming the argument. Upstream instead coerces,
because React does:

| `size` | upstream 1.6.1 | this package |
|---|---|---|
| `80`, `'100%'` | `width="80"`, `width="100%"` | identical |
| `true`, `false`, `null` | `width` and `height` **absent**, plus a React console warning | `ArgumentError` |
| `[80]` | `width="80"` | `ArgumentError` |
| `{}` | `width="[object Object]"` | `ArgumentError` |

Reproducing that would mean reproducing JavaScript's `String()` coercion and
React's attribute-dropping rules in order to emit `width="[object Object]"`
faithfully — and React prints that warning precisely to tell the author they
made a mistake, so the behaviour being reproduced is a bug report. Every value a
caller can plausibly mean by "size" is byte-identical; the divergence is
confined to values that are not sizes at all.

### 3. The document's internal ids, which cannot be reproduced by anyone

From 1.8.0 upstream names its mask with React's `useId()`, which is the
component's position in the render tree rather than anything about the avatar.
Measured: the same avatar is `:R0:` alone, `:R3:` as a third child, `:R2:` after
a `<span>` — and **two copies of one avatar in a single document get two
different ids**. So such a release has no fixed bytes for an avatar for anything
to reproduce, including itself. This package emits the literal `mask__marble`
that 1.7.0 writes, at every position — and the same goes for `marble`'s filter
id, which is the literal `prefix__filter0_f` through 1.10.1 and `useId()`-derived
from 1.10.2.

Everything a reader can see is unaffected, and that is measured rather than
argued: upstream's own documents and this package's went through one Chrome,
1,200 renders per selector — `v1_6_1` against 1.6.1, `v1_7_0` against 1.10.0,
`v1_10_1` against **2.0.4**, the far end of its group. Each run: **1,150
pixel-identical**, 40 where both sides produce no document at all (`beam` with
an empty palette), and the 10 `sunset` blanks documented above. **Zero
unexplained differences, in any run.**

If you need the document's internal ids to match a particular upstream render,
that is the one thing these selectors do not give you.

## Upstream's own bugs are reproduced, not corrected

Everything outside those three reproduces upstream exactly — including its
defects. The one that changes what a reader sees is in `marble`: its first path
takes its colour, translation and rotation from element 1 and its **scale from
element 2**, which is a copy-paste slip five neighbouring lines disagree with.
It is still there at upstream's `master` today. Correcting it would give **three
names in four** a different avatar from the one every `boring-avatars` user has
ever seen, so it is reproduced, and the suite pins it so nobody "fixes" it by
accident.
