// The #117 differential, on a **real engine**.
//
// **What it is measuring, and why it is a differential rather than a golden.**
// #117 reports that an avatar drawn inside an anti-aliased rounded clip is
// resampled — a fold across a smooth gradient — while the same avatar in the
// same frame outside that clip is not. The widget's own box is already snapped
// (ADR-0002 R1, and #117's own probe reports `frac=(0.0, 0.0)` on the axis that
// still looked wrong), so nothing about the avatar's placement distinguishes the
// two. Only the ancestor does.
//
// A stored golden cannot hold this. The condition needs `devicePixelRatio` to be
// something other than 1, and a golden captured on a 100% machine passes
// everywhere while entering the condition nowhere — `lessons.md`'s standing rule
// that a harness which never ran in the condition cannot have cleared it. So the
// fixture puts the clipped and the unclipped avatar in **one frame** and
// compares them **to each other**, and the sizes come off the ratio.
//
// **The assertion is structural, not perceptual.** Nearest-neighbour resampling
// of a buffer that is already the box's physical size shows up as adjacent
// **identical** columns or rows — a column duplicated where the sampler landed
// twice on the same source pixel. Counting those needs no reference image and no
// tolerance: the unclipped avatar's count is the expectation, and it is zero.
//
// **Measured 2026-08-18, Windows, ratio 1.5: the clip is not the condition.**
// Five cells — no ancestor; an anti-aliased rounded clip on the canvas path; the
// same clip forced onto a real `ClipRRectLayer` by a compositing sibling; the
// same with a `RepaintBoundary` around the avatar; and that one at a whole-pixel
// origin — every one of them came back `66x66` with **zero** duplicated columns
// and rows. #117's suspected root is falsified on this engine, and the cells are
// kept as the control that says so.
//
// **What the clip taught on the way, and it is worth keeping.** `PaintingContext.pushClipRRect` has two paths: with
// `needsCompositing` false it clips the canvas and paints in place, and only
// with it true does it push a real `ClipRRectLayer` — an offscreen the subtree
// is rasterised into and then composited somewhere. A clip with nothing
// compositing inside it therefore never produces the buffer this defect needs.
// That is very likely why #117's own standalone ladder — which rebuilt the app's
// clip and containers but nothing that forces compositing — could not reproduce
// it. It is also why the clip cells below vary *what forces the layer* rather
// than only whether a clip is present: without that axis a clean run would have
// proved nothing at all.
//
// **The live condition is a scroll viewport**, reported from the app after the
// clip came back clean. ADR-0002 R4 already names the mechanism and accepts it —
// alignment is computed while painting, and a layer can move without its child
// repainting — with #110's measurement beside it: after a 7.3-logical scroll at
// ratio 1.5 the destination was 11.2 device pixels stale. What R4 does *not* say
// is what that costs in pixels, and these cells are that measurement.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:boring_avatars/boring_avatars.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The page and the clipped container share one colour, so "ink" is anything
/// that is not it — inside the clip and outside it alike.
const _ground = Color(0xFF1A1A21);

/// #117's palette. **Low contrast on purpose**: the report measured that a fold
/// hides inside a high-contrast transition the eye already reads as an edge, so
/// a vivid palette would make this fixture pass while the defect was present.
const _palette = ['#C9B8FD', '#3B7BF0', '#2E33A0'];

/// What forces the clip to become a compositing layer, if anything.
enum _Compositing {
  /// Nothing does. The clip takes the canvas path and no offscreen exists.
  none,

  /// The avatar gets its own retained layer — the consumer's workaround, and
  /// what #117 measurement 4 reports as *not sufficient* at a fractional offset.
  boundary,

  /// Something *else* inside the clip composites, so the avatar is rasterised
  /// into an offscreen it does not own. This is the shape the reporting app has.
  sibling,
}

typedef _Cell = ({
  String label,
  bool clipped,
  _Compositing compositing,
  bool halfPixel,
});

