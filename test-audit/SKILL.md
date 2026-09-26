---
name: test-audit
description: "Use whenever writing, changing, reviewing, or sweeping tests in a Ruby, JavaScript/TypeScript, Python, or Rust project. Authoring gate for new tests, plus an audit workflow for low-value, implementation-coupled, or duplicated tests and the test-only production seams they keep alive. Triggers on 'add a test', 'write tests for', 'review these tests', 'test audit', 'prune the tests', 'clean up the test suite', 'are these tests worth keeping'."
---

# Test Audit

Three modes, one value bar. Authoring mode gates every new or changed test at
write time. Audit mode runs focused sweeps of tests that re-assert source,
duplicate stronger proof, couple behavior to implementation, or keep test-only
production seams alive. Continue broad audits as separate coherent follow-up
PRs; optimize for confidence, not deletion count. Campaign mode prunes one
whole subsystem's test surface (every test file one gem, package, crate, app
module, or plugin owns); before starting one, read [CAMPAIGN.md](CAMPAIGN.md).

## Repo context

Run once per repo, before the first judgement:

```bash
"$HOME/.claude/skills/test-audit/scripts/test_context.sh"
```

It prints labeled sections:

- **AGENT_DOCS**: `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md` and testing docs.
  Read the root file and every scoped file above the paths in scope. Repo rules
  win over this skill.
- **RUBY / JAVASCRIPT / PYTHON / RUST**: one section per project root, with the
  focused test command, formatter, linter, type checker, and the test libraries
  in use. Read the matching section of
  [references/stacks.md](references/stacks.md) for each stack in scope; it maps
  the generic rules below to that language's idioms.
- **TASK_RUNNERS** and **CI**: repo wrappers (`bin/ci`, `make test`, package
  scripts, pre-commit hooks) and the test lines CI actually runs. Prefer the
  repo's wrapper over the raw runner; CI shows what gates a merge.
- **TEST_SURFACE**: test and support file, line, and declaration counts.
- **SKIP_MARKERS**: focused (`.only`, `fit`, `focus: true`) and skipped tests.
- **WATCH_RUNNERS**: watch-mode runners running in this checkout.

## Authoring gate

Before adding any test, answer four questions; a missing answer means do not
add it yet:

1. What observable behavior, invariant, or independent contract does it protect?
2. What credible regression makes it fail?
3. Why does existing coverage not already catch that failure? Each contract has
   one primary test owner at the strongest boundary; another layer needs its
   own distinct risk, such as a transport or lifecycle failure the owner cannot
   reach. Prefer extending a table-driven case (`it.each`,
   `pytest.mark.parametrize`, an RSpec example loop, an `rstest` case) or a
   shared fixture over a near-duplicate test; consolidate duplicated setup in
   the same change.
4. Does it need a production seam that no production caller needs: an export,
   a flag, a wrapper, an injection hook, visibility widened for tests, or an
   `if test environment` branch? If yes, move the test to the real boundary
   instead.

