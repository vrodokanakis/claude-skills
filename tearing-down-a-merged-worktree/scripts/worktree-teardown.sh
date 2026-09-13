#!/usr/bin/env bash

# Tear down a merged worktree: confirm the PR merged, move this Herdr pane
# home, remove the checkout and branch, run the project's teardown hook,
# delete the setup log, and report counts. Project-agnostic.
#
# Does NOT move the Claude session: call ExitWorktree (action keep) yourself
# after this script if the session is inside the worktree being removed.
#
# Optional project hook: <repo>/.claude/worktree-teardown.sh <slug> <branch>,
# run from the main checkout after the git removal, for data that outlives the
# checkout (databases, search indexes, containers). Its output is shown.
#
# Usage: worktree-teardown.sh <slug|path> [--pr <n>] [--no-pr] [--force]
#   <slug|path>  Worktree dir name under .claude/worktrees/ or any registered path.
#   --pr <n>     PR number to check; default: the PR for the worktree's branch.
#   --no-pr      Branch has no PR; skip the MERGED check (asks nothing, you own it).
#   --force      Remove even with a dirty tree (git worktree remove --force).

set -euo pipefail
die() { echo "Error: $*" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" && pwd)" \
  || die "not inside a git repository"

TARGET="" PR="" NO_PR=0 FORCE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr)    PR="${2:-}"; shift 2 ;;
    --no-pr) NO_PR=1; shift ;;
    --force) FORCE="--force"; shift ;;
    -*)      die "unknown option: $1" ;;
    *)       [[ -z "$TARGET" ]] || die "unexpected argument: $1"; TARGET="$1"; shift ;;
  esac
done
[[ -n "$TARGET" ]] || die "usage: worktree-teardown.sh <slug|path> [--pr <n>] [--no-pr] [--force]"

if [[ -d "$TARGET" ]]; then WT_PATH="$(cd "$TARGET" && pwd)"; else WT_PATH="$REPO_ROOT/.claude/worktrees/$TARGET"; fi
SLUG="$(basename "$WT_PATH")"
[[ "$WT_PATH" != "$REPO_ROOT" ]] || die "refusing to remove the main checkout"
git -C "$REPO_ROOT" worktree list --porcelain | grep -qx "worktree $WT_PATH" \
  || die "$WT_PATH is not a registered worktree of $REPO_ROOT"
BRANCH="$(git -C "$WT_PATH" rev-parse --abbrev-ref HEAD)"
SETUP_LOG="$REPO_ROOT/.claude/worktrees/$SLUG-setup.log"
echo "==> slug=$SLUG branch=$BRANCH path=$WT_PATH"

# ---- 1. the PR ---------------------------------------------------------------

if [[ $NO_PR -eq 0 ]]; then
  command -v gh >/dev/null || die "gh not installed; pass --no-pr if the branch has no PR"
  STATE="$(cd "$REPO_ROOT" && gh pr view "${PR:-$BRANCH}" --json state,number,mergeCommit \
    --jq '"\(.state) #\(.number) \(.mergeCommit.oid // "")"' 2>&1)" || die "gh pr view failed: $STATE"
  echo "==> PR: $STATE"
  [[ "$STATE" == MERGED* ]] || die "PR is not MERGED (CLOSED is not MERGED either); refusing"
fi

# ---- 2. the pane -------------------------------------------------------------

