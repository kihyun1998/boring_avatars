// The upstream watcher's pure half: two observed states of `src/lib` in, one
// report out. No network, no filesystem, no `gh` — so it is testable with
// `node --test tool/watch/` and so the historical replay (`--replay`) can feed
// it real tags from the pinned reference tree and get exactly what the
// scheduled run would have got.
//
// **Why blob SHAs and not releases.** Measured over upstream's 28 tags: 9 of
// them carry a `src/lib` byte-identical to their predecessor's, and 2.0.3 /
// 2.0.4 were published to npm with **no git tag at all**. A release-triggered
// watcher is therefore noisy in one direction and blind in the other. The tree
// is the thing that actually moves.
//
// A TOOL, not a gate — see tool/watch/README.md.

/** The upstream repository, in the one place that has to know its name. */
export const UPSTREAM = 'boringdesigners/boring-avatars';

/**
 * A state is `{ ref, commit, tree, files }` — the branch watched, the commit it
 * pointed at, the `src/lib` subtree SHA, and path → blob SHA for every file
 * under it. Paths are relative to `src/lib/`.
 */
function assertConsistent(prev, next) {
  if (prev.tree !== next.tree) return;
  const a = JSON.stringify(sortedPairs(prev.files));
  const b = JSON.stringify(sortedPairs(next.files));
  if (a !== b) {
    throw new Error(
      `같은 tree SHA (${next.tree}) 인데 파일 목록이 다릅니다. ` +
        'git 이 보장하는 성질이 깨졌다는 뜻이므로 — 상태 파일이 손으로 ' +
        '고쳐졌거나, 트리 응답이 잘렸습니다. 여기서 멈춥니다.',
    );
  }
}

const sortedPairs = (files) =>
  Object.keys(files)
    .sort()
    .map((p) => [p, files[p]]);

/**
 * Compare the last-seen state with the one just observed.
 *
 * `prev` is `null` on the very first run. That case is deliberately **not** a
 * pile of additions: reporting the baseline as "upstream added nine files"
 * would file an issue about a day upstream did nothing.
 */
export function diffTrees(prev, next) {
  const empty = { added: [], removed: [], modified: [] };
  if (prev === null) return { kind: 'first-run', ...empty };

  assertConsistent(prev, next);

  const added = [];
  const removed = [];
  const modified = [];
  for (const [path, sha] of sortedPairs(next.files)) {
    const before = prev.files[path];
    if (before === undefined) added.push({ path, sha });
    else if (before !== sha) modified.push({ path, from: before, to: sha });
  }
  for (const [path, sha] of sortedPairs(prev.files)) {
    if (next.files[path] === undefined) removed.push({ path, sha });
  }

  const refMoved = prev.ref === next.ref ? null : { from: prev.ref, to: next.ref };
  const blobsMoved = added.length + removed.length + modified.length > 0;
  const treeMoved = prev.tree !== next.tree;

  if (!treeMoved && !refMoved) return { kind: 'unchanged', ...empty };

  return {
    kind: 'changed',
    added,
    removed,
    modified,
    refMoved,
    // A tree can move with every blob standing still — the SHA covers names and
    // file modes too. Saying so is better than printing a change list that is
    // empty for reasons the reader has to guess.
    treeOnly: treeMoved && !blobsMoved,
  };
}

const short = (sha) => sha.slice(0, 7);

const section = (heading, rows) =>
  rows.length === 0 ? '' : `\n**${heading}**\n\n${rows.join('\n')}\n`;

/**
 * Render the issue this watcher files. Refuses anything but a real change —
 * the guard is what stops a caller filing an empty issue by accident.
 */
export function renderIssue(diff, prev, next) {
  if (diff.kind !== 'changed') {
    throw new Error(
      `이슈는 kind === 'changed' 일 때만 만듭니다 (받은 값: ${diff.kind}).`,
    );
  }

  const compare = `https://github.com/${UPSTREAM}/compare/${prev.commit}...${next.commit}`;
  const title = `상류 \`src/lib\` 가 움직였습니다 — ${short(next.tree)}`;

  const body = [
    `[\`${UPSTREAM}\`](https://github.com/${UPSTREAM}) 의 \`src/lib/\` 가`,
    `마지막으로 본 상태와 달라졌습니다. **이 이슈는 게이트가 아닙니다** —`,
    `아무것도 막지 않고, 새 상류 상태가 릴리스 후보인지 판단해 달라는 알림입니다.`,
    ``,
    `| | 마지막으로 본 것 | 지금 |`,
    `|---|---|---|`,
    `| ref | \`${prev.ref}\` | \`${next.ref}\` |`,
    `| commit | \`${short(prev.commit)}\` | \`${short(next.commit)}\` |`,
    `| \`src/lib\` tree | \`${short(prev.tree)}\` | \`${short(next.tree)}\` |`,
    ``,
    `[변경 내용 보기 (compare)](${compare})`,
    diff.refMoved
      ? `\n> **감시 대상 ref 가 바뀌었습니다**: \`${diff.refMoved.from}\` → ` +
        `\`${diff.refMoved.to}\`. blob 이 그대로여도 이건 변경입니다 — 무엇을 ` +
        `보고 있는지가 달라졌으니까요.\n`
      : '',
    diff.treeOnly
      ? `\n> tree SHA 는 움직였는데 blob 은 하나도 안 움직였습니다. tree SHA 는 ` +
        `이름과 파일 모드까지 덮으므로, 내용이 아닌 것이 바뀌었다는 뜻입니다 ` +
        `(mode 변경, 심볼릭 링크 등). compare 링크로 확인하세요.\n`
      : '',
    section(
      '바뀐 파일',
      diff.modified.map(
        (m) => `- \`src/lib/${m.path}\` — \`${short(m.from)}\` → \`${short(m.to)}\``,
      ),
    ),
    section(
      '새 파일',
      diff.added.map((a) => `- \`src/lib/${a.path}\` — \`${short(a.sha)}\``),
    ),
    section(
      '삭제된 파일',
      diff.removed.map((r) => `- \`src/lib/${r.path}\` — \`${short(r.sha)}\` 였음`),
    ),
    ``,
    `## 다음에 할 일`,
    ``,
    `1. 이 변경이 **출력에 닿는지** 판단합니다 — 닿지 않으면 새 릴리스가 아닙니다`,
    `   (\`CLAUDE.md\` 원칙 3: 릴리스는 *출력 상태* 하나당 하나).`,
    `2. 닿는다면 \`tool/versions\` 로 그룹을 다시 재고, 새 선택자 값을 검토합니다.`,
    `3. 어느 쪽이든 \`docs/agents/theflow.md\` 의 버전 사다리를 갱신합니다.`,
    ``,
    `<sub>\`tool/watch/upstream.mjs\` 가 자동 생성 (#51). 상태: \`tool/watch/last-seen.json\`</sub>`,
  ]
    .join('\n')
    // The optional blocks above contribute an empty string when they do not
    // apply, which leaves runs of blank lines in the rendered issue. Collapsing
    // here keeps each block's own condition readable rather than threading
    // whitespace through every one of them.
    .replace(/\n{3,}/g, '\n\n');

  return { title, body };
}
