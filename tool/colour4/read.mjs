// Reads the strip back: one line per swatch, centre pixel of each 8x8 cell.
//   node tool/colour4/read.mjs <work-dir>
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const dir = process.argv[2];
if (!dir) {
  console.error('usage: node tool/colour4/read.mjs <work-dir>');
  process.exit(2);
}
const values = JSON.parse(readFileSync(join(dir, 'values.json')));
const rgba = readFileSync(join(dir, 'c4.rgba'));
const width = values.length * 8;
values.forEach((v, i) => {
  const x = i * 8 + 4, y = 4;
  const o = (y * width + x) * 4;
  console.log(`${String(i).padStart(2)}  [${rgba[o]},${rgba[o + 1]},${rgba[o + 2]},${rgba[o + 3]}]  ${v}`);
});
