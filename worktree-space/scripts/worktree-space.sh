#!/usr/bin/env bash

# Create a git worktree for the current repository and move this Herdr pane
# into it as a grouped workspace. Project-agnostic: works in any git repo.
#
# The worktree lives under <repo>/.claude/worktrees/<slug>, the directory
# Claude Code's EnterWorktree accepts from anywhere -- including from a session
# that is already inside another worktree. That is what makes chained runs
# (worktree -> worktree) a plain move here instead of a handoff.
#
# If the repository ships its own bin/worktree-herdr (project-specific data
# isolation, e.g. TPP), this script execs it and the project's rules apply.
#
# Optional project hook: <repo>/.claude/worktree-setup.sh, run inside the new
# worktree in the background (log: .claude/worktrees/<slug>-setup.log). It
# should print "Done. Worktree ready" as its last line on success.
#
# Usage: worktree-space.sh <branch> [--slug <name>] [--base <ref>] [--no-focus]
#   <branch>     Branch to create (or reuse if it already exists).
#   --slug       Worktree dir name; default: branch with '/' -> '-', lowercased.
#   --base       Start point; default origin/<default-branch>, else HEAD.
#   --no-focus   Move the pane without switching the UI to the new workspace.
#
# Outside Herdr (HERDR_ENV unset) the worktree is still created and the
# `herdr worktree open` command to run later is printed.

set -euo pipefail

die() { echo "Error: $*" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" && pwd)" \
  || die "not inside a git repository"
INVOKED_FROM="$(git rev-parse --show-toplevel)"

BRANCH="" SLUG="" BASE="" FOCUS="--focus"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --slug)     SLUG="${2:-}"; shift 2 ;;
    --base)     BASE="${2:-}"; shift 2 ;;
    --no-focus) FOCUS="--no-focus"; shift ;;
    -*)         die "unknown option: $1" ;;
    *)          [[ -z "$BRANCH" ]] || die "unexpected argument: $1"; BRANCH="$1"; shift ;;
  esac
done
[[ -n "$BRANCH" ]] || die "usage: worktree-space.sh <branch> [--slug <name>] [--base <ref>] [--no-focus]"

# Project-owned flow wins.
if [[ -x "$REPO_ROOT/bin/worktree-herdr" ]]; then
  echo "==> Repository ships bin/worktree-herdr; delegating (project rules apply)"
  ARGS=("$BRANCH"); [[ -n "$SLUG" ]] && ARGS+=(--slug "$SLUG"); [[ "$FOCUS" == "--no-focus" ]] && ARGS+=(--no-focus)
  exec "$REPO_ROOT/bin/worktree-herdr" "${ARGS[@]}"
fi

if [[ -z "$SLUG" ]]; then
  SLUG="$(printf '%s' "$BRANCH" | tr '[:upper:]' '[:lower:]' | tr '/' '-' | tr -c 'a-z0-9._-\n' '-' | sed 's/^-*//; s/-*$//')"
  [[ -n "$SLUG" ]] || die "could not derive a slug from '$BRANCH'; pass --slug <name>"
fi

WT_DIR="$REPO_ROOT/.claude/worktrees"
WT_PATH="$WT_DIR/$SLUG"
SETUP_LOG="$WT_DIR/$SLUG-setup.log"
CHAINED=""; [[ "$INVOKED_FROM" != "$REPO_ROOT" ]] && CHAINED="$INVOKED_FROM"

IN_HERDR=0
command -v herdr >/dev/null 2>&1 && [[ "${HERDR_ENV:-}" == "1" ]] && IN_HERDR=1

# ---- the checkout -----------------------------------------------------------

if [[ -d "$WT_PATH" ]]; then
  echo "==> .claude/worktrees/$SLUG already exists; reusing it"
else
  if [[ -z "$BASE" ]]; then
    DEFAULT="$(git -C "$REPO_ROOT" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    if [[ -z "$DEFAULT" ]]; then
      for c in origin/main origin/master; do
        git -C "$REPO_ROOT" rev-parse --verify -q "$c" >/dev/null && { DEFAULT="$c"; break; }
      done
    fi
    BASE="${DEFAULT:-HEAD}"
  fi
  mkdir -p "$WT_DIR"
  if git -C "$REPO_ROOT" rev-parse --verify -q "refs/heads/$BRANCH" >/dev/null; then
    echo "==> git worktree add .claude/worktrees/$SLUG $BRANCH (existing branch)"
    git -C "$REPO_ROOT" worktree add "$WT_PATH" "$BRANCH"
  else
    echo "==> git worktree add -b $BRANCH .claude/worktrees/$SLUG $BASE (--no-track)"
    git -C "$REPO_ROOT" worktree add --no-track -b "$BRANCH" "$WT_PATH" "$BASE"
  fi
fi