const _cells = <_Cell>[
  (
    label: 'plain      ',
    clipped: false,
    compositing: _Compositing.none,
    halfPixel: true,
  ),
  (
    label: 'clip       ',
    clipped: true,
    compositing: _Compositing.none,
    halfPixel: true,
  ),
  (
    label: 'clip+layer ',
    clipped: true,
    compositing: _Compositing.sibling,
    halfPixel: true,
  ),
  (
    label: 'clip+rb    ',
    clipped: true,
    compositing: _Compositing.boundary,
    halfPixel: true,
  ),
  (
    label: 'clip+rb@int',
    clipped: true,
    compositing: _Compositing.boundary,
    halfPixel: false,
  ),
];

/// Logical inset from the clip's own edge to the avatar's box.
const _pad = 11.0;

/// The clip is narrower than what it holds, so it genuinely cuts.
const _clipWidth = 200.0;
const _innerWidth = 400.0;

/// Vertical room per cell, logical.
const _band = 110.0;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a clipped avatar is drawn from the same pixels as an unclipped '
      'one', (tester) async {
    final ratio = tester.view.devicePixelRatio;

    // **The box is a whole number of device pixels on purpose.** #110's residual
    // — a buffer one pixel wider than a fractional box — is a different defect
    // in the same neighbourhood, and letting it in here would make a failure
    // ambiguous. 66 device pixels is 44 logical at 150%, the size #117 measured.
    const deviceSide = 66.0;
    final size = deviceSide / ratio;

    // Where the avatar's own box lands, in device pixels. Half past an integer
    // in every cell but the last.
    const halfPixel = 52.5;
    const whole = 54.0;
    double leftFor(_Cell cell) =>
        ((cell.halfPixel ? halfPixel : whole) / ratio) -
        (cell.clipped ? _pad : 0);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: const ValueKey('boundary'),
          child: ColoredBox(
            color: _ground,
            child: Stack(
              children: [
                for (var i = 0; i < _cells.length; i++)
                  Positioned(
                    left: leftFor(_cells[i]),
                    top: 10 + i * _band,
                    child: _wrap(
                      _cells[i],
                      size,
                      BoringAvatar(
                        name: '박기현',
                        colors: _palette,
                        size: size,
                        version: BoringAvatarsVersion.v1_7_0,
                        variant: BoringAvatarsVariant.marble,
                        // The extent is read off colour, and a disc's topmost row
                        // can quantise to no coverage at all — the same reason
                        // `pixel_snap_test.dart` squares its avatar.
                        square: true,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('boundary')),
    );

    // The raster is asynchronous and this binding is real, so pump until every
    // cell has arrived rather than assuming a frame count.
    List<_Band>? bands;
    for (var attempt = 0; attempt < 200 && bands == null; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      final shot = await boundary.toImage(pixelRatio: ratio);
      final data = await shot.toByteData(format: ui.ImageByteFormat.rawRgba);
      final read = _read(
        data!.buffer.asUint8List(),
        shot.width,
        shot.height,
        (_band * ratio).round(),
      );
      shot.dispose();
      if (read.length == _cells.length) bands = read;
    }

    expect(
      bands,
      isNotNull,
      reason:
          'not every cell arrived; with nothing to compare the run says nothing',
    );

    for (var i = 0; i < _cells.length; i++) {
      debugPrint(
        'CLIPRESAMPLE ratio=$ratio ${_cells[i].label} '
        'box=${bands![i].width}x${bands[i].height} '
        'at (${bands[i].left}, ${bands[i].top}) '
        'dupCols=${bands[i].duplicateColumns} '
        'dupRows=${bands[i].duplicateRows}',
      );
    }

    final plain = bands![0];

    expect(
      plain.duplicateColumns + plain.duplicateRows,
      0,
      reason:
          'the unclipped avatar is the expectation and it must be clean; a '
          'non-zero count here means the fixture, not the ancestor, is '
          'resampling',
    );

    for (var i = 1; i < _cells.length; i++) {
      expect(
        (bands[i].duplicateColumns, bands[i].duplicateRows),
        (plain.duplicateColumns, plain.duplicateRows),
        reason:
            'cell "${_cells[i].label.trim()}": the same buffer, in the same '
            'frame, at the same box origin — an ancestor must not change which '
            'pixels reach the screen (#117)',
      );
    }
  });
}

/// The ancestors under test.
///
/// **The clip is bounded and its child overflows it**, because a clip whose
/// child fits inside has nothing to cut, and an unbounded one is `Infinity` —
/// the first version of this fixture was the second mistake and painted `NaN`.
Widget _wrap(_Cell cell, double size, Widget avatar) {
  final placed = Align(
    alignment: Alignment.topLeft,
    child: cell.compositing == _Compositing.boundary
        ? RepaintBoundary(child: avatar)
        : avatar,
  );

  if (!cell.clipped) return placed;

  final clipHeight = size + _pad * 2;
  Widget inner = SizedBox(
    width: _innerWidth,
    height: clipHeight,
    child: ColoredBox(
      color: _ground,
      child: Padding(padding: const EdgeInsets.all(_pad), child: placed),
    ),
  );

  // A compositing sibling: the avatar is painted into an offscreen it does not
  // own, which is the arrangement the reporting app has and the one a
  // `RepaintBoundary` around the avatar cannot undo.
  if (cell.compositing == _Compositing.sibling) {
    inner = Opacity(opacity: 0.99, child: inner);
  }

  return SizedBox(
    width: _clipWidth,
    height: clipHeight,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: inner,
      ),
    ),
  );
}

