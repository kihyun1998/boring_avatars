// Renders the GitHub milestone descriptions from CLAUDE.md's release table.
//
//   node tool/milestones/sync.mjs           # show what would change
//   node tool/milestones/sync.mjs --apply   # write it
//
// **Why this exists.** The release-to-version mapping has one home: CLAUDE.md,
// principle 3. A milestone description needs the version list in it — "see
// CLAUDE.md" is useless to someone browsing GitHub — so the fact is in two
// places whether we like it or not. Generating one from the other is what stops
// them drifting: the mapping is derived, and re-running this is the correction.
//
// **What is NOT derived.** Each release also carries a sentence that is a
// product judgement rather than a fact about versions — what ships in it, why a
// version was excluded. Those are authored, and they live in NOTES below rather
// than in the milestone, so this tool can rewrite a description without
// destroying them. One home each: the mapping in CLAUDE.md, the note here.
//
// A TOOL, not a gate. `flutter test` is hermetic and never reaches the network.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const REPO = 'kihyun1998/boring_avatars';
const apply = process.argv.includes('--apply');

/** Authored, not derived — see the header. Keyed by release. */
const NOTES = {
  '0.1.0': '6개 variant 전부 + SVG 문자열 공개. 위젯과 픽셀 출력은 다음 릴리스.',
  '0.2.0': '바뀌는 것은 `<title>` 하나 — 그림은 0.1.0 과 동일.',
  '0.3.0':
    '바뀌는 것은 `pixel` 색 인덱스 하나. **1.11.0 은 제외** — 자기 props 를 ' +
    '`<svg>` 속성으로 흘리는 버그 버전이고, 상류가 1.11.1 에서 고쳤습니다.',
};

/** The rows of principle 3's table: release, selector, covered versions. */
function readReleaseTable() {
  const md = readFileSync('CLAUDE.md', 'utf8');
  const rows = [];
  for (const line of md.split('\n')) {
    const m = /^\s*\|\s*`(\d+\.\d+\.\d+)`\s*\|\s*`(\w+)`\s*\|\s*([^|]+?)\s*\|/.exec(line);
    if (m) rows.push({ release: m[1], selector: m[2], versions: m[3] });
  }
  if (rows.length === 0) {
    throw new Error(
      'CLAUDE.md 에서 릴리스 표를 찾지 못했습니다. ' +
        '표 형식이 바뀌었다면 이 파서도 함께 고쳐야 합니다.',
    );
  }
  return rows;
}

function describe({ release, selector, versions }) {
  const covered = versions.replace(/,\s*/g, ' / ').replace(/\s*–\s*/g, ' ~ ');
  const note = NOTES[release];
  if (!note) {
    throw new Error(`${release} 의 설명 문장이 NOTES 에 없습니다 — 추가하세요.`);
  }
  return (
    `상류 ${covered} 지원 (선택자 \`${selector}\`). ${note} ` +
    `— 버전 목록은 CLAUDE.md 원칙 3 에서 생성됨 (tool/milestones/sync.mjs)`
  );
}

const gh = (args) => execFileSync('gh', args, { encoding: 'utf8' }).trim();

const milestones = JSON.parse(
  gh(['api', `repos/${REPO}/milestones`, '--paginate']),
);
const byTitle = new Map(milestones.map((m) => [m.title, m]));
const table = readReleaseTable();

let changed = 0;
for (const row of table) {
  // `describe` first, so a release added to CLAUDE.md without a note here
  // fails loudly. Checking the milestone first would skip past it — and a new
  // release is exactly the case where the milestone does not exist yet, so the
  // check that matters would never run.
  const wanted = describe(row);
  const milestone = byTitle.get(row.release);
  if (!milestone) {
    console.log(`  ${row.release}  마일스톤이 없습니다 — 만들어야 합니다`);
    console.log(`    설명: ${wanted}`);
    changed++;
    continue;
  }
  if (milestone.description === wanted) {
    console.log(`  ${row.release}  이미 일치`);
    continue;
  }
  changed++;
  console.log(`\n  ${row.release}  다름`);
  console.log(`    현재: ${milestone.description || '(비어 있음)'}`);
  console.log(`    생성: ${wanted}`);
  if (apply) {
    gh([
      'api', '-X', 'PATCH', `repos/${REPO}/milestones/${milestone.number}`,
      '-f', `description=${wanted}`, '--jq', '.title',
    ]);
    console.log('    → 반영함');
  }
}

// A milestone with no row in the table is a release the plan no longer has —
// the drift this tool cannot fix by writing, only by reporting.
for (const m of milestones) {
  if (!table.some((r) => r.release === m.title)) {
    console.log(
      `\n  ${m.title}  CLAUDE.md 의 표에 없는 마일스톤입니다 — ` +
        '계획에서 빠진 것인지 확인하세요',
    );
    changed++;
  }
}

if (!apply && changed > 0) console.log('\n  --apply 를 붙이면 반영합니다.');
if (changed === 0) console.log('\n  전부 일치합니다.');
