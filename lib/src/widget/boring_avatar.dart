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

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
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
/// The SVG function hands a colour to the document and a browser draws it, so
/// **any** CSS colour works there. This rasterizer reads:
///
/// * hex — `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`;
/// * the 148 CSS named colours, plus `transparent` and `currentColor`;
/// * `rgb()` / `rgba()` / `hsl()` / `hsla()`, either separator, percentages or
///   0–255, and an alpha as a number or a percentage.
///
/// Keywords are ASCII case-insensitive and tolerate surrounding whitespace, as
/// CSS defines them. Anything outside that grammar would draw a **blank** avatar
/// rather than fail, so this widget rejects it and names the argument.
///
/// A colour may carry its own transparency — `#RRGGBBAA`, `rgba(…)`, `hsla(…)`,
/// `transparent`. Its alpha multiplies the shape's coverage, which is what a
/// browser does with the same document.
class BoringAvatar extends StatefulWidget {
  /// Every parameter mirrors [boringAvatarSvg] — the two public surfaces
  /// deliberately share one vocabulary, so an avatar moved between them is
  /// the same avatar.
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

  /// The palette, as CSS colours — hex, a named colour, `transparent`,
  /// `currentColor`, or an `rgb()` / `hsl()` function. See the note on this
  /// class.
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

  /// Which of upstream's six drawings to render; the two deprecated aliases
  /// resolve exactly as upstream resolves them.
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

  /// Whether [other] is the **same picture**, at whatever resolution.
  ///
  /// Everything except [pixels], and the split is the point. Of the six inputs,
  /// five decide *what is drawn* — a different `name`, palette, `variant`,
  /// `version` or `square` is a different avatar — and only `pixels` decides how
  /// finely the same avatar is drawn.
  ///
  /// That is what lets an already-drawn image be judged: pixels made for another
  /// `name` are a picture of somebody else, while pixels made for the same one at
  /// a smaller size are the right picture at the wrong resolution.
  bool sameDrawingAs(_AvatarKey other) =>
      other.name == name &&
      other.version == version &&
      other.variant == variant &&
      other.square == square &&
      _sameColours(other.colors, colors);

  @override
  bool operator ==(Object other) =>
      other is _AvatarKey && other.pixels == pixels && sameDrawingAs(other);

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
    // **The widget has no `title` parameter, and adding one would be a value
    // nothing reads.** `<title>` is an accessible name for an SVG *document*;
    // this widget produces pixels, and `scene_raster.dart` filters the element
    // out before anything is drawn. Whichever way the version resolves it, the
    // raster is identical — so a parameter here would accept a caller's choice
    // and discard it. `null` says "no opinion", which is the true one.
    //
    // A Flutter caller who wants the avatar announced has `Semantics`, which
    // is the platform's own answer and reaches screen readers that never see
    // an SVG document.
    title: null,
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
      if (parseCssColour(colour) == null) {
        throw ArgumentError.value(
          colour,
          'colors',
          'not a CSS colour this rasterizer reads: hex, a named or system '
              'colour, transparent, currentColor, rgb()/rgba(), hsl()/hsla(), '
              'hwb(), lab()/lch(), oklab()/oklch(), or color()',
        );
      }
    }
  }

  void _sync(_AvatarKey key) {
    if (key == _wanted) return;

    // **A different picture must not keep the old one on screen while it draws.**
    //
    // This surface already refuses that on failure — a widget whose fields say
    // `beam` must stop drawing the `pixel` it used to be — and until now the
    // success path did the same thing for as long as a raster takes, which used
    // to be one frame and is now hundreds of milliseconds. A recycled list row
    // would show the previous person's face under the new person's name.
    //
    // **Resolution is the exception, and it is what keeps this usable.** When
    // only `pixels` moved, the image on screen is the right avatar drawn too
    // coarsely, not somebody else's; blanking it would make every size change
    // and every ratio change flash.
    //
    // No `setState`: this runs inside `build`, where one is illegal and none is
    // needed — the build below reads `_image` after this returns.
    final settled = _settled;
    final stale = _image;
    if (stale != null && (settled == null || !key.sameDrawingAs(settled))) {
      _image = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => stale.dispose());
    }

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
        // **The `SizedBox` is the layout and [PixelSnappedImage] is the
        // drawing, and they are deliberately not the same rectangle.** Layout
        // owes the caller the `size` they asked for; the drawing owes the
        // buffer a whole number of device pixels to land on, and `size * dpr`
        // is not whole at 125% or 150%. Painting the buffer at the box's own
        // fractional size was #110: `FilterQuality.none` has no way to spend
        // half a pixel, so it dropped or duplicated an entire column, and every
        // non-`square` variant puts a *vertical* outline exactly where that
        // shows — tangent to the box, with no margin to hide in.
        child: image == null
            ? null
            : PixelSnappedImage(image: image, devicePixelRatio: dpr),
      ),
    );
  }
}

