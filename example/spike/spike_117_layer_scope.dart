// SPIKE (#117) — the instrument for one open question, kept for that reason.
//
// **It has already answered what it was built for**, and `0.3.2` ships the
// answer: with the enclosing layer half a device pixel past an integer, the
// screen-corrected placement differed from an unresampled reference in 2921 of
// 4356 pixels by up to 196 levels, while placing the drawing on the grid of the
// space it paints into came back **byte-identical**. Column three is that
// variant, and it is what the fix now does.
//
// **What keeps it in the tree is ADR-0002's validity condition for R6**: the
// rule stands on "the engine rounds the enclosing layer", measured on Windows
// at ratio 1.5 and **nowhere else**. If that is false on another backend, the
// old behaviour was right there and this one is wrong. Running these three
// columns on web (CanvasKit) or macOS is the check, and this file is it. Delete
// it once those are measured.
//
// Run (default window is big enough):
//   cd example
//   flutter run -t spike/spike_117_layer_scope.dart -d windows
//
// **Screenshot the window and hand it over. That is the instrument** — see the
// previous spike's finding: `RenderRepaintBoundary.toImage` re-rasterises the
// subtree offscreen and never runs the engine's composite onto the window, which
// is the step this is about. Twenty-eight fixture cells came back clean through
// it while the screen showed 94-level differences.
//
// **The question this settles.** A scroll viewport at a half-device-pixel origin
// resamples the avatar inside it. If it resamples *everything* in that layer —
// a vector circle Flutter draws itself, a line of text — then this is not a
// property of how this package hands over an image, it is what compositing a
// layer at a fractional offset does, and **no rendering strategy available to
// this package escapes it**: a layer is a texture whether what went into it was
// a bitmap or a path. If instead only the avatar moves, the hand-off is
// implicated after all and there is somewhere left to look.
//
// **How to read it.** Two columns, identical content, differing only in origin:
// the left layer starts half a device pixel past an integer, the right one on
// one. Three rows inside each: this package's avatar, a vector disc with a
// gradient (`BoxDecoration`, drawn by the engine every frame — no buffer of
// ours anywhere), and text. Compare left against right, row by row.
import 'dart:ui' as ui;

import 'package:boring_avatars/boring_avatars.dart';
// ignore: implementation_imports
import 'package:boring_avatars/src/widget/boring_avatar.dart'
    show rasterAvatarImage;
import 'package:flutter/material.dart';

void main() => runApp(const ScopeSpike());

const _ground = Color(0xFF1A1A21);
const _palette = ['#C9B8FD', '#3B7BF0', '#2E33A0'];
const _size = 44.0;

/// The vector disc's colours are the palette's two ends, so it carries a
/// gradient of comparable steepness to the avatar's — a flat fill would hide a
/// resample that a gradient shows.
const _from = Color(0xFF3B7BF0);
const _to = Color(0xFF2E33A0);

