// Does upstream 1.6.1 really ignore a `title` prop?
//
//   node tool/parity/probe-title-1-6-1.mjs
//
// This package **throws** on `title: false` at `v1_6_1`, and the reason given
// in `avatar.dart`, README and CHANGELOG is that upstream would ignore the
// request and leave the caller believing the element was gone. That sentence
// was written from *reading* 1.6.1's source — `avatar.js` spreads unknown props
// into `avatarProps` and the components read `props.size` explicitly rather
// than spreading onto `<svg>`.
//
// Reading the code is not observing what it does, and 1.11.0 exists precisely
// because upstream once *did* leak its props onto the `<svg>` element. So the
// claim is measured here rather than reasoned: if a `title` prop changed a
// single byte of 1.6.1's output, the justification would be false and the
// package would be throwing for a reason that does not hold.
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

const Avatar = await import('upstream-1.6.1').then(
  (m) => m.default?.default ?? m.default,
);

const PALETTE = ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'];
const VARIANTS = ['marble', 'beam', 'pixel', 'sunset', 'ring', 'bauhaus'];

let same = 0;
const differences = [];

for (const variant of VARIANTS) {
  const base = renderToStaticMarkup(
    React.createElement(Avatar, {
      variant,
      name: 'Clara Barton',
      colors: PALETTE,
      size: 80,
    }),
  );
  // `false` is the case the package refuses; `true` and a string are here
  // because React treats an unknown prop's *type* differently when deciding
  // whether to serialise it as an attribute.
  for (const title of [false, true, 'x']) {
    const withTitle = renderToStaticMarkup(
      React.createElement(Avatar, {
        variant,
        name: 'Clara Barton',
        colors: PALETTE,
        size: 80,
        title,
      }),
    );
    if (withTitle === base) {
      same++;
    } else {
      differences.push({ variant, title, sample: withTitle.slice(0, 200) });
    }
  }
}

for (const d of differences) {
  console.log(`  다름: ${d.variant} title=${JSON.stringify(d.title)}`);
  console.log(`        ${d.sample}`);
}
console.log(
  `\n  1.6.1 에 title 을 넘긴 렌더 ${same + differences.length}건 중 ` +
    `${same}건이 넘기지 않은 것과 바이트 동일, ${differences.length}건 다름.`,
);
process.exit(differences.length === 0 ? 0 : 1);