WS_NOTE="no Herdr"
if command -v herdr >/dev/null 2>&1 && [[ "${HERDR_ENV:-}" == "1" ]]; then
  LIST="$(herdr worktree list 2>/dev/null || echo '{}')"
  WT_WS="$(jq -r --arg p "$WT_PATH" '.result.worktrees[]? | select(.path==$p) | .open_workspace_id // empty' <<< "$LIST")"
  HOME_WS="$(jq -r --arg p "$REPO_ROOT" '.result.worktrees[]? | select(.path==$p) | .open_workspace_id // empty' <<< "$LIST")"
  PANE_JSON="$(herdr pane current --current)"
  PANE_ID="$(jq -r '.result.pane.pane_id' <<< "$PANE_JSON")"
  PANE_WS="$(jq -r '.result.pane.workspace_id' <<< "$PANE_JSON")"
  if [[ -n "$WT_WS" ]]; then
    if [[ "$PANE_WS" == "$WT_WS" ]]; then
      if [[ -z "$HOME_WS" ]]; then
        HOME_WS="$(herdr workspace create --cwd "$REPO_ROOT" --label "$(basename "$REPO_ROOT")" --no-focus | jq -r '.result.workspace.workspace_id')"
        echo "==> No home workspace; created $HOME_WS"
      fi
      MOVE="$(herdr pane move "$PANE_ID" --workspace "$HOME_WS" --new-tab --focus)"
      CLOSED="$(jq -r '.result.closed_workspace_id // empty' <<< "$MOVE")"
      echo "==> Moved pane $PANE_ID to home workspace $HOME_WS"
    fi
    if herdr workspace get "$WT_WS" >/dev/null 2>&1; then
      herdr workspace close "$WT_WS" >/dev/null 2>&1 && WS_NOTE="workspace $WT_WS closed" || WS_NOTE="workspace $WT_WS still open (close it yourself)"
    else
      WS_NOTE="workspace $WT_WS closed itself"
    fi
  else
    WS_NOTE="no workspace was open for it"
  fi
fi

# ---- 3. checkout and branch ---------------------------------------------------

if [[ -z "$FORCE" && -n "$(git -C "$WT_PATH" status --porcelain)" ]]; then
  git -C "$WT_PATH" status --short >&2
  die "worktree has uncommitted changes; inspect, then re-run with --force"
fi
git -C "$REPO_ROOT" worktree remove $FORCE "$WT_PATH"
[[ -d "$WT_PATH" ]] && { echo "==> Directory left behind; removing"; command rm -rf "$WT_PATH"; }
git -C "$REPO_ROOT" worktree prune
git -C "$REPO_ROOT" fetch -p -q 2>/dev/null || true
if [[ "$BRANCH" != "HEAD" ]]; then
  git -C "$REPO_ROOT" branch -D "$BRANCH" >/dev/null && echo "==> Deleted branch $BRANCH"
fi

# ---- 4. project data ----------------------------------------------------------

HOOK="$REPO_ROOT/.claude/worktree-teardown.sh"
HOOK_NOTE="no .claude/worktree-teardown.sh hook"
if [[ -x "$HOOK" ]]; then
  echo "==> Running .claude/worktree-teardown.sh $SLUG $BRANCH"
  (cd "$REPO_ROOT" && "$HOOK" "$SLUG" "$BRANCH") && HOOK_NOTE="hook ran OK" || HOOK_NOTE="hook FAILED (exit $?)"
fi

# ---- 5. log -----------------------------------------------------------------

LOG_NOTE="no setup log"
[[ -f "$SETUP_LOG" ]] && { command rm -f "$SETUP_LOG"; LOG_NOTE="setup log deleted"; }

cat <<REPORT

==> Teardown report for $SLUG
    branch:      $BRANCH deleted
    worktree:    $(git -C "$REPO_ROOT" worktree list --porcelain | grep -c "^worktree $WT_PATH\$" | sed 's/^0$/removed/; s/^[1-9].*/STILL REGISTERED/')
    herdr:       $WS_NOTE
    data hook:   $HOOK_NOTE
    log:         $LOG_NOTE
REPORT
[[ "$(jq -r '.result.pane.cwd // empty' <<< "${PANE_JSON:-{\}}" 2>/dev/null)" == "$WT_PATH"* ]] \
  && echo "    session:     still inside the removed dir -- call ExitWorktree (action keep) now"
exit 0
