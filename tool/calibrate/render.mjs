// Renders a scene in real Chrome and dumps the pixels, for the layer-3 parity
// calibration described in docs/agents/theflow.md (Step 4).
//
// This is a TOOL, not a gate. `flutter test` never runs it. A zero-tolerance
// gate against Chrome is a gate that fails when *Chrome* changes and our code
// has not — and theflow forbids relaxing a threshold to clear a red run, so it
// would deadlock. The committed goldens are the regression gate; this is the
// outside opinion, run deliberately when the rasterizer changes.
//
//   node tool/calibrate/render.mjs <out-dir>
//
// Writes <out-dir>/<case>.rgba — straight RGBA, four bytes a pixel, row-major,
// exactly the layout lib/src/raster/raster.dart produces.
import { execFileSync } from 'node:child_process';
import { inflateSync } from 'node:zlib';
import { mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';

const CHROME =
  process.env.CHROME ?? 'C:/Program Files/Google/Chrome/Application/chrome.exe';

const outDir = process.argv[2];
if (!outDir) {
  console.error('usage: node tool/calibrate/render.mjs <out-dir>');
  process.exit(2);
}

/**
 * The scenes to calibrate, as the SVG our emitter produces.
 *
 * They are pasted from `emitSvg(...)` output rather than regenerated here: the
 * point of the comparison is that Chrome and our rasterizer are fed the *same
 * document*, so the document has to come from one place.
 */
const cases = JSON.parse(readFileSync(join(outDir, 'scenes.json'), 'utf8'));

/** Decodes a non-interlaced 8-bit RGBA PNG to straight RGBA bytes. */
function decodePng(buffer) {
  if (buffer.readUInt32BE(0) !== 0x89504e47) throw new Error('not a PNG');
  let offset = 8;
  let width = 0;
  let height = 0;
  let bitDepth = 0;
  let colourType = 0;
  const idat = [];

  while (offset < buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString('ascii', offset + 4, offset + 8);
    const data = buffer.subarray(offset + 8, offset + 8 + length);
    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8];
      colourType = data[9];
      if (data[12] !== 0) throw new Error('interlaced PNG is not supported');
    } else if (type === 'IDAT') {
      idat.push(data);
    } else if (type === 'IEND') {
      break;
    }
    offset += length + 12;
  }

  if (bitDepth !== 8 || (colourType !== 6 && colourType !== 2)) {
    throw new Error(`unsupported PNG: depth ${bitDepth} colour ${colourType}`);
  }
  const channels = colourType === 6 ? 4 : 3;
  const raw = inflateSync(Buffer.concat(idat));
  const stride = width * channels;
  const out = Buffer.alloc(width * height * 4);
  let previous = Buffer.alloc(stride);

  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const line = Buffer.from(
      raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1)),
    );
    for (let i = 0; i < stride; i++) {
      const a = i >= channels ? line[i - channels] : 0;
      const b = previous[i];
      const c = i >= channels ? previous[i - channels] : 0;
      switch (filter) {
        case 0:
          break;
        case 1:
          line[i] = (line[i] + a) & 0xff;
          break;
        case 2:
          line[i] = (line[i] + b) & 0xff;
          break;
        case 3:
          line[i] = (line[i] + ((a + b) >> 1)) & 0xff;
          break;
        case 4: {
          const p = a + b - c;
          const pa = Math.abs(p - a);
          const pb = Math.abs(p - b);
          const pc = Math.abs(p - c);
          const pred = pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
          line[i] = (line[i] + pred) & 0xff;
          break;
        }
        default:
          throw new Error(`unknown PNG filter ${filter}`);
      }
    }
    for (let x = 0; x < width; x++) {
      out[(y * width + x) * 4 + 0] = line[x * channels + 0];
      out[(y * width + x) * 4 + 1] = line[x * channels + 1];
      out[(y * width + x) * 4 + 2] = line[x * channels + 2];
      out[(y * width + x) * 4 + 3] =
        channels === 4 ? line[x * channels + 3] : 255;
    }
    previous = line;
  }
  return { width, height, bytes: out };
}

mkdirSync(outDir, { recursive: true });

for (const [name, { svg, size }] of Object.entries(cases)) {
  // A bare .svg file gets a UA stylesheet and a scrollbar; an HTML wrapper with
  // zeroed margins does not. The viewport is exactly the drawing.
  const html = `<!doctype html><meta charset="utf-8"><style>
html,body{margin:0;padding:0;background:transparent;overflow:hidden}
svg{display:block}
</style>${svg}`;
  const page = join(outDir, `${name}.html`);
  const png = join(outDir, `${name}.png`);
  writeFileSync(page, html);

  execFileSync(
    CHROME,
    [
      '--headless',
      '--disable-gpu',
      '--hide-scrollbars',
      '--force-device-scale-factor=1',
      '--default-background-color=00000000',
      `--window-size=${size},${size}`,
      `--screenshot=${png}`,
      `file:///${page.replace(/\\/g, '/')}`,
    ],
    { stdio: 'pipe' },
  );

  const image = decodePng(readFileSync(png));
  if (image.width !== size || image.height !== size) {
    throw new Error(
      `${name}: Chrome produced ${image.width}x${image.height}, wanted ${size}`,
    );
  }
  writeFileSync(join(outDir, `${name}.rgba`), image.bytes);
  rmSync(page);
  rmSync(png);
  console.log(`${name}: ${image.width}x${image.height} from Chrome`);
}
