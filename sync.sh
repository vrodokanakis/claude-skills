#!/usr/bin/env bash
# Install or update the skills on this machine and link them for Codex.
# One-liner for a fresh machine:
#   curl -fsSL https://raw.githubusercontent.com/vrodokanakis/claude-skills/main/sync.sh | bash
set -euo pipefail
REPO="https://github.com/vrodokanakis/claude-skills"
DIR="$HOME/.claude/skills"
if [[ -d "$DIR/.git" ]]; then
  git -C "$DIR" pull --ff-only
elif [[ -d "$DIR" ]]; then
  # Folder exists but is not this repo (e.g. distro-provided skill symlinks).
  # Turn it into a clone in place and keep the existing entries as local,
  # untracked files that git ignores.
  echo "$DIR exists; adopting it into the repo and keeping its contents"
  git -C "$DIR" init -q -b main
  git -C "$DIR" remote add origin "$REPO"
  git -C "$DIR" fetch -q origin main
  for e in "$DIR"/* "$DIR"/.[!.]*; do
    [[ -e "$e" || -L "$e" ]] || continue
    n="$(basename "$e")"; [[ "$n" == ".git" ]] && continue
    if git -C "$DIR" cat-file -e "origin/main:$n" 2>/dev/null; then
      echo "  $n clashes with the repo; moved to $DIR.local/$n"
      mkdir -p "$DIR.local" && mv "$e" "$DIR.local/$n"
    else
      echo "/$n" >> "$DIR/.git/info/exclude"
      echo "  kept $n (local only)"
    fi
  done
  git -C "$DIR" checkout -q -b main origin/main 2>/dev/null || git -C "$DIR" reset -q --hard origin/main
  git -C "$DIR" branch -q --set-upstream-to=origin/main main
elif [[ -e "$DIR" ]]; then
  echo "$DIR exists and is not a directory. Move it away and re-run." >&2; exit 1
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
