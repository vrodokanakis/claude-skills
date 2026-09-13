---
name: tearing-down-a-merged-worktree
description: Use after a PR has merged and its worktree should be cleaned up (checkout, branch, Herdr workspace, setup log, project data). Triggers on tear down the worktree, clean up the worktree, remove the worktree, teardown after merge, and on an auto-merge poll seeing MERGED. Works in any git repository.
---

# Tearing down a merged worktree

`git worktree remove` cleans up only the checkout. The branch, the Herdr
workspace holding the pane, the setup log, and any per-worktree data
(databases, indexes) outlive it. The bundled script handles all of it except
moving the Claude session, which only `ExitWorktree` can do.

Script: `~/.claude/skills/tearing-down-a-merged-worktree/scripts/worktree-teardown.sh`
(header comment documents the flags).

Runs when the user asks after a merge, or automatically once auto-merge
polling sees `MERGED`. In the automatic case do not ask, but report.

## Steps

1. If the repo has its own `tearing-down-a-merged-worktree` skill under
   `.claude/skills/`, follow that one instead. It knows the project's data.
2. Run:

   ```bash
   ~/.claude/skills/tearing-down-a-merged-worktree/scripts/worktree-teardown.sh <slug>
   ```

   `<slug>` is the dir name under `.claude/worktrees/`, or any registered
   worktree path. The script refuses unless the branch's PR is `MERGED`
   (`--pr <n>` to name it, `--no-pr` only when the user confirms there is no
   PR). `CLOSED` is not `MERGED`: closed-unmerged work exists only in that
   checkout. Never bypass this for an open PR.
3. If the tree is dirty the script stops and shows the changes. Inspect with
   the user before re-running with `--force`. Unmerged work is the one thing
   here that cannot be recovered.
4. The script moves the pane to the repo's home workspace first, creating one
   if none exists, then removes checkout and branch, runs the project's
   `.claude/worktree-teardown.sh <slug> <branch>` hook if present, and deletes
   the setup log.
5. If the report ends with a `session:` line, call `ExitWorktree` with
   `action: "keep"` now. The session is sitting in a deleted directory.
6. Relay the report verbatim: branch, worktree, herdr, data hook, log. A
   teardown that quietly skipped a step reads exactly like one that worked.

## Project hook

`<repo>/.claude/worktree-teardown.sh <slug> <branch>` (executable) runs from
the main checkout after the git removal. Put database drops, index deletes and
container cleanup there, and make it verify by counting what the server
reports, not by exit code: a drop that matched nothing still exits 0.

## Notes

- `branch -D`, not `-d`: a squash merge leaves the branch looking unmerged.
- Pane and session are two movements. `herdr pane move` leaves the session's
  cwd behind; `ExitWorktree` leaves the pane behind. The script does the
  first, you do the second.
- The worktree's workspace closes itself when its last pane leaves. The
  script closes it explicitly if extra tabs kept it alive.
