// The upstream watcher's impure half — it talks to GitHub, reads and writes
// last-seen.json, and files the issue. The judgement lives next door in
// diff.mjs, which is pure and tested.
//
//   node tool/watch/upstream.mjs                     # dry run: what would happen
//   node tool/watch/upstream.mjs --apply             # file the issue, then save state
//   node tool/watch/upstream.mjs --ref=main          # watch a different branch
//   node tool/watch/upstream.mjs --replay=v2.0.0..v2.0.1
//
// **`--replay` is the fourth acceptance criterion of #51**, and it is a real
// replay rather than an analogy: a subtree SHA from `git rev-parse
// <tag>:src/lib` in the pinned reference tree is byte-identical to the one
// GitHub's tree API returns for the same subtree — measured on
// `origin/master`, both `5790e5c5c9ef37af044d644eb75c48f200e5a7bd`. So the
// numbers fed to `diffTrees` under `--replay` are the numbers the scheduled
// run would have seen on the day that tag was pushed.
//
// **Order of operations, and why it is not the other one.** On `--apply` the
// issue is filed *first* and the state written *second*. If the state write
// fails after the issue is filed, the next run files a duplicate — loud,
// visible, and undone with one `gh issue close`. The reverse order fails the
// other way: the state advances, the issue never appears, and the upstream
// change is swallowed permanently with nothing anywhere saying so. Between a
// recoverable duplicate and a silent loss, the watcher takes the duplicate.
// The title carries the tree SHA and is checked against existing issues, so
// the duplicate is usually prevented outright.
//
// A TOOL, not a gate — see tool/watch/README.md.
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { UPSTREAM, diffTrees, renderIssue } from './diff.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const STATE_PATH = resolve(HERE, 'last-seen.json');
/** The pinned reference tree — a sibling of this repo, per theflow Step 1. */
const REFS = resolve(HERE, '..', '..', '..', '.refs', 'boring-avatars');

const REPO = 'kihyun1998/boring_avatars';
const WATCHED = 'src/lib';
/** The watcher's own label, so it can find the issues it filed. */
const LABEL = 'upstream-watch';

const argv = process.argv.slice(2);
const flag = (name) =>
  argv.find((a) => a.startsWith(`--${name}=`))?.slice(name.length + 3);
const apply = argv.includes('--apply');
const replay = flag('replay');
const ref = flag('ref') ?? 'master';

if (replay && apply) {
  // A replay reconstructs a day that has already happened. Letting it write
  // state or file issues would make a probe indistinguishable from an
  // observation — and the state it wrote would be a past state presented as
  // the present one.
  console.error('--replay 은 과거를 재생하는 프로브입니다. --apply 와 함께 쓸 수 없습니다.');
  process.exit(2);
}

const gh = (args) => execFileSync('gh', args, { encoding: 'utf8' }).trim();
const git = (args) => execFileSync('git', ['-C', REFS, ...args], { encoding: 'utf8' }).trim();

/** Observe `src/lib` as GitHub reports it right now. */
function observeFromApi(atRef) {
  const tree = JSON.parse(
    gh(['api', `repos/${UPSTREAM}/git/trees/${atRef}:${WATCHED}?recursive=1`]),
  );
  if (tree.truncated) {
    // Reading a truncated tree as the whole tree turns "GitHub paginated us"
    // into "upstream deleted files" — a change report invented out of nothing.
    // Scoped to this subtree it should never fire; that is why it is cheap.
    throw new Error(
      `${WATCHED} 의 트리 응답이 잘렸습니다 (truncated). 지금 비교하면 ` +
        '없는 삭제를 보고하게 되므로 여기서 멈춥니다.',
    );
  }
  const commit = gh(['api', `repos/${UPSTREAM}/commits/${atRef}`, '--jq', '.sha']);
  return {
    ref: atRef,
    commit,
    tree: tree.sha,
    files: Object.fromEntries(
      tree.tree
        .filter((e) => e.type === 'blob')
        .map((e) => [e.path, e.sha])
        .sort(([a], [b]) => (a < b ? -1 : 1)),
    ),
  };
}

/**
 * Observe `src/lib` at a revision of the pinned reference tree.
 *
 * **`ref` is the watched branch, not `rev`.** A replay simulates the same
 * branch observed on two different days, so putting the tag name in `ref`
 * makes every replay trip the ref-moved rule and report a change — which is
 * what it did the first time this ran, on the one transition (v2.0.0 →
 * v2.0.1) that #51's fourth criterion asks it to stay quiet through. The unit
 * tests could not see it: they build states by hand, and only the observer
 * decides what `ref` means.
 */
function observeFromGit(rev, watched) {
  if (!existsSync(REFS)) {
    throw new Error(
      `레퍼런스 트리가 없습니다: ${REFS}\n` +
        'docs/agents/theflow.md 의 Step 1 에 만드는 방법이 있습니다.',
    );
  }
  const files = Object.fromEntries(
    git(['ls-tree', '-r', `${rev}:${WATCHED}`])
      .split('\n')
      .filter(Boolean)
      .map((line) => {
        const [meta, path] = line.split('\t');
        const [, type, sha] = meta.split(/\s+/);
        return type === 'blob' ? [path, sha] : null;
      })
      .filter(Boolean)
      .sort(([a], [b]) => (a < b ? -1 : 1)),
  );
  return {
    ref: watched,
    commit: git(['rev-parse', `${rev}^{commit}`]),
    tree: git(['rev-parse', `${rev}:${WATCHED}`]),
    files,
  };
}

