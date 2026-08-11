// System colours via getComputedStyle — exact values, no PNG rounding.
import { chromium } from 'playwright-core';

const current = ['Canvas','CanvasText','LinkText','VisitedText','ActiveText',
  'ButtonFace','ButtonText','ButtonBorder','Field','FieldText','Highlight',
  'HighlightText','SelectedItem','SelectedItemText','Mark','MarkText',
  'GrayText','AccentColor','AccentColorText'];
const deprecated = ['ActiveBorder','ActiveCaption','AppWorkspace','Background',
  'ButtonHighlight','ButtonShadow','CaptionText','InactiveBorder',
  'InactiveCaption','InactiveCaptionText','InfoBackground','InfoText','Menu',
  'MenuText','Scrollbar','ThreeDDarkShadow','ThreeDFace','ThreeDHighlight',
  'ThreeDLightShadow','ThreeDShadow','Window','WindowFrame','WindowText'];
// Discriminating none-components and a lab comma form, resolved the same way.
const extra = ['lab(none 50 0)', 'rgb(none 128 0)', 'oklch(0.7 none 30)',
  'lab(50%, 40, 59.5)', 'hwb(120 30% 20%)'];

const browser = await chromium.launch({ channel: 'chrome' });
const page = await browser.newPage({ colorScheme: 'light' });
await page.setContent('<div id="p"></div>');
const resolve = (v) => page.evaluate((val) => {
  const el = document.getElementById('p');
  el.style.color = '';
  el.style.color = val;
  if (el.style.color === '' && val !== '') return 'REFUSED';
  return getComputedStyle(el).color;
}, v);
console.log('# current');
for (const v of current) console.log(`${v}\t${await resolve(v)}`);
console.log('# deprecated');
for (const v of deprecated) console.log(`${v}\t${await resolve(v)}`);
console.log('# extra');
for (const v of extra) console.log(`${v}\t${await resolve(v)}`);
console.log('# version\t' + browser.version());
await browser.close();
