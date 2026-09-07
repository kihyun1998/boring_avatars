// Writes the images the README shows.
//
//   dart run tool/readme/generate.dart
//
// **They are drawn by this package's own rasterizer, not by a browser.** A
// screenshot taken from Chrome would show what upstream draws; these show what
// `BoringAvatar` puts on screen, which is the thing the README is claiming. The
// two agree — that is what `tool/calibrate` measures — but only one of them is
// evidence for the sentence next to it.
//
// Deterministic, so re-running with no source change rewrites the same bytes
// and `git status` stays clean. Run it deliberately when the rasterizer or the
// roster below changes, and review the diff like any other committed artifact.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:boring_avatars/src/avatar.dart';
import 'package:boring_avatars/src/raster/raster.dart';
import 'package:boring_avatars/src/raster/scene_raster.dart';
import 'package:boring_avatars/src/variant.dart';
import 'package:boring_avatars/src/version.dart';

/// Upstream's own default palette — the one a reader gets by copying the
/// README's first snippet, so the gallery has to be drawn with it.
const _palette = ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'];

/// The name every gallery avatar is drawn from. Upstream's default too, which
/// makes the images checkable against `boring-avatars`' own site by eye.
const _name = 'Clara Barton';

/// 256 rather than 80: the README displays these at about 120 CSS pixels, and a
/// 2x screen asks for 240. Rendering at the display size and letting the
/// browser upscale would show the browser's sampler, not this rasterizer's
/// edges.
const _size = 256;

void main() {
  final dir = Directory('docs/images')..createSync(recursive: true);

  for (final variant in BoringAvatarsVariant.values) {
    // The two deprecated aliases resolve to variants already in the list —
    // drawing them would write a second copy of `beam` under another name.
    if (variant.resolved != variant) continue;

    final scene = buildAvatarScene(
      name: _name,
      colors: _palette,
      size: _size,
      version: BoringAvatarsVersion.latest,
      variant: variant,
      square: false,
      title: null,
    );
    final image = rasterizeScene(scene, width: _size, height: _size);
    final path = '${dir.path}/variant-${variant.name}.png';
    File(path).writeAsBytesSync(_encodePng(image));
    stdout.writeln('wrote $path');
  }
}

/// The minimum PNG that carries straight-alpha RGBA: one `IHDR`, one `IDAT`,
/// one `IEND`.
///
/// Written here rather than pulled in as a dependency because the package has
/// none and a README tool is not a reason to acquire one. [RasterImage.bytes]
/// is already 8-bit straight-alpha RGBA in row order, which is colour type 6
/// exactly — so the encoder's whole job is the per-row filter byte, `zlib`, and
/// the chunk framing.
Uint8List _encodePng(RasterImage image) {
  final raw = BytesBuilder(copy: false);
  final stride = image.width * 4;
  for (var y = 0; y < image.height; y++) {
    // Filter 0 (None). A predictive filter would compress better; this file is
    // read by a browser, not by a budget.
    raw.addByte(0);
    raw.add(Uint8List.sublistView(image.bytes, y * stride, (y + 1) * stride));
  }

  final ihdr = BytesBuilder(copy: false)
    ..add(_be32(image.width))
    ..add(_be32(image.height))
    ..addByte(8) // bit depth
    ..addByte(6) // colour type: truecolour with alpha
    ..addByte(0) // deflate
    ..addByte(0) // adaptive filtering
    ..addByte(0); // no interlace

  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
    ..._chunk('IHDR', ihdr.takeBytes()),
    ..._chunk('IDAT', ZLibEncoder().convert(raw.takeBytes())),
    ..._chunk('IEND', const []),
  ]);
}

List<int> _chunk(String type, List<int> data) {
  final typed = [...ascii.encode(type), ...data];
  return [..._be32(data.length), ...typed, ..._be32(_crc32(typed))];
}

List<int> _be32(int v) => [
  (v >> 24) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 8) & 0xFF,
  v & 0xFF,
];

/// The CRC-32 the PNG specification names (§5, the reflected polynomial
/// `0xEDB88320`), table built on first use.
final List<int> _crcTable = List.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}