/// One cell's drawing, as measured off the captured pixels.
typedef _Band = ({
  int left,
  int top,
  int width,
  int height,
  int duplicateColumns,
  int duplicateRows,
});

/// Finds each cell's ink inside its own horizontal band and counts the adjacent
/// identical columns and rows in it.
///
/// **Identical, not similar.** A duplicated column is a byte-for-byte copy of
/// its neighbour, which a smooth gradient never produces on its own; using a
/// tolerance here would start reporting the gradient itself.
List<_Band> _read(Uint8List bytes, int width, int height, int bandDevice) {
  int at(int x, int y, int k) => bytes[(y * width + x) * 4 + k];
  bool ink(int x, int y) =>
      (at(x, y, 0) - 0x1A).abs() +
          (at(x, y, 1) - 0x1A).abs() +
          (at(x, y, 2) - 0x21).abs() >
      6;

  final bands = <_Band>[];
  for (var band = 0; band * bandDevice < height; band++) {
    final from = band * bandDevice;
    final to = ((band + 1) * bandDevice).clamp(0, height);
    var minX = width, maxX = -1, minY = to, maxY = -1;
    for (var y = from; y < to; y++) {
      for (var x = 0; x < width; x++) {
        if (!ink(x, y)) continue;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    if (maxX < 0) continue;

    var dupCols = 0, dupRows = 0;
    for (var x = minX + 1; x <= maxX; x++) {
      var same = true;
      for (var y = minY; y <= maxY && same; y++) {
        for (var k = 0; k < 4; k++) {
          if (at(x, y, k) != at(x - 1, y, k)) {
            same = false;
            break;
          }
        }
      }
      if (same) dupCols++;
    }
    for (var y = minY + 1; y <= maxY; y++) {
      var same = true;
      for (var x = minX; x <= maxX && same; x++) {
        for (var k = 0; k < 4; k++) {
          if (at(x, y, k) != at(x, y - 1, k)) {
            same = false;
            break;
          }
        }
      }
      if (same) dupRows++;
    }

    bands.add((
      left: minX,
      top: minY,
      width: maxX - minX + 1,
      height: maxY - minY + 1,
      duplicateColumns: dupCols,
      duplicateRows: dupRows,
    ));
  }
  return bands;
}