SETUP_PID=""
HOOK="$REPO_ROOT/.claude/worktree-setup.sh"
if [[ -x "$HOOK" && ! -f "$SETUP_LOG" ]]; then
  echo "==> Running .claude/worktree-setup.sh in the background (log: .claude/worktrees/$SLUG-setup.log)"
  ( cd "$WT_PATH" && "$HOOK" "$SLUG" "$BRANCH" ) > "$SETUP_LOG" 2>&1 &
  SETUP_PID=$!; disown "$SETUP_PID"
fi

# ---- the Herdr workspace ----------------------------------------------------

if [[ $IN_HERDR -eq 0 ]]; then
  cat <<HINT
==> Not attached to Herdr; open the workspace later from a Herdr pane with:
    herdr worktree open --cwd "$REPO_ROOT" --path "$WT_PATH" --label "$SLUG" $FOCUS
==> Ready: $WT_PATH
HINT
  [[ -n "$SETUP_PID" ]] && echo "    Setup running (pid $SETUP_PID): grep -q 'Done. Worktree ready' '$SETUP_LOG'"
  exit 0
fi

herdr_json() {
  local out
  if ! out="$(herdr "$@" 2>&1)"; then
    echo "$out" | jq -r '.error.message // .' >&2 2>/dev/null || echo "$out" >&2
    die "herdr $1 ${2:-} failed"
  fi
  printf '%s' "$out"
}

PANE_JSON="$(herdr_json pane current --current)"
PANE_ID="$(jq -r '.result.pane.pane_id' <<< "$PANE_JSON")"
PANE_WS="$(jq -r '.result.pane.workspace_id' <<< "$PANE_JSON")"

OPEN_JSON="$(herdr_json worktree open --cwd "$REPO_ROOT" --path "$WT_PATH" --label "$SLUG" --no-focus)"
WS_ID="$(jq -r '.result.workspace.workspace_id' <<< "$OPEN_JSON")"
ALREADY_OPEN="$(jq -r '.result.already_open // false' <<< "$OPEN_JSON")"
[[ -n "$WS_ID" && "$WS_ID" != "null" ]] || die "herdr worktree open returned no workspace id"

if [[ "$ALREADY_OPEN" == "true" ]]; then
  echo "==> Herdr workspace $WS_ID already holds .claude/worktrees/$SLUG"
else
  echo "==> Opened Herdr workspace $WS_ID for .claude/worktrees/$SLUG (grouped under $(basename "$REPO_ROOT"))"
fi

AGENT_TAB=""
if [[ "$PANE_WS" == "$WS_ID" ]]; then
  echo "==> Pane $PANE_ID is already in workspace $WS_ID"
  AGENT_TAB="$(jq -r '.result.pane.tab_id // empty' <<< "$PANE_JSON")"
elif [[ "$ALREADY_OPEN" == "true" ]]; then
  echo "==> Moving pane $PANE_ID into workspace $WS_ID (new tab)"
  MOVE_JSON="$(herdr_json pane move "$PANE_ID" --workspace "$WS_ID" --new-tab "$FOCUS")"
  AGENT_TAB="$(jq -r '.result.move_result.pane.tab_id // empty' <<< "$MOVE_JSON")"
else
  # Fresh workspace: take over its placeholder shell's tab, then close the shell.
  ROOT_JSON="$(herdr_json pane list --workspace "$WS_ID")"
  ROOT_PANE="$(jq -r '.result.panes[0].pane_id // empty' <<< "$ROOT_JSON")"
  ROOT_TAB="$(jq -r '.result.panes[0].tab_id // empty' <<< "$ROOT_JSON")"
  echo "==> Moving pane $PANE_ID into workspace $WS_ID (root tab $ROOT_TAB)"
  if [[ -n "$ROOT_TAB" ]]; then
    MOVE_JSON="$(herdr_json pane move "$PANE_ID" --tab "$ROOT_TAB" --split right "$FOCUS")"
    herdr_json pane close "$ROOT_PANE" >/dev/null
  else
    MOVE_JSON="$(herdr_json pane move "$PANE_ID" --workspace "$WS_ID" --new-tab "$FOCUS")"
  fi
  AGENT_TAB="$(jq -r '.result.move_result.pane.tab_id // empty' <<< "$MOVE_JSON")"
fi

if [[ "$FOCUS" == "--focus" ]]; then
  [[ -n "$AGENT_TAB" ]] && herdr_json tab focus "$AGENT_TAB" >/dev/null
  herdr_json workspace focus "$WS_ID" >/dev/null
  echo "==> Focused workspace $WS_ID${AGENT_TAB:+, tab $AGENT_TAB}"
fi

echo "==> Ready: $WT_PATH"
[[ -n "$CHAINED" ]] && echo "    Chained from $CHAINED: EnterWorktree with this path still works (it is under .claude/worktrees/)."
[[ -n "$SETUP_PID" ]] && echo "    Setup running (pid $SETUP_PID): grep -q 'Done. Worktree ready' '$SETUP_LOG'"
echo "==> Next: EnterWorktree path=\"$WT_PATH\""
