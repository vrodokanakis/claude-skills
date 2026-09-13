#!/usr/bin/env bash
# Gather everything needed to open a PR in one shot.
# Prints labeled sections so the agent can write a title/body and pick labels.
# Requires: git, gh (authenticated). Run from inside the repo.
set -uo pipefail

section() { printf '\n===== %s =====\n' "$1"; }

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh is not authenticated. Run: gh auth login" >&2
  exit 1
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not in a git repo" >&2; exit 1; }
DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)"
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
git fetch -q origin "$DEFAULT_BRANCH" 2>/dev/null
BASE="origin/${DEFAULT_BRANCH}"
git rev-parse -q --verify "$BASE" >/dev/null 2>&1 || BASE="$DEFAULT_BRANCH"

section "BRANCH"
echo "current: ${CURRENT_BRANCH}"
echo "default: ${DEFAULT_BRANCH}"
[ "${CURRENT_BRANCH}" = "${DEFAULT_BRANCH}" ] && echo "WARNING: on the default branch; create a feature branch first."
echo "upstream: $(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo '(none, needs push -u)')"
echo "uncommitted changes: $(git status --porcelain | wc -l | tr -d ' ')"

section "EXISTING_PR"
gh pr view --json number,url,state,title,isDraft 2>/dev/null \
  || echo "(no PR for this branch yet)"

section "AVAILABLE_LABELS"
gh label list --limit 200 --json name,description \
  -q '.[] | "- \(.name): \(.description // "")"' 2>/dev/null \
  || echo "(could not list labels; repo may have none or token lacks scope)"

section "COMMITS_ON_BRANCH"
git log --no-merges --pretty=format:'- %s' "${BASE}..HEAD" 2>/dev/null \
  || echo "(could not compute commit range against ${BASE})"
echo

section "DIFFSTAT"
git diff --stat "${BASE}...HEAD" 2>/dev/null \
  || echo "(could not compute diff against ${BASE})"

section "PR_TEMPLATE"
FOUND=0
for t in .github/pull_request_template.md .github/PULL_REQUEST_TEMPLATE.md pull_request_template.md docs/pull_request_template.md; do
  if [ -f "$ROOT/$t" ]; then echo "file: $t"; cat "$ROOT/$t"; FOUND=1; break; fi
done
[ "$FOUND" = 1 ] || echo "(none)"

section "REPO_RULES"
# Lines about PRs or labels from the repo's agent instructions.
for f in CLAUDE.md AGENTS.md .claude/CLAUDE.md; do
  [ -f "$ROOT/$f" ] || continue
  grep -n -i -E 'label|pull request|\bPRs?\b|draft|co-author' "$ROOT/$f" | sed "s|^|$f:|"
done | grep . || echo "(none found)"
