# boring_avatars — example

The controls from <https://boringavatars.com/>, drawn by this package.

```
flutter run            # from this directory
```

Pick a variant, cycle the palette, toggle round/square. Every avatar on screen
goes through `BoringAvatar`, so what you are looking at is what the package
guarantees: the same pixels upstream's npm package produces for the same name,
palette and variant.

Two panels under the gallery show the two public surfaces for the same avatar —
the widget call, and `boringAvatarSvg`'s document, byte for byte as upstream
emits it. The avatars above are that document, rasterised in software.

**Not `flutter_svg`.** Measured in #78: it does not clamp `rx` the way SVG 1.1
§9.4 requires, so the circular mask every variant relies on comes out square,
and it has no `<filter>`, so `marble` loses its blur — all six variants draw
wrongly. Not `Canvas` either, which would make the pixels depend on the GPU and
the Flutter version. That is the whole reason this package rasterises itself.
