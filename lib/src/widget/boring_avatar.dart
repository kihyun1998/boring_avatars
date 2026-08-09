/// The consumer seam: an avatar on screen, drawn by this package's own
/// rasterizer.
///
/// **Not `flutter_svg`, and not `Canvas`.** Measured in #78: `flutter_svg` does
/// not clamp `rx` the way SVG 1.1 §9.4 requires, so the circular mask every
/// variant relies on becomes a square, and it has no `<filter>` at all, so
/// `marble` loses its blur. Delegating to `Canvas` would make the output depend
/// on Skia-vs-Impeller, GPU, platform and Flutter version, which is the whole
/// reason the rasterizer exists (`CLAUDE.md`, invariant 4).
///
/// **It reaches the core by sibling `src/` import, not through the barrel** —
/// `buildAvatarScene` is deliberately unexported and `rasterizeScene` is not
/// exported at all. The barrel is what a *dependent* imports; this layer is
/// inside the package.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../avatar.dart';
import '../raster/raster.dart';
import '../raster/scene_raster.dart';
import '../variant.dart';
import '../version.dart';

/// An avatar, rasterised at the display's physical pixel size.
///
/// ```dart
/// BoringAvatar(
///   name: 'Clara Barton',
///   colors: const ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'],
///   size: 80,
///   version: BoringAvatarsVersion.v1_6_1,
///   variant: BoringAvatarsVariant.beam,
/// )
/// ```
///
/// ## `colors` is narrower here than on [boringAvatarSvg]
///
/// The SVG function passes a colour through to the document and a browser draws
/// it, so `'red'` works there. This rasterizer reads `#RRGGBB` and nothing else
/// yet, and a colour it cannot read would draw a **blank** avatar rather than
/// fail — so this widget rejects it instead, naming the argument. Later
/// releases widen what is accepted; a palette that works today keeps working.
class BoringAvatar extends StatefulWidget {
  const BoringAvatar({
    super.key,
    required this.name,
    required this.colors,
    required this.size,
    required this.version,
    this.variant = BoringAvatarsVariant.marble,
    this.square = false,
    this.semanticLabel,
  });

  /// The only input the drawing comes from.
  final String name;

  /// The palette, as `#RRGGBB` strings — see the note on this class.
  final List<String> colors;

  /// The side, in **logical** pixels.
  ///
  /// A number, not [boringAvatarSvg]'s `num`-or-`String`: `'100%'` has no basis
  /// before layout, and a size taken from `BoxConstraints` would only be known
  /// at layout time and so could not be memoised on this widget's fields.
  ///
  /// **There is no upper bound, and that is a decision rather than an
  /// oversight.** Cost is O(area) — roughly 86 bytes of `Float64` per output
  /// pixel on the filtered path, so `marble` at 1024 physical pixels a side
  /// takes about 2.4 s and an 86 MiB layer, and 2048 is four times that again.
  /// A ceiling was considered and rejected: this package refuses input it
  /// **cannot honour** (a `size` that is not a size, a non-uniform scale), and
  /// a large avatar is one it can honour, only slowly. Deciding how slow is too
  /// slow is the caller's budget, and size is theirs to inject.
  ///
  /// Multiply by the device pixel ratio before judging: a 512-logical avatar on
  /// a 3x display is 1536 physical.
  final double size;

  /// Which upstream release to reproduce. Required, and it has no default —
  /// a default of "newest" would redraw the avatars in an app that upgraded.
  final BoringAvatarsVersion version;

  final BoringAvatarsVariant variant;

  /// Drops the mask's corner radius.
  final bool square;

  /// The accessibility label.
  ///
  /// Left to the caller rather than defaulting to [name]: `name` is often an id
  /// or an email and is usually announced by an adjacent widget already. The
  /// node is still marked as an image.
  final String? semanticLabel;

  @override
  State<BoringAvatar> createState() => _BoringAvatarState();
}

/// Everything the drawing depends on, as one comparable value.
///
/// The palette is compared **by content and copied**, not held by identity. The
/// idiomatic call site writes the list literal inline in `build()`, which is a
/// new object every frame — identity would give a 0% hit rate and re-rasterise
/// forever. Copying also means a caller mutating the list afterwards cannot
/// silently change what is already on screen.
@immutable
class _AvatarKey {
  _AvatarKey({
    required this.name,
    required List<String> colors,
    required this.pixels,
    required this.version,
    required this.variant,
    required this.square,
  }) : colors = List<String>.unmodifiable(colors);

  final String name;
  final List<String> colors;

  /// The **physical** side. Logical size and device pixel ratio never appear
  /// separately: two different pairs that land on the same physical square draw
  /// the same bytes.
  final int pixels;

  final BoringAvatarsVersion version;
  final BoringAvatarsVariant variant;
  final bool square;

  @override
  bool operator ==(Object other) =>
      other is _AvatarKey &&
      other.name == name &&
      other.pixels == pixels &&
      other.version == version &&
      other.variant == variant &&
      other.square == square &&
      _sameColours(other.colors, colors);

  static bool _sameColours(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    name,
    Object.hashAll(colors),
    pixels,
    version,
    variant,
    square,
  );
}

