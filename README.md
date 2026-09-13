# claude-skills

My personal skills for [Claude Code](https://claude.com/claude-code). This folder
lives at `~/.claude/skills` on every machine I use. Git keeps the copies in sync.

A skill is a folder with a `SKILL.md` file. Claude reads the file when a task
matches its description. Some skills also ship scripts that do the real work.

## Install

One command on any machine, new or existing:

```bash
curl -fsSL https://raw.githubusercontent.com/vrodokanakis/claude-skills/main/sync.sh | bash
```

It clones the repo into `~/.claude/skills` (or pulls if it is already there),
links every skill for Codex, and adds a `skills-sync` alias to your shell.
Open a new shell, then restart Claude Code. Run `/` in the prompt to see the
skills listed.

> [!NOTE]
> If `~/.claude/skills` already exists (for example, your distro put skill
> links there), the script adopts it. Existing entries stay in place and git
> ignores them. Anything with the same name as a repo skill moves to
> `~/.claude/skills.local/`.

## Keep machines in sync

After you edit a skill:

```bash
cd ~/.claude/skills
git pull
git add -A
git commit -m "Describe the change"
git push
```

On every other machine, run:

```bash
skills-sync
```

It pulls the latest skills and refreshes the Codex links. Run it after you
add a new skill too.

## Use the same skills in OpenAI Codex

Codex reads skills from `~/.agents/skills`. `skills-sync` keeps a symlink
there for every skill, so nothing extra is needed. `link-codex.sh` does only
the linking step if you ever want it alone.

## Skills

| Skill | Use it when |
| --- | --- |
| `create-pull-request` | You want to open a GitHub pull request with a good title, body and labels. |
| `deep-research` | You need a long, cited research report with source quality checks. |
| `herdr` | You are inside [Herdr](https://herdr.dev) and want to control panes, tabs or agents. |
| `readme-writer` | You are writing a README or want to measure and lower the reading level of any prose. |
| `remix` | You are building a Remix 3 app. |
| `sandi-metz-rules` | You are reviewing Ruby code for size and clarity. |
| `skill-creator` | You want to create or improve a skill. |
| `worktree-space` | You are inside Herdr and want a new git worktree in its own workspace. |
| `tearing-down-a-merged-worktree` | A pull request merged and its worktree should go away. |

### Worktree skills and project hooks

`worktree-space` and `tearing-down-a-merged-worktree` work in any git repo.
They put worktrees under `<repo>/.claude/worktrees/<slug>`. A project can add
its own steps with two optional scripts in the repo:

| Script | Runs | Use it for |
| --- | --- | --- |
| `.claude/worktree-setup.sh <slug> <branch>` | inside the new worktree, in the background | installing gems, copying a database |
| `.claude/worktree-teardown.sh <slug> <branch>` | from the main checkout, after removal | dropping databases, deleting indexes |

> [!NOTE]
> The setup script must print `Done. Worktree ready` as its last line. The
> skill waits for that line before it runs anything that needs the database.

> [!IMPORTANT]
> If a repo ships its own `bin/worktree-herdr` or its own copy of these skills
> under `.claude/skills/`, the project version wins.

## Write a new skill

1. Make a folder: `mkdir ~/.claude/skills/my-skill`.
2. Add `SKILL.md` with `name` and `description` in the front matter. The
   description should say *when* to use the skill, not what it does.
3. Test it on a real task before you commit.

The `skill-creator` skill walks you through this.

Third-party skills and their upstream repos are listed in `SOURCES.md`.

## Layout

```
.
├── README.md
├── <skill-name>/
│   ├── SKILL.md        # required
│   └── scripts/        # optional helper scripts
└── ...
```

Scripts are Bash. They need `git`, `jq` and, for the Herdr parts, the `herdr`
CLI. They were written on macOS. Linux should work too but is not tested.

## License

MIT for the skills written here. Third-party skills keep their own licence; see `SOURCES.md`.