/// The device-pixel-aligned rectangle an avatar buffer is drawn into.
///
/// **Pure, and separated from `paint` because it is the whole of the fix.** Its
/// two guarantees are that `left`, `top`, `width` and `height` are all whole
/// numbers of device pixels, and that the result is within half a device pixel
/// of where layout put the box. Everything #110 is about follows from the
/// first, and the price of it is the second.
///
/// **Why the width is rounded rather than taken from the buffer.** Rounding the
/// *box* to whole device pixels lands on exactly the `(size * dpr).round()` the
/// buffer was rasterised at while the box is the size the caller asked for —
/// the case the fix is about — and lets a parent that squeezes the box keep
/// squeezing the drawing, which is what `RawImage` did and what README
/// promises. Taking the buffer's own extent instead painted a 240-pixel avatar
/// across a 20-logical box at full size, over whatever sat beside it.
///
/// **Why [global] and not [local].** `local` is relative to the enclosing
/// *layer*, and a layer's origin is not on the grid just because this box's
/// offset within it is: a repaint boundary paints its child at `Offset.zero`
/// and carries the real position on an `OffsetLayer` that reaches the engine
/// unrounded. `ListView` wraps **every child** in one, and `Opacity`,
/// `FadeTransition` and `Hero` push layers of their own. Measured under an
/// inner boundary at ratio 1.5: 69 device pixels across, 272 of them partly
/// covered, for a 68-pixel buffer. `localToGlobal` walks the render tree rather
/// than the layer tree, so it sees through all of them; the correction it
/// yields is then applied to `local`, which is the space the canvas is in.
///
/// **Prior art agrees, and it was found after the fact rather than copied.**
/// Flutter snaps its own text caret the same way —
/// `RenderEditable._snapToPhysicalPixel` (`rendering/editable.dart:2341`)
/// computes `(global / (1 / dpr)).round() * (1 / dpr) - global`, which is this
/// function's correction term rearranged, and takes `global` from
/// `localToGlobal` for the same reason. Convergence, not derivation from it;
/// what the reference did supply is the non-finite guard below.
///
/// **What it cannot do is survive a scroll, and that is not fixable here.**
/// The correction is computed in `paint`, and a layer can move without its
/// child repainting — which is exactly what a `ListView` does, since it offsets
/// each child's repaint boundary instead of painting it again. Measured: after
/// a 7.3-logical scroll at ratio 1.5 the recorded destination was **11.2 device
/// pixels** stale and `paint` had not re-run. So a *stationary* avatar in a
/// list is on the grid and a *scrolling* one is not. Flutter tracks this as
/// flutter/flutter#111302 — *"no guarantee the render object will repaint if
/// this changes"* — and its own caret has the same limitation; the engine used
/// to pixel-snap layers and that was removed (flutter/flutter#111145).
///
/// **This is asserted directly rather than through a rendered pixel, and the
/// reason is invariant 4.** Skia, with `isAntiAlias` off, already rounds a
/// destination rectangle whose width is a whole number of device pixels — so a
/// screenshot cannot tell a snapped origin from an unsnapped one, and a test
/// that only looked at pixels left this function's central claim un-killable.
/// Leaning on that rounding would also be exactly the Skia-versus-Impeller
/// dependence `CLAUDE.md` refuses; doing the rounding here is what makes the
/// placement the package's own rather than the backend's.
@visibleForTesting
Rect snappedAvatarRect({
  required Offset global,
  required Offset local,
  required Size box,
  required double devicePixelRatio,
}) {
  double onGrid(double value) =>
      (value * devicePixelRatio).roundToDouble() / devicePixelRatio;

  // **A non-finite global position corrects by nothing rather than by `NaN`.**
  // `localToGlobal` walks the ancestor transforms, and a degenerate one — a
  // `Transform.scale(scale: 0)`, a collapsed matrix — hands back infinity or
  // `NaN`. Carried into the rectangle that reaches `drawImageRect`, that is a
  // drawing the caller never sees and an exception they cannot place. Flutter's
  // own `RenderEditable._snapToPhysicalPixel` guards the identical expression
  // the identical way, which is where this guard comes from rather than from a
  // failure.
  double correction(double at) => at.isFinite ? onGrid(at) - at : 0;

  return Rect.fromLTWH(
    local.dx + correction(global.dx),
    local.dy + correction(global.dy),
    onGrid(box.width),
    onGrid(box.height),
  );
}

