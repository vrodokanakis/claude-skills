---
name: worktree-space
description: "Use when running inside Herdr (HERDR_ENV=1) and the user asks to open a worktree in a Herdr space, move this session into a new worktree, start feature work in its own worktree workspace, or says worktree space / herdr worktree / open in herdr. Works in any git repository. Outside Herdr do not use it: use EnterWorktree alone."
---

# Worktree space

Create the worktree with the bundled script, then move this session into it
with `EnterWorktree`. The script moves the *terminal pane* into a grouped
Herdr workspace; `EnterWorktree` moves the *session*. Both are needed, and
the script cannot do the second one.

Worktrees go under `<repo>/.claude/worktrees/<slug>`. That is the one
location `EnterWorktree` accepts from anywhere, including from a session
already sitting in another worktree, so chained runs are a normal move.

Script: `~/.claude/skills/worktree-space/scripts/worktree-space.sh`
(`--help` is the header comment; read it for flags).

## Steps

1. Gate: `test "${HERDR_ENV:-}" = 1`. If it fails, say so and stop using
   this skill. Create the worktree with `EnterWorktree name=<slug>` instead.
2. Pick the branch name up front (the ticket's canonical branch name if the
   project uses one; renaming a branch with an open PR closes the PR).
3. Run:

   ```bash
   ~/.claude/skills/worktree-space/scripts/worktree-space.sh <branch>
   ```

   It prints the worktree path, the workspace id, and a final
   `==> Next: EnterWorktree path="..."` line. If the repo ships its own
   `bin/worktree-herdr`, the script delegates to it and the project's own
   worktree skill or AGENTS.md rules take over from here, including any
   handoff behaviour on chained runs.
4. Call `EnterWorktree` with the printed `path`. Never `claude --resume` in
   the new workspace: the running session is the one that moved.
5. If the script reported a background setup log, wait for it before any
   command that needs dependencies or databases:

   ```bash
   grep -q 'Done. Worktree ready' <repo>/.claude/worktrees/<slug>-setup.log
   ```

6. First report after the move states: workspace opened, session moved, and
   whether setup is still running.

## Project hooks

- `bin/worktree-herdr` in the repo: the script execs it. Project owns the flow.
- `.claude/worktree-setup.sh` in the repo (executable): run once inside the
  new worktree in the background with args `<slug> <branch>`. Its last line
  on success must be `Done. Worktree ready`. Use it for bundle/db/deps.

## Notes

- Re-runnable: an existing worktree dir is reused and an already-open
  workspace gets a new tab instead of a second workspace.
- After moving from one worktree to another, the previous worktree is no
  longer writable from this session. Re-enter it with `EnterWorktree path`
  if you need to.
- Teardown: `ExitWorktree` moves the session back, not the pane. Move the
  pane to its home workspace first (`herdr pane move <id> --workspace <home>`),
  then exit with `action: "remove"`. The empty workspace closes when its last
  pane leaves. Delete the setup log too.
- Outside Herdr the script still builds the worktree and prints the
  `herdr worktree open` command to run later.
