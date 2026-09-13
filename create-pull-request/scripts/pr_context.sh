#!/usr/bin/env bash
# Gather everything needed to open a PR in one shot.
# Prints labeled sections so Claude can draft a title/body and pick labels.
# Requires: git, gh (authenticated). Run from inside the repo.
set -uo pipefail

section() { printf '\n===== %s =====\n' "$1"; }

# Fail fast if gh isn't authenticated.
if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh is not authenticated. Run: gh auth login" >&2
  exit 1
fi

DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)"
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"

section "BRANCH"
echo "current: ${CURRENT_BRANCH}"
echo "default: ${DEFAULT_BRANCH}"
if [ -n "${CURRENT_BRANCH}" ] && [ "${CURRENT_BRANCH}" = "${DEFAULT_BRANCH}" ]; then
  echo "WARNING: current branch is the default branch — create a feature branch before opening a PR."
fi
echo "upstream: $(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo '(none — needs push -u)')"

section "EXISTING_PR"
gh pr view --json number,url,state,title 2>/dev/null \
  || echo "(no PR exists for this branch yet)"

section "AVAILABLE_LABELS"
# name + description so labels can be matched semantically, not just by name.
gh label list --limit 200 --json name,description \
  -q '.[] | "- \(.name): \(.description // "")"' 2>/dev/null \
  || echo "(could not list labels — repo may have none or token lacks scope)"

section "COMMITS_ON_BRANCH"
git log --no-merges --pretty=format:'- %s' "${DEFAULT_BRANCH}..HEAD" 2>/dev/null \
  || echo "(could not compute commit range against ${DEFAULT_BRANCH})"

section "DIFFSTAT"
git diff --stat "${DEFAULT_BRANCH}...HEAD" 2>/dev/null \
  || echo "(could not compute diff against ${DEFAULT_BRANCH})"