Then check the test against every [junk pattern](#junk-patterns); a match fails
the gate unless the [retention bar](#retention-bar) names the contract it
independently guards. A test that would break under behavior-preserving
refactoring is asserting implementation, not behavior; rewrite it at the
owning boundary before landing it.

Bug regression tests must fail on the pre-fix code for the intended reason and
pass after the owner-boundary repair. A regression test that never demonstrably
failed proves the mock, not the fix. One regression at the owner boundary
covers the bug; do not replay the same scenario at every layer it crosses.

## Junk patterns

The shared checklist for both modes: the authoring gate rejects a new test that
matches one, and audits hunt for existing tests that do.

- assertion-free coverage probes;
- self-comparisons and identity copiers;
- copied fixtures, inventories, manifests, or export lists;
- exact source, import, or string greps;
- private predicate or call-shape tests duplicated at real boundaries;
- duplicate invocations of the same contract;
- each caller replaying a shared helper's own tests;
- tests whose only purpose is preserving test-only exports, globals, or wrappers;
- dead production code whose only callers are tests;
- expected values produced by the helper or renderer under test, including
  snapshots accepted without anyone reading them;
- mocks that implement the asserted behavior, or one identical mock standing in
  for different APIs;
- fixtures or stubs that supply the result, acknowledgement, or callback order
  the code under test should produce, or persistence asserted against a store
  the path never writes;
- tests that restate a declared flag, config value, or declaration instead of
  exercising the behavior it promises;
- negative controls that pass for an unrelated reason, such as a denial from a
  different guard or a rejection the production path never reaches;
- names or fixtures that promise more than the input exercises, such as an
  "expires the session" test that asserts the session still exists;
- focus markers that silently shrink the suite, and skipped or ignored tests
  with no reason, owner, or CI job that runs them.

## Value bar

Tests justify their maintenance cost by protecting behavior, a credible
regression, or an independently meaningful contract. In an audit, an existing
test that must change for behavior-preserving source reorganization is suspect,
not automatically deletable; the authoring gate still rejects new ones.

Before judging a candidate, read the complete test and production owner, its
entry point, callers, callees, sibling implementations, overlapping tests,
whether and where CI runs it (tags, markers, feature flags, excluded paths),
and relevant history (`git log -L` or `git log --follow -p` on the test).
When the test claims dependency-backed behavior, inspect the dependency source
or types directly; [references/stacks.md](references/stacks.md) says where each
stack keeps them.

## Discovery

Keep discovery read-only and report evidence before editing. For broad scope,
run parallel read-only discovery lanes (subagents) when available:

- core library and application code (`lib/`, `app/`, `src/`, `packages/*`,
  `crates/*`);
- plugins, engines, or workspace members with their own suites;
- UI, apps, scripts, and tooling (`bin/`, `scripts/`, frontend);
- a cross-cutting pattern sweep across all test files.

Outside campaign mode, prefer a few high-confidence candidates over a large
speculative inventory. Hunt for the [junk patterns](#junk-patterns). Coverage
reports help find production code whose only callers are tests; they are
evidence, not a verdict.

## Retention bar

Keep a test when it independently enforces a public API, CLI, wire protocol,
file format, config, database migration, storage, security, platform, default
value, exact output bytes (rendered text, prompts, serialized formats),
generated code, packaging, release, or architecture contract. Also keep:

- call ordering when order is observable behavior;
- regressions with a credible failure mode;
- source inspection when it is the cheapest independent guard: it fails when
  the contract changes (the user-facing key, byte, or path) and survives an
  identifier-only refactor;
- a retained test that fails on the baseline: treat it as a possible product
  bug, reproduce it, and repair the owner rather than deleting it.

Static or slow is not a deletion reason. A test that resembles implementation
may still be the independent contract; prove otherwise before removing it.

## Candidate evidence

Record every field below before editing. A missing field means the candidate is
not ready for deletion:

- exact test name and location;
- what failure it can actually detect;
- non-test callers of the covered production or support seam, including
  dynamic ones (see the stack notes);
- stronger remaining owner-boundary proof, or why no proof is needed;
- relevant history and the reason the test or seam exists;
- production or test-support deletion unlocked;
- risk and the focused validation command.

## Edit shape

Choose one coherent owner-boundary batch. Delete obsolete test-only exports,
globals, wrappers, and dead production paths instead of preserving aliases.
Move retained regressions to their canonical owners. Consolidate repeated
package or dependency assertions into one generic contract.

Prefer net-negative production LOC. Do not add replacement tests that restate
the same implementation, and do not convert uncertain candidates into cleanup
to increase deletion counts.

## Validation

Never edit source or tests while a watch-mode runner (WATCH_RUNNERS) is running
in the checkout; it reruns half-edited files and reports misleading results.
Ask the user to stop it first.

1. Run the smallest owner and sibling tests with the focused command from the
   stack section.
2. For removed source greps or plan assertions, run the executable script, CLI,
   or dry-run that owns the real contract.
3. Run the formatter and linter on changed files, then `git diff --check`.
4. Run the gate the repo requires for the changed paths: the CI test lines,
   the repo wrapper (`bin/ci`, `make check`, `pre-commit run --files <paths>`),
   and the type checker where the stack has one. Deleted tests can drop
   coverage below a configured threshold; lowering a threshold needs the
   user's approval.
5. Split the diff into tests, test support, and production:

   ```bash
   "$HOME/.claude/skills/test-audit/scripts/test_context.sh" diff [<base>]
   ```

   With no base it covers uncommitted work; pass the default branch for a
   whole branch. Report production/tooling separately from tests and test
   support.
6. After final audit edits, run a review pass over the whole diff: the
   `code-review` skill (`/code-review`) when available, otherwise re-check
   every deletion against its candidate evidence.

## Landing and continuation

Commit, push, open a PR, or merge only when the user asked. Open PRs with the
`create-pull-request` skill when it is installed. Land one coherent PR at a
time; after landing, refresh from the default branch and rerun read-only
discovery for the next high-confidence batch.

## Handoff

Report:

- root cause and removed low-value categories;
- production owner simplifications;
- retained false positives and why they remain valuable;
- focused and full proof actually run;
- production versus test LOC;
- PR and merge state;
- named follow-ups.

## Resources

- `scripts/test_context.sh`: repo survey (stacks, commands, CI, surface,
  markers, watchers); `diff [<base>]` splits the diff into tests, support, and
  production.
- `references/stacks.md`: per-language runners, idioms, seams, mocks,
  dynamic callers, dependency source, coverage.
- `CAMPAIGN.md`: whole-subsystem pruning, lane by lane.