/// Draws [image] across exactly its own number of **device** pixels, on the
/// device pixel grid.
///
/// **Why this exists rather than a [RawImage].** This package rasterises at
/// `(size * dpr).round()` physical pixels and hands the buffer over with
/// [FilterQuality.none], because any sampling at all would be Skia's and
/// `CLAUDE.md`'s invariant 4 refuses it. That is only honest while the buffer
/// and the rectangle it is painted into are the same number of device pixels,
/// and a `RawImage` sized in *logical* units cannot promise that: `size * dpr`
/// is fractional at every ratio that is not a whole number, and layout is free
/// to put the box's origin on a fractional device pixel too.
///
/// When both are true, nearest neighbour resolves the mismatch by dropping or
/// duplicating a whole column — measured in #110 at `size: 45`: 68 physical
/// pixels painted across 67.5 lose a column, and 56 across 56.25 gain one.
/// Neither condition is sufficient alone; a fractional origin under a whole
/// ratio is absorbed, and so is a fractional size at a whole origin.
///
/// **What it costs.** The drawn square is up to one device pixel wider than the
/// box and up to half a device pixel away from where layout put it — the two
/// roundings, and both are below the threshold of a thing anyone can see. What
/// it buys is that the buffer arrives whole, which is the claim the package
/// actually makes.
///
/// **One case is narrowed rather than closed, and it cannot be closed here.**
/// `(size * dpr).round()` sometimes rounds *up*, and then the buffer is
/// genuinely wider than the box — 45 logical at 150% is 67.5 device pixels
/// holding a 68-pixel buffer. An ancestor clipping to exactly the box then
/// takes the excess back off, which is #110's symptom again. No placement
/// avoids it: an integer rectangle of 68 does not fit inside 67.5, wherever it
/// starts. Measured across 105 combinations of ratio, inset and clip: the
/// `RawImage` this replaced was wrong in **21**, this is wrong in **6**, and
/// the 6 are a subset of the 21 — so the clip case is narrowed and nothing
/// regressed. Closing the rest means rasterising at `floor` rather than
/// `round`, which moves the buffer size and the smallest accepted `size`, and
/// that is a decision about the public surface rather than a rounding.
///
/// **What it does not fix.** Snapping reads [devicePixelRatio] against the
/// paint offset, so it is exact while the chain of ancestors between this box
/// and its enclosing layer is a pure translation — which is what paddings,
/// margins and insets are. Under an ancestor [Transform] that scales or
/// rotates, "the device pixel grid" is not axis-aligned with this box at all
/// and there is nothing to snap to; the drawing is then no worse than a
/// `RawImage` would be, and no better.
///
/// **Not exported.** The barrel does not name it, for the same reason it does
/// not name [rasterAvatarImage]: it is this package's own consumer layer, and
/// the tests reach it by sibling import as `tool/` does.
class PixelSnappedImage extends LeafRenderObjectWidget {
  /// Creates a widget that draws [image] one device pixel per image pixel.
  const PixelSnappedImage({
    super.key,
    required this.image,
    required this.devicePixelRatio,
  });

  /// The buffer to draw. Its width and height are read as **physical** pixels.
  ///
  /// This widget does not take ownership: the render object holds a clone and
  /// disposes that, exactly as [RawImage] does, so the caller's handle stays
  /// theirs to release.
  final ui.Image image;

  /// The ratio the box is **currently displayed** at.
  ///
  /// **Passed in rather than read from the context**, because the caller has
  /// already read it to decide how many pixels to rasterise, and two lookups
  /// can disagree across a rebuild.
  ///
  /// It is deliberately the *current* ratio and not the one [image] was made
  /// at, which are the same value except on the one path where they are not:
  /// `_sync` keeps an already-drawn avatar on screen while a new resolution
  /// rasterises, so between a ratio change and its raster landing this is a
  /// current ratio beside an older buffer. The grid to snap to is a property of
  /// the display, so the current one is the right input; the buffer simply
  /// scales in the meantime, which is what that path already promises.
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderPixelSnappedImage(
        image: image.clone(),
        devicePixelRatio: devicePixelRatio,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderPixelSnappedImage renderObject,
  ) {
    renderObject
      ..image = image.clone()
      ..devicePixelRatio = devicePixelRatio;
  }
}

