// Groups upstream releases by **what a caller actually gets**, which is the
// criterion the release plan rests on (CLAUDE.md, principle 3).
//
//   cd tool/versions && npm install && npm run group
//
// This exists because the plan is a claim about measurement — "these versions
// produce the same thing" — and a claim whose evidence cannot be re-run is a
// claim nobody can check. The grouping was first measured in a throwaway
// directory; this is that probe made permanent, the same way tool/parity is.
//
// A TOOL, not a gate. `flutter test` is hermetic and never runs Node.
//
// `1.8.0` and `1.9.0` are absent on purpose: their npm tarballs contain no
// JavaScript at all (`main` points at `build/index.js`, which is not in the
// package), so there is nothing to render. They sit inside `1.10.0`'s group by
// source — the git trees for 1.8.0, 1.9.0 and 1.10.0 are the same blob.
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

const VERSIONS = [
  ['v1_6_1', '1.6.1'], ['v1_6_2', '1.6.2'], ['v1_6_3', '1.6.3'],
  ['v1_7_0', '1.7.0'], ['v1_10_0', '1.10.0'],
  ['v1_10_1', '1.10.1'], ['v1_10_2', '1.10.2'],
  ['v1_11_0', '1.11.0'], ['v1_11_1', '1.11.1'], ['v1_11_2', '1.11.2'],
  ['v2_0_0', '2.0.0'], ['v2_0_1', '2.0.1'], ['v2_0_2', '2.0.2'],
  ['v2_0_3', '2.0.3'], ['v2_0_4', '2.0.4'],
];
const VARIANTS = ['marble', 'beam', 'pixel', 'sunset', 'ring', 'bauhaus'];
const NAMES = ['Clara Barton', '박기현', 'a', ''];
const PALETTE = ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'];

/** Internal references — they name nothing the reader sees. */
const withoutIds = (svg) =>
  svg
    .replace(/id="[^"]*"/g, 'id="_"')
    .replace(/url\(#[^)]*\)/g, 'url(#_)')
    .replace(/mask="[^"]*"/g, 'mask="_"')
    .replace(/filter="[^"]*"/g, 'filter="_"');

const withoutTitle = (svg) =>
  withoutIds(svg).replace(/<title>.*?<\/title>/g, '');

const modules = {};
for (const [alias] of VERSIONS) {
  const m = await import(alias);
  modules[alias] = m.default?.default ?? m.default;
}

function renderAll(alias, extra) {
  const Avatar = modules[alias];
  const out = [];
  for (const variant of VARIANTS) {
    for (const name of NAMES) {
      try {
        out.push(renderToStaticMarkup(React.createElement(Avatar, {
          variant, name, colors: PALETTE, size: 80, ...extra,
        })));
      } catch (e) {
        out.push('THROWS:' + (e?.constructor?.name ?? 'Error'));
      }
    }
  }
  return out.join('\n');
}

function group(label, project, extra = {}) {
  const buckets = [];
  for (const [alias, version] of VERSIONS) {
    const key = project(renderAll(alias, extra));
    const hit = buckets.find((b) => b.key === key);
    if (hit) hit.members.push(version);
    else buckets.push({ key, members: [version] });
  }
  console.log('\n' + label);
  console.log('-'.repeat(72));
  buckets.forEach((b, i) =>
    console.log(`  그룹 ${i + 1}  ${b.members.join(', ')}`));
  console.log(`  => ${buckets.length}개 그룹`);
  return buckets;
}

console.log('상류 릴리스를 "호출자가 받는 것" 기준으로 묶습니다.');
console.log(`${VERSIONS.length}개 버전 × ${VARIANTS.length}개 variant × ${NAMES.length}개 이름.`);

group('① 원문 그대로', (s) => s);
group('② 내부 id 만 정규화', withoutIds);
const drawn = group('③ id + <title> 정규화 — 순수하게 그려지는 것', withoutTitle);
group('④ id 정규화, title 을 켜서 렌더', withoutIds, { title: true });

// The boundary the plan turns on: is it one variant wide?
console.log('\n⑤ 그룹 경계가 어느 variant 때문인가');
console.log('-'.repeat(72));
for (let i = 1; i < drawn.length; i++) {
  const a = drawn[i - 1].members.at(-1);
  const b = drawn[i].members[0];
  const aliasOf = (v) => VERSIONS.find(([, ver]) => ver === v)[0];
  const differing = VARIANTS.filter((variant) =>
    NAMES.some((name) => {
      const props = { variant, name, colors: PALETTE, size: 80 };
      return withoutTitle(renderToStaticMarkup(React.createElement(modules[aliasOf(a)], props)))
        !== withoutTitle(renderToStaticMarkup(React.createElement(modules[aliasOf(b)], props)));
    }));
  console.log(`  ${a} → ${b}:  ${differing.length ? differing.join(', ') : '(그림 차이 없음)'}`);
}

console.log('\n결과가 CLAUDE.md 원칙 3 의 표와 맞는지 확인하세요.');
console.log('1.11.0 이 혼자 떨어져 나오는 것이 정상입니다 — props 를 <svg> 속성으로 흘립니다.');
