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

import 'package:flutter/foundation.dart' show compute;
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
  /// oversight.** A ceiling was considered and rejected: this package refuses
  /// input it **cannot honour** (a `size` that is not a size, a non-uniform
  /// scale), and a large avatar is one it can honour, only slowly. Deciding how
  /// slow is too slow is the caller's budget, and size is theirs to inject —
  /// which only works if the budget is stated, so here it is.
  ///
  /// Cost is O(area). The filtered path (`marble`) holds roughly **86 bytes of
  /// `Float64` per output pixel**, so 1024 physical pixels a side is an 86 MiB
  /// layer and 2048 is four times that again. Measured time, `marble`:
  ///
  /// | | native | web |
  /// |---|---|---|
  /// | 210 physical | 237 ms | — |
  /// | 480 physical | — | 5.4 s |
  ///
  /// Web is the expensive platform and the numbers include the banding tax that
  /// buys the frame back — 2.1x there, 10–26% on native.
  ///
  /// **That argument used to have a hole, and the hole is now closed.** It
  /// assumed the caller could budget around "slow", which was false while the
  /// raster ran inside `build()` and froze the thread for the duration. It no
  /// longer does: the drawing goes through an isolate on native and yields
  /// between bands on web, so a slow avatar is a *late* avatar rather than a
  /// stalled application. Cost is still real, and still the caller's to weigh.
  ///
  /// Building for WebAssembly does **not** help — measured, it ran this code
  /// 2.2–2.6x slower than dart2js.
  ///
  /// The application stays responsive throughout, but "responsive" is not
  /// "free": the worst measured stall at the shipped slice is 23 ms, so a web
  /// raster drops at least one 60 Hz frame however small the avatar is.
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

/// Everything the drawing needs, as one value an isolate can carry.
///
/// Primitives and enums only — no `ui.Image`, no closure over the widget. That
/// is not a style choice: it is what makes the type a legal `compute` message.
typedef _RasterRequest = ({
  String name,
  List<String> colors,
  int pixels,
  BoringAvatarsVersion version,
  BoringAvatarsVariant variant,
  bool square,
});

/// Scene → pixels → premultiplied bytes. **Top-level, because `compute` needs
/// a target it can name rather than a closure it would have to capture.**
///
/// Async because [rasterizeSceneAsync] is: the raster hands the loop back
/// between bands, which is what keeps a frame alive on web where `compute` has
/// no isolate to hide the work in. `ComputeCallback` is
/// `FutureOr<R> Function(M)`, so a future here is legal rather than a
/// workaround.
Future<Uint8List> _rasterBytes(_RasterRequest request) async {
  final scene = buildAvatarScene(
    name: request.name,
    colors: request.colors,
    size: request.pixels,
    version: request.version,
    variant: request.variant,
    square: request.square,
  );
  final raster = await rasterizeSceneAsync(
    scene,
    width: request.pixels,
    height: request.pixels,
  );

  // **`PixelFormat.rgba8888` is premultiplied and our buffer is straight.**
  // Straight is the deliberate choice — a browser hands back straight bytes, so
  // a premultiplied buffer would differ from Chrome on every antialiased pixel
  // — and `raster.dart:22` already records that the cost is "one multiply at
  // the Flutter hand-off". This is that multiply.
  //
  // **It slices like the drawing does, and for the same reason.** It is O(area)
  // — 2.4 million iterations for a 512-logical avatar on a 3x display — and on
  // web `compute` has no isolate to put it in, so leaving it as one
  // uninterruptible pass would hand back exactly the stall the banding removed,
  // just after the drawing instead of during it.
  final width = request.pixels;
  final premultiplied = Uint8List(raster.bytes.length);
  final clock = Stopwatch()..start();
  for (var y = 0; y < request.pixels; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final a = raster.bytes[i + 3];
      premultiplied[i] = (raster.bytes[i] * a + 127) ~/ 255;
      premultiplied[i + 1] = (raster.bytes[i + 1] * a + 127) ~/ 255;
      premultiplied[i + 2] = (raster.bytes[i + 2] * a + 127) ~/ 255;
      premultiplied[i + 3] = a;
    }
    if (clock.elapsed >= defaultRasterSlice) {
      await Future<void>.delayed(Duration.zero);
      clock.reset();
    }
  }
  return premultiplied;
}