class ScopeSpike extends StatelessWidget {
  const ScopeSpike({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(debugShowCheckedModeBanner: false, home: _ScopePage());
}

class _ScopePage extends StatelessWidget {
  const _ScopePage();

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final view = View.of(context);

    // The fractional part of an origin is a physical quantity, so the positions
    // are stated in device pixels and converted here.
    const columnWidth = 420.0;
    const left = 60.0;

    return Scaffold(
      backgroundColor: _ground,
      body: Stack(
        children: [
          for (var i = 0; i < 4; i++)
            Positioned(
              // columns 0 and 2 sit half a device pixel past an integer;
              // column 1 sits on one and is the reference.
              left: (left + i * columnWidth + (i == 1 ? 0.0 : 0.5)) / ratio,
              top: 60 / ratio,
              child: SizedBox(
                width: 360 / ratio,
                height: 700 / ratio,
                child: _Layered(
                  ratio: ratio,
                  localSnap: i == 2,
                  globalSnap: i == 3,
                ),
              ),
            ),
          Positioned(
            left: (left + 0.5) / ratio,
            top: 20 / ratio,
            child: const Text(
              'layer @ half device pixel',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Positioned(
            left: (left + columnWidth) / ratio,
            top: 20 / ratio,
            child: const Text(
              'layer @ whole device pixel  (reference)',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Positioned(
            left: (left + 2 * columnWidth + 0.5) / ratio,
            top: 20 / ratio,
            child: const Text(
              'layer @ half  ·  A: snapped against the layer',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Positioned(
            left: (left + 3 * columnWidth + 0.5) / ratio,
            top: 20 / ratio,
            child: const Text(
              'layer @ half  ·  B: snapped against the screen (0.3.1)',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Positioned(
            right: 16,
            top: 16,
            child: DefaultTextStyle(
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('dpr $ratio · surface ${view.physicalSize}'),
                  const Text('스크린샷을 넘겨주세요 — 좌우를 행별로 대조합니다'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A scroll viewport — the ancestor measured to resample — holding three kinds
/// of drawing. Everything inside is identical between the two columns; only the
/// viewport's own origin differs.
class _Layered extends StatelessWidget {
  const _Layered({
    required this.ratio,
    this.localSnap = false,
    this.globalSnap = false,
  });

  final double ratio;

  /// Draw the avatar's buffer the way `0.3.1` did: corrected against the screen
  /// position. On a backend that rounds the enclosing layer this over-corrects;
  /// on one that does not, it is the placement that lands whole.
  final bool globalSnap;

  /// Draw the avatar's buffer with **variant A**: the destination is put on the
  /// grid of the space this box paints into, with no screen-space correction —
  /// the hypothesis being that the engine already places the enclosing layer on
  /// the grid, so the shipped correction is applied twice.
  final bool localSnap;

  @override
  Widget build(BuildContext context) {
    // 24 device pixels — whole, so the spacing is never the variable.
    final gap = SizedBox(height: 24 / ratio);
    return SizedBox(
      width: 320 / ratio,
      height: 660 / ratio,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            gap,
            // 1 — this package's buffer, shipped placement or variant A.
            SizedBox(
              width: _size,
              height: _size,
              child: (localSnap || globalSnap)
                  ? _LocalSnapAvatar(ratio: ratio, global: globalSnap)
                  : const BoringAvatar(
                      name: '박기현',
                      colors: _palette,
                      size: _size,
                      version: BoringAvatarsVersion.v1_7_0,
                      variant: BoringAvatarsVariant.marble,
                    ),
            ),
            gap,
            // 2 — a vector disc, drawn by the engine from a path and a gradient
            // every frame. No image of ours is involved anywhere in it.
            Container(
              width: _size,
              height: _size,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_from, _to],
                ),
              ),
            ),
            gap,
            // 3 — text, the third thing a layer can hold.
            const Text(
              'Hg 한글 0123',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            gap,
            // Enough content to make the viewport a viewport.
            SizedBox(height: 600 / ratio),
          ],
        ),
      ),
    );
  }
}

/// Variant A — the same buffer, placed on the **local** grid.
///
/// Deliberately minimal: it bakes the identical raster the widget bakes, then
/// draws it with a destination rounded in the space it is painting into rather
/// than against the screen. If the engine puts the enclosing layer on the grid
/// itself, this is the placement that lands whole and the shipped one
/// over-corrects by the layer's own fraction.
class _LocalSnapAvatar extends StatefulWidget {
  const _LocalSnapAvatar({required this.ratio, this.global = false});

  final double ratio;
  final bool global;

  @override
  State<_LocalSnapAvatar> createState() => _LocalSnapAvatarState();
}

class _LocalSnapAvatarState extends State<_LocalSnapAvatar> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _bake();
  }

  Future<void> _bake() async {
    final image = await rasterAvatarImage(
      name: '박기현',
      colors: _palette,
      pixels: (_size * widget.ratio).round(),
      version: BoringAvatarsVersion.v1_7_0,
      variant: BoringAvatarsVariant.marble,
      square: false,
    );
    if (mounted) setState(() => _image = image);
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return SizedBox(
      width: _size,
      height: _size,
      child: image == null
          ? null
          : _LocalSnapImage(
              image: image,
              ratio: widget.ratio,
              global: widget.global,
            ),
    );
  }
}

class _LocalSnapImage extends LeafRenderObjectWidget {
  const _LocalSnapImage({
    required this.image,
    required this.ratio,
    this.global = false,
  });

  final ui.Image image;
  final double ratio;
  final bool global;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLocalSnapImage(image, ratio, global);

  @override
  void updateRenderObject(BuildContext context, _RenderLocalSnapImage r) {
    r.image = image;
  }
}

class _RenderLocalSnapImage extends RenderBox {
  _RenderLocalSnapImage(this._image, this._ratio, this._global);

  ui.Image _image;
  final double _ratio;
  final bool _global;

  set image(ui.Image value) {
    _image = value;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    double onGrid(double v) => (v * _ratio).roundToDouble() / _ratio;
    late final Offset topLeft;
    if (_global) {
      // `0.3.1`: correct by what the *screen* position needs, applied in the
      // space the canvas is in.
      final g = localToGlobal(Offset.zero);
      double correction(double at) => at.isFinite ? onGrid(at) - at : 0;
      topLeft = Offset(
        offset.dx + correction(g.dx),
        offset.dy + correction(g.dy),
      );
    } else {
      topLeft = Offset(onGrid(offset.dx), onGrid(offset.dy));
    }
    final destination = Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      onGrid(size.width),
      onGrid(size.height),
    );
    context.canvas.drawImageRect(
      _image,
      Rect.fromLTWH(0, 0, _image.width.toDouble(), _image.height.toDouble()),
      destination,
      Paint()
        ..isAntiAlias = false
        ..filterQuality = FilterQuality.none,
    );
  }
}
