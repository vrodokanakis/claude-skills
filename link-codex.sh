#!/usr/bin/env bash
# Expose every skill in this repo to OpenAI Codex (and other runtimes that read
# ~/.agents/skills) by symlinking each skill folder there. Safe to re-run.
# Existing real folders with the same name are replaced (a copy is kept in
# ~/.agents/skills.bak/ the first time).
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
DST="$HOME/.agents/skills"
mkdir -p "$DST"
for d in "$SRC"/*/; do
  name="$(basename "$d")"
  [[ -f "$d/SKILL.md" ]] || continue
  if [[ -e "$DST/$name" && ! -L "$DST/$name" ]]; then
    mkdir -p "$HOME/.agents/skills.bak" && mv "$DST/$name" "$HOME/.agents/skills.bak/$name"
  fi
  ln -sfn "$SRC/$name" "$DST/$name"
  echo "linked $name"
done
# Drop dead symlinks left behind by older setups.
find "$DST" -maxdepth 1 -type l ! -exec test -e {} \; -print -delete | sed 's/^/removed dead link /'
