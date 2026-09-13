#!/usr/bin/env bash
# Install or update the skills on this machine and link them for Codex.
# One-liner for a fresh machine:
#   curl -fsSL https://raw.githubusercontent.com/vrodokanakis/claude-skills/main/sync.sh | bash
set -euo pipefail
REPO="https://github.com/vrodokanakis/claude-skills"
DIR="$HOME/.claude/skills"
if [[ -d "$DIR/.git" ]]; then
  git -C "$DIR" pull --ff-only
elif [[ -e "$DIR" ]]; then
  echo "$DIR exists but is not this repo. Move it away and re-run." >&2; exit 1
else
  git clone "$REPO" "$DIR"
fi
"$DIR/link-codex.sh"
# Shell alias so next time it is just: skills-sync
RC="$HOME/.zshrc"; [[ -n "${BASH_VERSION:-}" && ! -f "$RC" ]] && RC="$HOME/.bashrc"
if [[ -w "$RC" || ! -e "$RC" ]] && ! grep -q 'alias skills-sync=' "$RC" 2>/dev/null; then
  printf '\nalias skills-sync="%s/sync.sh"\n' "$DIR" >> "$RC"
  echo "added alias skills-sync to $RC (open a new shell)"
fi
