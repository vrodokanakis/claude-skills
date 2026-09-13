---
name: create-pull-request
description: Use when the user wants to open a GitHub pull request for the current branch. Triggers on "create a PR", "open a pull request", "raise a PR", "submit this for review", "PR this".
---

# Create Pull Request

Open the PR in one pass. Do not ask for confirmation of the title, body or
labels; the user asked for a PR, so make it. Ask only when something blocks
creation (see Stop conditions).

## Workflow

### 1. Gather context

```bash
"$HOME/.claude/skills/create-pull-request/scripts/pr_context.sh"
```

Read the sections:
- **BRANCH**: current must not be the default branch.
- **EXISTING_PR**: if one exists, do not create a second. Update it with
  `gh pr edit` and report its URL.
- **AVAILABLE_LABELS**: the only label names allowed. An unknown name fails
  the whole `gh pr create` call.
- **COMMITS_ON_BRANCH** / **DIFFSTAT**: what changed. Read
  `git diff <default>...HEAD` for anything the diffstat leaves unclear.
- **PR_TEMPLATE**: if present, fill that template instead of the body below.
- **REPO_RULES**: label or PR rules from the repo's CLAUDE.md or AGENTS.md.
  They win over this skill.

### 2. Write the title

Conventional-commit prefix (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`,
`test:`), imperative, under 70 characters. One logical change: reuse its
commit subject.

### 3. Write the body

The body is exactly this, and nothing more:

```markdown
## What
<1 to 3 bullets. Each bullet: one plain sentence, under 15 words, says what changed.>

## Why
<1 sentence. The problem or need. Link the ticket if one exists.>

## Testing
<1 to 3 bullets: the commands run and their result, or "Not tested: <reason>".>
```

Rules for the words:
- Whole body under 100 words.
- Everyday words. Say "fix", not "remediate". Say "add", not "introduce".
- No adjectives about quality ("robust", "clean", "comprehensive").
- No file-by-file lists. The diff shows files.
- No repeat of the title in the first bullet.
- No "This PR" openers. Start bullets with a verb.

Good:

```markdown
## What
- Add a `--no-pr` flag to skip the merge check.
- Refuse to remove the main checkout.

## Why
Teardown ran on branches that never had a PR and failed at `gh pr view`.

## Testing
- Ran `worktree-teardown.sh feat-x --no-pr --force` in a throwaway repo. Worktree and branch removed.
- Not tested: the Herdr pane move.
```

### 4. Pick labels

From **AVAILABLE_LABELS** only, using name and description:
- `fix:` → bug label. New behaviour → feature or enhancement. Docs only →
  documentation. Dependency bumps → dependencies.
- Add area labels (`frontend`, `ruby`, `javascript`, `area/api`) when the
  diffstat clearly touches that area.
- 1 to 3 labels. None if nothing matches. Follow **REPO_RULES** if it names
  labels to always apply.

### 5. Push and create

```bash
git push -u origin HEAD
gh pr create --base "<default>" --title "<title>" \
  --label "<l1>" --label "<l2>" \
  --body-file - <<'BODY'
<body>
BODY
```

After the PR exists, make sure the branch is deleted on merge. That checkbox
on the PR page comes from a repo setting, so turn it on once per repo:

```bash
gh repo edit --delete-branch-on-merge
```

If that fails (no admin rights), say so in one line and tell the user to merge
with `gh pr merge --delete-branch`. Never skip this silently.

Add `--draft` if the user said draft, or if REPO_RULES says PRs open as
drafts. If `gh` rejects a label, drop it and retry. Add it later with
`gh pr edit <n> --add-label` only if the name was a typo on your side.

### 6. Report

One line: the PR URL, the title, the labels applied. Add "branch deletes on
merge" only if the repo setting could not be turned on. Nothing else.

## Stop conditions

Stop and tell the user, in one sentence each, when:
- `gh auth status` fails. Suggest `! gh auth login`.
- The current branch is the default branch.
- There are uncommitted changes. Never commit for the user unless they asked.
- A PR already exists and the user did not ask to update it.

## Resources

- `scripts/pr_context.sh`: branch state, existing PR, labels with
  descriptions, commits, diffstat, PR template, repo rules.