/// Scene → pixels → a `ui.Image`, with nothing of the widget in it.
///
/// **The split is not arbitrary — it is where an isolate boundary can go.**
/// A `ui.Image` is an engine resource and cannot cross one, so the drawing goes
/// through [compute] and the decode stays on the calling thread. Measured in
/// #80: the hop costs 0.3 ms and does not grow with the buffer, so there is no
/// size below which it is not worth taking, and therefore no threshold for this
/// package to invent.
///
/// On web `compute` has no isolate to offer and runs `_rasterBytes` on the main
/// thread — which is why the raster bands and yields on its own rather than
/// relying on the hop.
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
  final premultiplied = await compute(_rasterBytes, (
    name: name,
    colors: colors,
    pixels: pixels,
    version: version,
    variant: variant,
    square: square,
  ), debugLabel: 'boring_avatars raster');

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
  /// The newest key `build` has asked for.
  _AvatarKey? _wanted;

  /// The key the drawing loop has finished with — drawn, or failed and reported.
  _AvatarKey? _settled;

  /// Whether [_drawLatest] is running. **One raster at a time, and this is what
  /// enforces it.**
  ///
  /// Before the raster moved off `build()` it was synchronous, so a second one
  /// could not start until the first had finished: concurrency was structurally
  /// one and nothing had to say so. Going asynchronous removed that silently.
  /// Without this flag every rebuild with a different key — an animated `size`,
  /// a rotation, a recycled list row — starts *another* `compute`, each holding
  /// its own O(area) buffers, and on web each one still claims its slice of the
  /// single thread, so the avatar the user is waiting for arrives later the more
  /// of them are in flight.
  bool _drawing = false;

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
    if (key == _wanted) return;
    _wanted = key;
    // A raster already running will pick this up when it lands: it re-reads
    // `_wanted` rather than closing over the key it started with.
    if (!_drawing) unawaited(_drawLatest());
  }

  /// Draws until what is on screen is what was last asked for.
  ///
  /// **A loop rather than a call per rebuild**, which is what bounds the work: a
  /// burst of ten different sizes starts one raster, not ten, and the nine
  /// superseded keys are never drawn at all rather than drawn and thrown away.
  Future<void> _drawLatest() async {
    _drawing = true;
    try {
      while (mounted) {
        final key = _wanted;
        if (key == null || key == _settled) return;

        final ui.Image image;
        try {
          image = await rasterAvatarImage(
            name: key.name,
            colors: key.colors,
            pixels: key.pixels,
            version: key.version,
            variant: key.variant,
            square: key.square,
          );
        } catch (error, stack) {
          // Settled *as failed*: retrying the input that just threw would
          // report the same error forever. A different key is a different key
          // and the loop picks it up on the next turn.
          _settled = key;
          _rasterFailed(key, error, stack);
          continue;
        }

        // Unmounted, or the inputs moved on while this was in flight: the
        // arriving image is nobody's and has to be released rather than
        // assigned.
        if (!mounted) {
          image.dispose();
          return;
        }
        if (key != _wanted) {
          image.dispose();
          continue;
        }

        _settled = key;
        final previous = _image;
        setState(() => _image = image);
        // **Not disposed synchronously.** The frame being painted can still
        // hold the outgoing image; the framework's own widget defers this to a
        // post-frame callback for the same reason.
        if (previous != null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => previous.dispose(),
          );
        }
      }
    } finally {
      _drawing = false;
    }
  }

  /// A raster that threw, handled where it can be seen.
  ///
  /// **Two separate failures were possible here, and both were live.** The
  /// error vanished into the zone — `avatar.dart` promises an `ArgumentError`
  /// for `beam` with an empty palette and this surface threw nothing — and the
  /// *previous* avatar stayed on screen, so a widget whose fields said `beam`
  /// kept drawing the `pixel` it used to be. Silently, and forever.
  ///
  /// So: report it where the framework's error machinery can see it, and drop
  /// the stale image, because showing the wrong avatar is the plausible wrong
  /// picture this package's seams exist to refuse.
  ///
  /// The key is marked settled before this runs, on purpose. Retrying the input
  /// that just threw would report the same error every frame; a *different*
  /// input is a different key and the draw loop picks it up.
  void _rasterFailed(_AvatarKey key, Object error, StackTrace stack) {
    if (!mounted || key != _wanted) return;

    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'boring_avatars',
        context: ErrorDescription(
          'rasterising a BoringAvatar (${key.variant.name}, '
          '${key.pixels}x${key.pixels} physical)',
        ),
      ),
    );

    final stale = _image;
    if (stale != null) {
      setState(() => _image = null);
      WidgetsBinding.instance.addPostFrameCallback((_) => stale.dispose());
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

    // **Checked before the arithmetic, not after.** `.round()` on a non-finite
    // double throws `UnsupportedError: Infinity or NaN toInt`, which names an
    // internal conversion the caller never wrote and no argument at all — and
    // an unbounded `BoxConstraints.maxWidth` hands over exactly that value in
    // perfectly ordinary code. S-4's rule is that a public seam rejects what it
    // cannot honour and says which argument; this is the seam, and running the
    // multiply first was a counterexample to it.
    if (!widget.size.isFinite || widget.size <= 0) {
      throw ArgumentError.value(
        widget.size,
        'size',
        'must be a finite, positive number of logical pixels',
      );
    }
    final pixels = (widget.size * dpr).round();
    if (pixels < 1) {
      // A separate message, because a separate thing is wrong: the size *is*
      // positive and the device is what makes it vanish. "must be positive" was
      // simply untrue here, and a message that misdescribes the input sends the
      // reader to the wrong argument.
      throw ArgumentError.value(
        widget.size,
        'size',
        'is positive but rounds to $pixels physical pixels at a device pixel '
            'ratio of $dpr; there is no image that small',
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