/// The render object behind [PixelSnappedImage].
///
/// Public for the reason `RenderImage` is: [PixelSnappedImage.updateRenderObject]
/// names it in its signature. The barrel exports neither.
class RenderPixelSnappedImage extends RenderBox {
  /// Takes ownership of [image]; see [PixelSnappedImage.image].
  RenderPixelSnappedImage({
    required ui.Image image,
    required double devicePixelRatio,
  }) : _image = image,
       _devicePixelRatio = devicePixelRatio;

  ui.Image _image;

  /// Takes ownership of [value] and releases the handle it replaces.
  ///
  /// **The clone check is not an optimisation.** [PixelSnappedImage] clones on
  /// every rebuild, so without it an unchanged avatar would drop the handle it
  /// is currently painting and adopt a fresh one every frame. `isCloneOf` asks
  /// the question that matters — same underlying buffer — rather than identity,
  /// which a clone never satisfies. Same arrangement as `RenderImage`.
  set image(ui.Image value) {
    if (value.isCloneOf(_image)) {
      value.dispose();
      return;
    }
    final resized =
        value.width != _image.width || value.height != _image.height;
    _image.dispose();
    _image = value;
    markNeedsPaint();
    if (resized) markNeedsLayout();
  }

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
    markNeedsLayout();
  }

  /// The buffer's own logical side — what the box would take if nothing
  /// constrained it. The only call site wraps this in a `SizedBox` of the
  /// caller's `size`, whose tight constraints win; this is what makes the
  /// widget mean something on its own.
  Size get _intrinsic =>
      Size(_image.width / _devicePixelRatio, _image.height / _devicePixelRatio);

  @override
  double computeMinIntrinsicWidth(double height) => _intrinsic.width;

  @override
  double computeMaxIntrinsicWidth(double height) => _intrinsic.width;

  @override
  double computeMinIntrinsicHeight(double width) => _intrinsic.height;

  @override
  double computeMaxIntrinsicHeight(double width) => _intrinsic.height;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_intrinsic);

  @override
  void performLayout() => size = constraints.constrain(_intrinsic);

  /// **`RenderBox` says `false` and `RenderImage` says `true`, and the avatar
  /// needs the second one.** A leaf that declines the hit test is invisible to
  /// every ancestor that defers to its child — which is `GestureDetector`'s
  /// default whenever it has one — so an avatar inside an `onTap` would stop
  /// responding to taps. Measured: 0 taps against `RawImage`'s 1.
  @override
  bool hitTestSelf(Offset position) => true;

  /// Where the last `paint` put the drawing, in **global** logical pixels.
  ///
  /// **The only observation point for the half of the fix a screenshot cannot
  /// price.** Skia, with `isAntiAlias` off, already rounds a destination whose
  /// width is a whole number of device pixels — so whether `paint` snapped
  /// against the screen or against the enclosing layer makes no difference to
  /// any pixel this suite can capture, while making all the difference inside a
  /// `ListView`, where every child sits on a layer of its own. Without this a
  /// revert to the layer offset is silent.
  ///
  /// Written inside an `assert`, so it costs nothing in release and no shipped
  /// behaviour can come to depend on it.
  @visibleForTesting
  Rect? debugGlobalDestination;

  @override
  void paint(PaintingContext context, Offset offset) {
    final ratio = _devicePixelRatio;

    final global = localToGlobal(Offset.zero);
    final destination = snappedAvatarRect(
      global: global,
      local: offset,
      box: size,
      devicePixelRatio: ratio,
    );
    assert(() {
      debugGlobalDestination = destination.shift(global - offset);
      return true;
    }());

    context.canvas.drawImageRect(
      _image,
      Rect.fromLTWH(0, 0, _image.width.toDouble(), _image.height.toDouble()),
      destination,
      // `isAntiAlias` is `paintImage`'s value, not `Paint`'s default, so the
      // destination edge is treated exactly as the `RawImage` path treated it.
      Paint()
        ..isAntiAlias = false
        ..filterQuality = FilterQuality.none,
    );
  }

  @override
  void dispose() {
    _image.dispose();
    super.dispose();
  }
}
