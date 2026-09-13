---
name: create-pull-request
description: Use when the user wants to open a GitHub pull request — drafts a conventional-commit-style title and structured body, pushes the current branch, and auto-selects labels by matching the repo's available GitHub labels against the diff. Triggers on "create a PR", "open a pull request", "raise a PR", "submit this for review".
---

# Create Pull Request

## Overview

Open a GitHub PR from the current branch with a well-formed title, a structured body, and
labels chosen by matching the repo's *actual* available labels against the change. Labels are
proposed automatically and confirmed with the user before the PR is created.

## When to use

Use when the user asks to open/create/raise/submit a pull request, or when a branch of work is
ready for review and a PR is the next step.

## Prerequisites

- `gh` CLI installed and authenticated (`gh auth status`). If not authenticated, stop and tell
  the user to run `gh auth login` (suggest they type `! gh auth login` in this session).
- Work committed on a non-default branch. Never commit on the user's behalf without their
  intent; if uncommitted changes belong in the PR, confirm and commit first.

## Workflow

Follow these steps in order.

### 1. Gather context

Run the bundled script from the repo root — it collects branch state, any existing PR, the
repo's labels (with descriptions), the commit list, and the diffstat in one call:

```bash
"$HOME/.claude/skills/create-pull-request/scripts/pr_context.sh"
```

Read each section of the output:
- **BRANCH** — confirm the current branch is not the default branch, and note whether an
  upstream exists (`(none — needs push -u)` means a first push is required).
- **EXISTING_PR** — if a PR already exists for this branch, do NOT create a second one. Offer to
  update it (`gh pr edit`) or just report its URL instead.
- **AVAILABLE_LABELS** — the only labels that may be applied. Never invent label names; `gh pr
  create --label X` fails the entire command if `X` doesn't exist in the repo.
- **COMMITS_ON_BRANCH** / **DIFFSTAT** — the substance of the change, for drafting and matching.

If the diff is large or the diffstat is ambiguous, inspect specifics with
`git diff <default>...HEAD` before drafting.

### 2. Draft title and body

- **Title**: conventional-commit style (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`,
  `test:`), imperative, concise. If the branch is a single logical change, mirror its commit.
- **Body**: short markdown —
  - `## Summary` — 1–3 bullets on what changed and why.
  - `## Test plan` — how it was verified (commands run, checks passed) or what still needs
    testing. Be honest: if something wasn't tested, say so.

If the repo has a PR template at `.github/pull_request_template.md`, fill that in instead of
imposing the structure above.

### 3. Auto-select labels

Match the change against **AVAILABLE_LABELS** using both the label name and its description:

- Map change type to labels: `fix:` → a `bug` label; new functionality → `feature` /
  `enhancement`; docs-only → `documentation`; dependency bumps → `dependencies`. Use the
  descriptions to disambiguate similarly named labels.
- Match touched areas to scoped labels (e.g. `frontend`, `backend`, `area/api`) when the
  diffstat clearly implicates that area.
- Prefer precision over coverage: only propose labels with clear evidence. 1–3 labels is
  typical. If nothing matches confidently, propose none.
- If the repo has no labels, skip labeling entirely.

### 4. Confirm before creating

Present the drafted title, body, base branch (the repo default), and proposed labels to the
user compactly, and ask for confirmation or edits. Do not create the PR until the user confirms.

### 5. Push and create

After confirmation:

```bash
# Push the current branch, setting upstream if needed.
git push -u origin HEAD

# Create the PR against the default branch with the confirmed labels.
# Use --body-file with a heredoc to avoid shell-quoting issues on multi-line bodies.
gh pr create \
  --base "<default-branch>" \
  --title "<title>" \
  --label "<label-1>" --label "<label-2>" \
  --body-file - <<'EOF'
## Summary
...

## Test plan
...
EOF
```

Notes:
- Pass each label with its own `--label` flag, using the exact names from AVAILABLE_LABELS.
- If `gh pr create` rejects a label, it usually means a name mismatch — re-check against
  AVAILABLE_LABELS, drop the offending label, and retry. Labels can also be added afterward with
  `gh pr edit <num> --add-label`.

### 6. Report

Print the PR URL returned by `gh pr create` and a one-line summary of the title and applied
labels.

## Resources

- `scripts/pr_context.sh` — one-shot context gatherer (branch, existing PR, labels+descriptions,
  commits, diffstat). Requires an authenticated `gh`.
