// The watcher's pure half, tested with zero network and zero filesystem.
//
//   node --test tool/watch/
//
// The impure half (tool/watch/upstream.mjs) is proved differently — by replaying
// real upstream tags out of the pinned reference tree, which is the only proof
// that answers #51's fourth acceptance criterion. See the README.
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { diffTrees, renderIssue } from './diff.mjs';

/** A state as it is stored in last-seen.json. */
const state = (tree, files, { ref = 'master', commit = `c-${tree}` } = {}) => ({
  ref,
  commit,
  tree,
  files,
});

const BASE = state('aaaa111', {
  'index.tsx': 'f1',
  'utilities.ts': 'f2',
  'components/avatar-beam.tsx': 'f3',
});

test('no previous state is a first run, not nine added files', () => {
  const d = diffTrees(null, BASE);
  assert.equal(d.kind, 'first-run');
  // The side condition is the whole point: a first run that reports the
  // baseline as additions files an issue saying upstream just wrote every
  // file it has, on a day upstream did nothing.
  assert.deepEqual(d.added, []);
  assert.deepEqual(d.removed, []);
  assert.deepEqual(d.modified, []);
});

test('an identical tree is unchanged', () => {
  const d = diffTrees(BASE, state('aaaa111', { ...BASE.files }));
  assert.equal(d.kind, 'unchanged');
  assert.deepEqual(d.added, []);
  assert.deepEqual(d.removed, []);
  assert.deepEqual(d.modified, []);
});

test('a new commit that leaves src/lib alone is unchanged', () => {
  // The entire reason this watcher reads trees instead of releases: 9 of
  // upstream's 28 tags carry a src/lib identical to their predecessor's.
  const d = diffTrees(BASE, state('aaaa111', { ...BASE.files }, { commit: 'c-later' }));
  assert.equal(d.kind, 'unchanged');
});

test('a modified file carries both SHAs, and nothing else moves', () => {
  const next = state('bbbb222', { ...BASE.files, 'utilities.ts': 'f2-new' });
  const d = diffTrees(BASE, next);
  assert.equal(d.kind, 'changed');
  assert.deepEqual(d.modified, [
    { path: 'utilities.ts', from: 'f2', to: 'f2-new' },
  ]);
  assert.deepEqual(d.added, []);
  assert.deepEqual(d.removed, []);
});

test('an added file is an addition, not a modification', () => {
  const next = state('bbbb222', { ...BASE.files, 'components/avatar-new.tsx': 'f9' });
  const d = diffTrees(BASE, next);
  assert.equal(d.kind, 'changed');
  assert.deepEqual(d.added, [{ path: 'components/avatar-new.tsx', sha: 'f9' }]);
  assert.deepEqual(d.modified, []);
  assert.deepEqual(d.removed, []);
});

test('a removed file is a removal, and keeps the SHA it had', () => {
  const files = { ...BASE.files };
  delete files['utilities.ts'];
  const d = diffTrees(BASE, state('bbbb222', files));
  assert.equal(d.kind, 'changed');
  assert.deepEqual(d.removed, [{ path: 'utilities.ts', sha: 'f2' }]);
  assert.deepEqual(d.added, []);
  assert.deepEqual(d.modified, []);
});

test('paths are reported in a stable order, not in object order', () => {
  const next = state('bbbb222', {
    'utilities.ts': 'f2-new',
    'components/avatar-beam.tsx': 'f3-new',
    'index.tsx': 'f1-new',
  });
  const d = diffTrees(BASE, next);
  assert.deepEqual(
    d.modified.map((m) => m.path),
    ['components/avatar-beam.tsx', 'index.tsx', 'utilities.ts'],
  );
});

test('a renamed file reads as one addition and one removal', () => {
  const files = { ...BASE.files };
  delete files['utilities.ts'];
  files['utils.ts'] = 'f2';
  const d = diffTrees(BASE, state('bbbb222', files));
  assert.equal(d.kind, 'changed');
  assert.deepEqual(d.added, [{ path: 'utils.ts', sha: 'f2' }]);
  assert.deepEqual(d.removed, [{ path: 'utilities.ts', sha: 'f2' }]);
});

test('the ref moving is a change even when every blob is identical', () => {
  // Upstream renaming master → main must not read as "nothing happened".
  // The blobs really are the same; what changed is *what we are watching*, and
  // a watcher that silently follows is one nobody can audit.
  const d = diffTrees(BASE, { ...BASE, ref: 'main' });
  assert.equal(d.kind, 'changed');
  assert.deepEqual(d.refMoved, { from: 'master', to: 'main' });
});

test('a tree that moved with no blob moving is still a change', () => {
  // A git tree SHA covers names and file *modes*, not only blob content — so
  // this is reachable (chmod, a symlink) and per-blob comparison is blind to
  // it. Reporting "unchanged" would also freeze last-seen.json on the old tree
  // forever, since the state only advances when something is reported.
  const d = diffTrees(BASE, state('bbbb222', { ...BASE.files }));
  assert.equal(d.kind, 'changed');
  assert.equal(d.treeOnly, true);
  assert.deepEqual(d.modified, []);
});

test('a tree SHA that disagrees with its own file list throws', () => {
  // Git guarantees these agree. If they do not, one of the two states was
  // hand-edited or truncated, and the honest move is to stop rather than to
  // report a diff derived from a state that cannot exist.
  assert.throws(
    () => diffTrees(BASE, state('aaaa111', { ...BASE.files, 'index.tsx': 'CHANGED' })),
    /tree SHA/i,
  );
});

test('rendering an issue for a non-change is refused', () => {
  // The guard is the reason a caller cannot file an empty issue by accident.
  assert.throws(() => renderIssue(diffTrees(null, BASE), null, BASE), /changed/i);
  assert.throws(
    () => renderIssue(diffTrees(BASE, { ...BASE }), BASE, BASE),
    /changed/i,
  );
});

test('the issue body names every file, both SHAs, and links a live compare', () => {
  const next = state(
    'bbbb2222222222',
    {
      'utilities.ts': 'f2-new',
      'index.tsx': 'f1',
      'components/avatar-beam.tsx': 'f3',
      'components/avatar-new.tsx': 'f9',
    },
    { commit: 'commit-new' },
  );
  const d = diffTrees(BASE, next);
  const { title, body } = renderIssue(d, BASE, next);

  assert.match(title, /bbbb222/);
  assert.match(body, /utilities\.ts/);
  assert.match(body, /f2-new/);
  assert.match(body, /avatar-new\.tsx/);

  // The compare link is between **commits**. Between trees it is a 404 —
  // measured, not assumed: two real src/lib tree SHAs (v2.0.1, v2.0.2) return
  // 404 from github.com/…/compare, and their commits return 200. A dead link
  // would satisfy a laxer assertion and be found by a human, months later.
  assert.match(body, /compare\/c-aaaa111\.\.\.commit-new/);
  assert.doesNotMatch(body, /compare\/aaaa111\.\.\./);

  // An empty section must not appear: it reads as "we checked and found none",
  // which is true today and becomes a lie the day the renderer stops filling it.
  assert.doesNotMatch(body, /삭제된 파일/);
});