const readState = () =>
  existsSync(STATE_PATH) ? JSON.parse(readFileSync(STATE_PATH, 'utf8')) : null;

function writeState(state) {
  // Trailing newline, two-space indent — this file is read in `git diff` far
  // more often than by the tool, and that is the point of committing it.
  writeFileSync(STATE_PATH, `${JSON.stringify(state, null, 2)}\n`, 'utf8');
}

/** The issue this run would file, if it is already there. */
function existingIssue(title) {
  const found = JSON.parse(
    gh([
      'issue', 'list', '--repo', REPO, '--state', 'all',
      '--label', LABEL, '--limit', '50', '--json', 'number,title',
    ]),
  );
  return found.find((i) => i.title === title) ?? null;
}

function ensureLabel() {
  const names = JSON.parse(
    gh(['label', 'list', '--repo', REPO, '--limit', '100', '--json', 'name']),
  ).map((l) => l.name);
  if (names.includes(LABEL)) return;
  gh([
    'label', 'create', LABEL, '--repo', REPO, '--color', 'BFD4F2',
    '--description', '상류 src/lib 변경 알림 (tool/watch/upstream.mjs 가 생성)',
  ]);
  console.log(`  라벨 ${LABEL} 을 만들었습니다.`);
}

// ---------------------------------------------------------------------------

const [from, to] = replay ? replay.split('..') : [];
if (replay && (!from || !to)) {
  console.error('--replay 형식: --replay=<이전 revision>..<이후 revision>');
  process.exit(2);
}

const prev = replay ? observeFromGit(from, ref) : readState();
const next = replay ? observeFromGit(to, ref) : observeFromApi(ref);

console.log(
  replay
    ? `  재생: ${from} → ${to}  (레퍼런스 트리)`
    : `  관측: ${UPSTREAM}@${ref}  ${WATCHED}  tree ${next.tree.slice(0, 7)}`,
);

const diff = diffTrees(prev, next);

if (diff.kind === 'first-run') {
  console.log('  이전 상태가 없습니다 — 기준선만 기록하고 이슈는 만들지 않습니다.');
  console.log(`  파일 ${Object.keys(next.files).length}개, tree ${next.tree.slice(0, 7)}`);
  if (apply) {
    writeState(next);
    console.log(`  → ${STATE_PATH} 에 기록했습니다.`);
  } else {
    console.log('  --apply 를 붙이면 기록합니다.');
  }
  process.exit(0);
}

if (diff.kind === 'unchanged') {
  console.log(`  변경 없음 — ${WATCHED} 는 마지막으로 본 것과 같습니다.`);
  console.log(`  (commit ${prev.commit.slice(0, 7)} → ${next.commit.slice(0, 7)})`);
  process.exit(0);
}

const { title, body } = renderIssue(diff, prev, next);

console.log(`\n  변경됨 — ${diff.modified.length} 수정 · ${diff.added.length} 추가 · ${diff.removed.length} 삭제`);
for (const m of diff.modified) console.log(`    ~ ${WATCHED}/${m.path}  ${m.from.slice(0, 7)} → ${m.to.slice(0, 7)}`);
for (const a of diff.added) console.log(`    + ${WATCHED}/${a.path}  ${a.sha.slice(0, 7)}`);
for (const r of diff.removed) console.log(`    - ${WATCHED}/${r.path}  ${r.sha.slice(0, 7)} 였음`);
if (diff.treeOnly) console.log('    (blob 은 그대로 — 이름이나 파일 모드가 바뀌었습니다)');
if (diff.refMoved) console.log(`    ref ${diff.refMoved.from} → ${diff.refMoved.to}`);

if (!apply) {
  // The whole body, not just the title — same rule as tool/milestones/sync.mjs,
  // which prints the description it would write. A dry run that shows less
  // than it would do is one nobody can check before letting it act.
  console.log(`\n  만들 이슈: ${title}\n`);
  console.log(body.replace(/^/gm, '  │ '));
  console.log('\n  --apply 를 붙이면 이 이슈를 만들고 상태를 기록합니다.');
  process.exit(0);
}

ensureLabel();
const already = existingIssue(title);
if (already) {
  console.log(`\n  같은 제목의 이슈가 이미 있습니다 (#${already.number}) — 만들지 않습니다.`);
} else {
  const url = gh([
    'issue', 'create', '--repo', REPO, '--title', title, '--body', body,
    '--label', LABEL, '--label', 'needs-triage',
  ]);
  console.log(`\n  이슈를 만들었습니다: ${url}`);
}

// State last — see the header.
writeState(next);
console.log(`  ${STATE_PATH} 를 갱신했습니다.`);