/// Scene → pixels → a `ui.Image`, with nothing of the widget in it.
///
/// **Extracted so the hand-off can be proved.** Step 4 asks this layer for the
/// produced image's bytes against the goldens, and that proof cannot be taken
/// through the widget: a raster started from `build()` lives in the test
/// binding's fake-async zone while `decodeImageFromPixels` completes on a real
/// callback, and no arrangement of pumps bridges the two — measured, all three
/// arrangements either hang or never arrive, and `decodeImageFromPixelsSync`
/// is "not implemented on Skia", which is the test backend. A future *created
/// inside* `runAsync` has no such problem, and that is exactly what a caller of
/// this function does.
///
/// It is library-private in the sense that matters: the barrel does not export
/// it, so it is not API. The tests reach it by sibling import, as `tool/` does.
Future<ui.Image> rasterAvatarImage({
  required String name,
  required List<String> colors,
  required int pixels,
  required BoringAvatarsVersion version,
  required BoringAvatarsVariant variant,
  required bool square,
}) async {
  final scene = buildAvatarScene(
    name: name,
    colors: colors,
    size: pixels,
    version: version,
    variant: variant,
    square: square,
  );
  final raster = rasterizeScene(scene, width: pixels, height: pixels);

  // **`PixelFormat.rgba8888` is premultiplied and our buffer is straight.**
  // Straight is the deliberate choice — a browser hands back straight bytes, so
  // a premultiplied buffer would differ from Chrome on every antialiased pixel
  // — and `raster.dart:22` already records that the cost is "one multiply at
  // the Flutter hand-off". This is that multiply.
  final premultiplied = Uint8List(raster.bytes.length);
  for (var i = 0; i < raster.bytes.length; i += 4) {
    final a = raster.bytes[i + 3];
    premultiplied[i] = (raster.bytes[i] * a + 127) ~/ 255;
    premultiplied[i + 1] = (raster.bytes[i + 1] * a + 127) ~/ 255;
    premultiplied[i + 2] = (raster.bytes[i + 2] * a + 127) ~/ 255;
    premultiplied[i + 3] = a;
  }

  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    premultiplied,
    pixels,
    pixels,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

class _BoringAvatarState extends State<BoringAvatar> {
  _AvatarKey? _drawn;
  ui.Image? _image;

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  /// Rejects a palette the raster path cannot read, naming the argument.
  ///
  /// An **empty** palette is not a bad colour: five variants render with
  /// colours missing and `beam` throws because upstream throws there (ruling
  /// S-2). Turning that into a `colors` error here would rename a divergence
  /// the ledger already settled.
  void _checkPalette() {
    for (final colour in widget.colors) {
      if (parseHexColour(colour) == null) {
        throw ArgumentError.value(
          colour,
          'colors',
          'the raster path reads #RRGGBB and nothing else yet; '
              'boringAvatarSvg accepts any CSS colour, this widget does not',
        );
      }
    }
  }

  void _sync(_AvatarKey key) {
    if (key == _drawn) return;
    _drawn = key;
    unawaited(_raster(key));
  }

  Future<void> _raster(_AvatarKey key) async {
    final image = await rasterAvatarImage(
      name: key.name,
      colors: key.colors,
      pixels: key.pixels,
      version: key.version,
      variant: key.variant,
      square: key.square,
    );

    // Unmounted, or the inputs moved on while this was in flight: the arriving
    // image is nobody's and has to be released rather than assigned.
    if (!mounted || key != _drawn) {
      image.dispose();
      return;
    }
    final previous = _image;
    setState(() => _image = image);
    // **Not disposed synchronously.** The frame being painted can still hold
    // the outgoing image; the framework's own widget defers this to a
    // post-frame callback for the same reason.
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  Widget build(BuildContext context) {
    _checkPalette();

    // **`devicePixelRatioOf`, not `MediaQuery.of`.** The aspect-scoped lookup
    // rebuilds only when the ratio itself changes; the whole-data one rebuilds
    // when a keyboard appears or the text scale moves, and each of those would
    // cost a full re-rasterisation.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final pixels = (widget.size * dpr).round();
    if (pixels <= 0) {
      throw ArgumentError.value(
        widget.size,
        'size',
        'must be positive; $dpr device pixels per logical pixel makes this '
            '$pixels physical',
      );
    }

    _sync(
      _AvatarKey(
        name: widget.name,
        colors: widget.colors,
        pixels: pixels,
        version: widget.version,
        variant: widget.variant,
        square: widget.square,
      ),
    );

    final image = _image;
    return Semantics(
      image: true,
      container: widget.semanticLabel != null,
      label: widget.semanticLabel ?? '',
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        // **`FilterQuality.none`.** `RawImage` defaults to `medium`, and
        // `paintImage` has no identity fast path — it always goes through
        // `drawImageRect`. Since the buffer is already the box's physical size,
        // any sampling at all would be Skia's, which invariant 4 refuses.
        //
        // The remaining case is outside this widget: if layout puts the box's
        // origin on a fractional device pixel, the sampler runs anyway.
        child: image == null
            ? null
            : RawImage(
                image: image,
                width: widget.size,
                height: widget.size,
                filterQuality: FilterQuality.none,
              ),
      ),
    );
  }
}
