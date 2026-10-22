# thegraph — boring_avatars

## What this project is

A bit-exact Dart port of boringdesigners/boring-avatars: the same name, palette and variant give the same SVG and pixels npm does.

## References

| Source | Informs | Reached by | Binding |
|---|---|---|---|
| boring-avatars, at the tag being ported (never HEAD) | how it works | `../.refs/boring-avatars` sparse clone of `src/lib`, all tags — raw; never WebFetch | spec |
| ECMA-262 | how it works | a Node probe's output first, then the spec text — raw | spec |
| SVG 1.1, Filter Effects, CSS Color 4 | how it works | normative spec text — raw, not a restatement | spec |
| Chrome | how it works | a render measured directly (`tool/calibrate`, `tool/crosscheck`) — raw | spec, only where the specs above are silent |
| Flutter SDK | how it works | SDK source — raw | spec |
| pub.dev | what is published | `curl -s https://pub.dev/api/packages/boring_avatars` — raw | spec |

The reference tree, once (full tag history, so no `--depth 1`):

```bash
mkdir -p ../.refs && cd ../.refs
git clone --filter=blob:none --sparse https://github.com/boringdesigners/boring-avatars boring-avatars
cd boring-avatars && git sparse-checkout set src/lib && git fetch --tags
```
