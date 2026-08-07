// The mutation harness — a TOOL, not a gate.
//
//   node tool/mutate/run.mjs cases/41-marble.json          # every case
//   node tool/mutate/run.mjs cases/41-marble.json --only=A  # one group
//
// `flutter test` never runs this. It exists because a claim like "12 of 12
// mutants died" is a claim about a *measurement*, and this repo's own rule for
// `tool/versions` applies to it verbatim: **a claim whose evidence cannot be
// re-run is one nobody can check.** Before this existed, three separate
// runners were written from scratch in one session and each one re-learned the
// same traps.
//
// Every rule below is a scar. `docs/agents/lessons.md` has the incidents.
//
//  * **Literal `split`/`join`, never a regex.** A pattern that is accidentally
//    a regex matches something else and the report is silently about the wrong
//    edit (#34, #36, #37).
//  * **Three outcomes, not two.** `NO MATCH` is its own result. Folding a
//    substitution that never applied into "survived" is how a report says the
//    exact opposite of the truth in the one place whose job is to say which
//    mechanisms are unguarded (#34, #36, #37, #39).
//  * **A green run over zero tests is not a survivor either.** A `--name`
//    filter that matches nothing runs nothing and exits 0.
//  * **argv as an array, never shell-joined.** `execFileSync(cmd, args,
//    {shell: true})` concatenates unquoted, so `--name "a b c"` arrives as
//    three bare words, the filter never applies, the whole file runs, and a
//    mutation the filtered group is provably blind to is reported **killed**.
//    A false kill retires a real question as answered — the worse direction
//    (#39).
//  * **Read the file's own line ending.** The working tree is CRLF
//    (`core.autocrlf=true`). A multi-line pattern written with bare `\n`
//    matches nothing (#39, and again in #41).
//  * **Verify restoration against the bytes we saved, not `git status`.** The
//    files under test are usually tracked *and* legitimately modified while
//    work is in progress, so git is dirty by design and cannot answer "did the
//    mutation get backed out" (#41).
//  * **Assert the tree is untouched before starting.** Two measuring lenses in
//    one worktree produced a run whose baseline was already mutated (#39).
import { execSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '..', '..');

const CR = String.fromCharCode(13);
const LF = String.fromCharCode(10);

const [specArg, ...flags] = process.argv.slice(2);
if (!specArg) {
  console.error('usage: node tool/mutate/run.mjs <cases.json> [--only=<group>]');
  process.exit(2);
}
const only = flags.find((f) => f.startsWith('--only='))?.slice('--only='.length);

const spec = JSON.parse(readFileSync(resolve(HERE, specArg), 'utf8'));
const cases = spec.cases.filter((c) => !only || c.group === only);
if (cases.length === 0) {
  console.error(`no cases matched --only=${only}`);
  process.exit(2);
}

/** Rewrites a pattern's newlines to whatever the target file actually uses. */
const toFileEndings = (pattern, source) =>
  source.includes(CR + LF)
    ? pattern.split(LF).join(CR + LF)
    : pattern.split(CR + LF).join(LF);

/** Runs one test target bare. Returns {failed, ran}. */
function runTests(target) {
  // `flutter` is a `.bat`, so it cannot be `execFile`d directly, and handing
  // `cmd.exe` a multi-part argv gets Node's own escaping applied on top of
  // cmd's — "The syntax of the command is incorrect". This runner reported
  // that as `NO TESTS` on all 32 cases rather than as 32 survivors, which is
  // the third outcome doing its job on the runner itself.
  //
  // So: one command string, quoted **here**. That is the lesson's
  // prescription, not its prohibition — what #39 caught was an argv array
  // being concatenated *unquoted* by someone else. Only `target` can contain
  // anything surprising, and it is quoted.
  const command = [
    'flutter',
    'test',
    target ? `"${target}"` : null,
    '--reporter',
    'compact',
  ]
    .filter(Boolean)
    .join(' ');
  try {
    const out = execSync(command, {
      cwd: REPO,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    const seen = out.match(/\+(\d+)/g) ?? [];
    const ran = seen.length ? Math.max(...seen.map((s) => +s.slice(1))) : 0;
    return { failed: false, ran };
  } catch (e) {
    const out = `${e.stdout ?? ''}`;
    const seen = out.match(/\+(\d+)/g) ?? [];
    const ran = seen.length ? Math.max(...seen.map((s) => +s.slice(1))) : 0;
    return { failed: true, ran };
  }
}

const tally = { killed: 0, survived: 0, noMatch: 0, noTests: 0 };
const report = [];

for (const c of cases) {
  const path = resolve(REPO, c.file);
  const original = readFileSync(path, 'utf8');

  const from = toFileEndings(c.from, original);
  const to = toFileEndings(c.to ?? '', original);
  const pieces = original.split(from);
  const edits = pieces.length - 1;

  if (edits === 0) {
    tally.noMatch++;
    report.push(['NO MATCH', c.name, 'the substitution never applied']);
    continue;
  }
  if (c.expectEdits != null && edits !== c.expectEdits) {
    tally.noMatch++;
    report.push([
      'NO MATCH',
      c.name,
      `applied ${edits} times, the case says ${c.expectEdits}`,
    ]);
    continue;
  }

  writeFileSync(path, pieces.join(to));
  let outcome;
  let detail;
  try {
    const { failed, ran } = runTests(c.test ?? spec.test);
    if (ran === 0) {
      outcome = 'NO TESTS';
      detail = 'the run covered zero tests — not a survivor';
      tally.noTests++;
    } else if (failed) {
      outcome = 'killed';
      detail = `${ran} tests ran`;
      tally.killed++;
    } else {
      outcome = 'SURVIVED';
      detail = `${ran} tests green with the mutation applied`;
      tally.survived++;
    }
  } finally {
    writeFileSync(path, original);
  }

  if (readFileSync(path, 'utf8') !== original) {
    console.error(`!! ${c.file} was not restored — stopping before the next case`);
    process.exit(1);
  }

  report.push([outcome, c.name, `${edits} edit(s) · ${detail}`]);
}

for (const [outcome, name, detail] of report) {
  console.log(`${outcome.padEnd(9)} ${name}`);
  console.log(`${' '.repeat(10)}${detail}`);
}

const { killed, survived, noMatch, noTests } = tally;
console.log(
  `\n${killed} killed · ${survived} survived · ${noMatch} never applied` +
    (noTests ? ` · ${noTests} ran no tests` : ''),
);

// A case that never applied is not a pass and not a failure — it is a stale
// case, and it has to be visible in the exit status or nobody fixes it.
if (survived > 0 || noMatch > 0 || noTests > 0) process.exit(1);
