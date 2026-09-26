#!/usr/bin/env bash
# Survey a repo's test setup before writing or auditing tests.
#
#   test_context.sh              labeled sections: agent docs, per-stack test,
#                                format and lint commands, task runners, CI test
#                                lines, test surface size, skip/focus markers,
#                                running watch-mode runners
#   test_context.sh diff [BASE]  split `git diff --numstat BASE` (default HEAD,
#                                i.e. uncommitted work) into tests, test support,
#                                production and other
#
# Covers Ruby, JavaScript/TypeScript, Python and Rust. Read-only.
# Requires: git. Optional: jq or node (to list package.json scripts).
set -uo pipefail

section() { printf '\n===== %s =====\n' "$1"; }
has() { command -v "$1" >/dev/null 2>&1; }
or_none() { local s; s="$(cat)"; if [ -n "$s" ]; then printf '%s\n' "$s"; else echo "${1:-(none)}"; fi; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not in a git repo" >&2; exit 1; }
cd "$ROOT" || exit 1

SKIP_DIRS='(^|/)(node_modules|vendor|target|\.venv|venv|\.tox|dist|build|coverage|tmp)/'
FIXTURE_DIRS='(^|/)(fixtures?|testdata|__fixtures__|__snapshots__|cassettes|snapshots)/'

# Test files, by stack.
RB_TEST='(^|/)spec/.*_spec\.rb$|(^|/)test/.*_test\.rb$'
JS_TEST='\.(test|spec)\.[cm]?[jt]sx?$|(^|/)__tests__/.*\.[cm]?[jt]sx?$'
PY_TEST='(^|/)test_[^/]*\.py$|_test\.py$'
RS_TEST='(^|/)tests/.*\.rs$'
ALL_TEST="$RB_TEST|$JS_TEST|$PY_TEST|$RS_TEST"
# Test support: helpers, factories, fixtures, conftest, snapshots.
SUPPORT='(^|/)(spec|test|tests|__tests__)/(support|factories|helpers?|shared|fixtures?|mocks?|__mocks__|__snapshots__|cassettes|snapshots|testdata)/|(^|/)(spec_helper|rails_helper|test_helper)\.rb$|(^|/)conftest\.py$|(^|/)(test-utils?|test_utils|testing|testutil)(/|\.[a-z]+$)|(^|/)(vitest|jest|playwright)\.(config|setup)\.[cm]?[jt]s$|(^|/)\.rspec$|(^|/)(pytest|tox)\.ini$|\.snap$'

# ---------------------------------------------------------------- diff mode
if [ "${1:-}" = "diff" ]; then
  BASE="${2:-HEAD}"
  git diff --numstat "$BASE" -- . >/dev/null 2>&1 || { echo "ERROR: cannot diff against $BASE" >&2; exit 1; }
  section "DIFF_SPLIT (git diff --numstat $BASE)"
  { git diff --numstat "$BASE" -- .
    # Untracked files count as all-added.
    git ls-files --others --exclude-standard | while IFS= read -r f; do
      [ -f "$f" ] && printf '%s\t0\t%s\n' "$(wc -l < "$f" | tr -d ' ')" "$f"
    done
  } | SUPPORT="$SUPPORT" TESTS="$ALL_TEST" \
      OTHER='(^|/)(README|CHANGELOG|LICEN[CS]E)[^/]*$|\.(md|txt|lock)$|(^|/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock)$' \
      awk -F'\t' '
    BEGIN { support = ENVIRON["SUPPORT"]; test = ENVIRON["TESTS"]; other = ENVIRON["OTHER"] }
    { add = ($1 == "-") ? 0 : $1; del = ($2 == "-") ? 0 : $2; f = $3
      if (f ~ support) k = "test support"
      else if (f ~ test) k = "tests"
      else if (f ~ other) k = "docs/locks/other"
      else k = "production/tooling"
      a[k] += add; d[k] += del; n[k]++
      if (k == "production/tooling" && f ~ /\.rs$/) rs = 1 }
    END {
      split("tests|test support|production/tooling|docs/locks/other", order, "|")
      for (i = 1; i <= 4; i++) { k = order[i]
        printf "%-20s %4d files  +%-6d -%-6d net %+d\n", k ":", n[k], a[k], d[k], a[k] - d[k] }
      if (rs) print "note: Rust in-module tests (#[cfg(test)] mod tests) count as production here; count them by hand."
    }'
  exit 0
fi

# ---------------------------------------------------------------- survey mode
FILES="$(git ls-files --cached --others --exclude-standard | grep -vE "$SKIP_DIRS")"
matching() { printf '%s\n' "$FILES" | grep -E "$1"; }
existing() { while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done; }
dirs_of() { while IFS= read -r f; do dirname "$f"; done | sort -u; }
lock_in() { # lock_in <dir> <file>...: first lockfile found in dir, else repo root
  local d="$1" f; shift
  for f in "$@"; do [ -f "$d/$f" ] && { echo "$d/$f"; return; }; done
  for f in "$@"; do [ -f "$f" ] && { echo "$f"; return; }; done
}
# libs_in <file> <name>...: names that appear quoted or as keys in a manifest/lockfile
libs_in() {
  local file="$1" found="" n; shift
  [ -f "$file" ] || return
  for n in "$@"; do grep -qE "(^|[\"' ])${n}([\"' =:(]|$)" "$file" && found="$found $n"; done
  [ -n "$found" ] && echo "test libs:${found}"
}

section "REPO"
echo "root: $ROOT"
echo "head: $(git rev-parse --short HEAD 2>/dev/null || echo '(no commits)') on $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
echo "uncommitted changes: $(git status --porcelain | wc -l | tr -d ' ')"

section "AGENT_DOCS"
matching '(^|/)(AGENTS|CLAUDE|CONTRIBUTING)\.md$|(^|/)docs/[^/]*test[^/]*\.md$' | grep -vE "$FIXTURE_DIRS" | head -30 | or_none

# --- Ruby
RB_DIRS="$(matching '(^|/)Gemfile$' | grep -vE "$FIXTURE_DIRS" | dirs_of | head -10)"
for d in $RB_DIRS; do
  section "RUBY ($d)"
  lock="$d/Gemfile.lock"
  if grep -qs 'rspec-core' "$lock" || [ -f "$d/.rspec" ]; then
    echo "runner: bundle exec rspec <path>[:<line>]    filter: -e '<example>'"
  fi
  if [ -x "$d/bin/rails" ] && [ -d "$d/test" ]; then
    echo "runner: bin/rails test <path>[:<line>]    filter: -n /<pattern>/"
  elif grep -qs ' minitest ' "$lock" && [ -d "$d/test" ]; then
    echo "runner: bundle exec ruby -Itest <path> -n /<pattern>/"
  fi
  grep -qs ' standard ' "$lock" && echo "format: bundle exec standardrb --fix <paths>"
  grep -qs ' rubocop ' "$lock" && ! grep -qs ' standard ' "$lock" && echo "format: bundle exec rubocop -a <paths>"
  grep -qs ' sorbet ' "$lock" && echo "types:  bundle exec srb tc"
  libs_in "$lock" factory_bot webmock vcr mocha capybara shoulda-matchers timecop simplecov rspec-snapshot mutant guard
done

# --- JavaScript / TypeScript
JS_DIRS="$(matching '(^|/)package\.json$' | grep -vE "$FIXTURE_DIRS" | dirs_of | head -12)"
for d in $JS_DIRS; do
  pkg="$d/package.json"
  section "JAVASCRIPT ($d)"
  lock="$(lock_in "$d" pnpm-lock.yaml yarn.lock bun.lock bun.lockb package-lock.json)"
  case "$lock" in
    *pnpm-lock.yaml) x="pnpm exec" ;;
    *yarn.lock) x="yarn" ;;
    *bun.lock*) x="bunx" ;;
    *) x="npx" ;;
  esac
  echo "package manager: ${lock:-(no lockfile, assuming npm)}"
  dep() { grep -qE "\"$1\"[[:space:]]*:" "$pkg"; }
  dep vitest && echo "runner: $x vitest run <path> -t '<name>'    (plain \`vitest\` is watch mode)"
  dep jest && echo "runner: $x jest <path> -t '<name>'"
  dep mocha && echo "runner: $x mocha <path> --grep '<name>'"
  dep ava && echo "runner: $x ava <path> --match '<name>'"
  dep '@playwright/test' && echo "runner: $x playwright test <path> -g '<name>'"
  dep cypress && echo "runner: $x cypress run --spec <path>"
  grep -qE '"test"[[:space:]]*:[[:space:]]*"[^"]*node --test' "$pkg" && echo "runner: node --test --test-name-pattern='<name>' <path>"
  grep -qE '"test"[[:space:]]*:[[:space:]]*"bun test' "$pkg" && echo "runner: bun test <path> -t '<name>'"
  dep '@biomejs/biome' && echo "format: $x biome check --write <paths>"
  dep prettier && echo "format: $x prettier --write <paths>"
  dep eslint && echo "lint:   $x eslint --fix <paths>"
  dep typescript && echo "types:  $x tsc --noEmit"
  dep knip && echo "dead code: $x knip"
  found=""; for n in @testing-library/react @testing-library/dom msw nock sinon supertest c8 nyc @vitest/coverage-v8 fast-check @stryker-mutator/core happy-dom jsdom; do dep "$n" && found="$found $n"; done
  [ -n "$found" ] && echo "test libs:$found"
  if has jq; then
    s="$(jq -r '.scripts // {} | to_entries[] | select(.key | test("test|spec|lint|format|fmt|check|type|ci|e2e")) | "  \(.key): \(.value)"' "$pkg" 2>/dev/null)"
  elif has node; then
    s="$(node -e 'const s=require(process.argv[1]).scripts||{};for(const[k,v]of Object.entries(s))if(/test|spec|lint|format|fmt|check|type|ci|e2e/.test(k))console.log(`  ${k}: ${v}`)' "$ROOT/$pkg" 2>/dev/null)"
  else
    s="  (install jq or node to list scripts)"
  fi
  [ -n "$s" ] && { echo "scripts:"; echo "$s"; }
done

# --- Python
PY_DIRS="$(matching '(^|/)(pyproject\.toml|setup\.py|setup\.cfg|requirements[^/]*\.txt|pytest\.ini|tox\.ini|manage\.py)$' | grep -vE "$FIXTURE_DIRS" | dirs_of | head -10)"
for d in $PY_DIRS; do
  section "PYTHON ($d)"
  lock="$(lock_in "$d" uv.lock poetry.lock pdm.lock Pipfile.lock)"
  case "$lock" in
    *uv.lock) p="uv run " ;;
    *poetry.lock) p="poetry run " ;;
    *pdm.lock) p="pdm run " ;;
    *Pipfile.lock) p="pipenv run " ;;
    *) p="" ;;
  esac
  echo "env: ${lock:-(no lockfile; activate the project venv first)}"
  meta="$(cat "$d"/pyproject.toml "$d"/setup.cfg "$d"/requirements*.txt "$d"/tox.ini "$d"/pytest.ini $lock 2>/dev/null)"
  if grep -q 'pytest' <<<"$meta" || [ -f "$d/pytest.ini" ] || [ -n "$(matching "^${d#.}/?.*conftest\.py$")" ]; then
    echo "runner: ${p}pytest <path>::<test> -q    filter: -k '<expr>'    rerun failures: --lf"
  else
    echo "runner: ${p}python -m unittest <dotted.module.Class.test>"
  fi
  [ -f "$d/manage.py" ] && ! grep -q 'pytest-django' <<<"$meta" && echo "runner: ${p}python manage.py test <app.tests.module>"
  [ -f "$d/tox.ini" ] && echo "matrix: tox -e <env>"
  [ -f "$d/noxfile.py" ] && echo "matrix: nox -s <session>"
  if [ -f "$d/ruff.toml" ] || [ -f "$d/.ruff.toml" ] || grep -q 'tool.ruff' <<<"$meta"; then
    echo "format: ${p}ruff format <paths> && ${p}ruff check --fix <paths>"
  elif grep -qE '(^|[^a-z])black([^a-z]|$)' <<<"$meta"; then
    echo "format: ${p}black <paths>"
  fi
  grep -qE 'tool\.mypy|(^|[" ])mypy' <<<"$meta" && echo "types:  ${p}mypy <paths>"
  grep -qE 'tool\.pyright|(^|[" ])pyright' <<<"$meta" && echo "types:  ${p}pyright <paths>"
  found=""; for n in pytest-mock pytest-django pytest-asyncio pytest-cov hypothesis responses respx vcrpy freezegun syrupy factory-boy mutmut pytest-watch; do grep -qi "$n" <<<"$meta" && found="$found $n"; done
  [ -n "$found" ] && echo "test libs:$found"
done

# --- Rust
RS_MANIFESTS="$(matching '(^|/)Cargo\.toml$' | grep -vE "$FIXTURE_DIRS")"
if [ -n "$RS_MANIFESTS" ]; then
  section "RUST"
  ws="$(printf '%s\n' "$RS_MANIFESTS" | while IFS= read -r m; do grep -qs '^\[workspace\]' "$m" && echo "$m"; done | head -1)"
  echo "run from: $(dirname "${ws:-$(printf '%s\n' "$RS_MANIFESTS" | awk '{ print length, $0 }' | sort -n | head -1 | cut -d' ' -f2-)}")"
  echo "crates:"
  printf '%s\n' "$RS_MANIFESTS" | while IFS= read -r m; do
    n="$(awk '/^\[package\]/{p=1; next} /^\[/{p=0} p && /^name *=/{gsub(/[" ]/, "", $0); sub(/^name=/, ""); print; exit}' "$m")"
    [ -n "$n" ] && echo "  $n ($m)"
  done
  echo "runner: cargo test -p <crate> <path::filter>    exact: -- --exact    integration file: --test <stem>    doctests: --doc"
  if [ -f .config/nextest.toml ] || cargo nextest --version >/dev/null 2>&1; then
    echo "runner: cargo nextest run -p <crate> <filter>    (skips doctests; run cargo test --doc too)"
  fi
  [ -n "$(printf '%s\n' "$RS_MANIFESTS" | xargs grep -ls '^\[features\]')" ] \
    && echo "features: some crates declare [features]; feature-gated tests only run with --features/--all-features"
  echo "format: cargo fmt -p <crate>    lint: cargo clippy -p <crate> --all-targets"
  found=""; for n in mockall insta proptest quickcheck rstest test-case wiremock httpmock assert_cmd trycmd trybuild pretty_assertions serial_test; do
    printf '%s\n' "$RS_MANIFESTS" | xargs grep -qsE "^${n}[[:space:]]*=|^\[(dev-)?dependencies\.${n}\]" && found="$found $n"
  done
  [ -n "$found" ] && echo "test libs:$found"
fi

section "TASK_RUNNERS"
{
  for f in Makefile makefile GNUmakefile; do
    [ -f "$f" ] && grep -oE '^[A-Za-z0-9_.-]+:' "$f" | tr -d ':' | grep -iE 'test|spec|lint|fmt|format|check|ci|cov' | sed "s|^|$f: make |"
  done
  for f in justfile Justfile .justfile; do
    [ -f "$f" ] && grep -oE '^@?[A-Za-z0-9_-]+' "$f" | tr -d '@' | grep -iE 'test|spec|lint|fmt|format|check|ci|cov' | sort -u | sed "s|^|$f: just |"
  done
  [ -f Rakefile ] && grep -oE 'task[[:space:]]*\(?:?[A-Za-z0-9_]+' Rakefile | grep -iE 'test|spec|lint|ci' | sed 's|^|Rakefile: |'
  [ -f Taskfile.yml ] && echo "Taskfile.yml: task --list"
  for f in bin/* script/* scripts/*; do
    [ -f "$f" ] && [ -x "$f" ] && basename "$f" | grep -qiE 'test|spec|ci|lint|check|fmt|format' && echo "$f"
  done
  for f in .pre-commit-config.yaml lefthook.yml .lefthook.yml .overcommit.yml .husky; do
    [ -e "$f" ] && echo "hooks: $f"
  done
} | head -40 | or_none

section "CI"
CI_FILES="$(matching '^\.github/workflows/[^/]+\.ya?ml$|^\.gitlab-ci\.yml$|^\.circleci/config\.yml$|^\.buildkite/|^Jenkinsfile$|^azure-pipelines\.yml$|^bitbucket-pipelines\.yml$|^\.woodpecker|^config/ci\.rb$')"
if [ -n "$CI_FILES" ]; then
  printf '%s\n' "$CI_FILES" | while IFS= read -r f; do
    if [ "$f" = config/ci.rb ]; then grep -HnE '^[[:space:]]*step ' "$f"; continue; fi
    grep -nE 'rspec|rails ([a-z:_]+ )*test|bin/(test|ci|rspec)|[ /]rake( |$)|minitest|pytest|unittest|tox|nox|cargo (test|nextest|clippy|fmt)|vitest|jest|mocha|playwright|cypress|(npm|pnpm|yarn|bun)( run)? (test|lint|check|typecheck|ci)|tsc|ruff|mypy|rubocop|standardrb|make [a-z]|just [a-z]|--cov|coverage' /dev/null "$f" \
      | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'
  done | sed -E 's|:([0-9]+):[[:space:]]*|:\1: |' | head -40
else
  echo "(no CI config found)"
fi

section "TEST_SURFACE (approximate)"
surface() { # surface <label> <test regex> <declaration regex>
  local list n lines decls
  list="$(matching "$2" | grep -vE "$FIXTURE_DIRS|$SUPPORT" | existing)"
  [ -n "$list" ] || return
  n="$(printf '%s\n' "$list" | wc -l | tr -d ' ')"
  lines="$(printf '%s\n' "$list" | tr '\n' '\0' | xargs -0 cat | wc -l | tr -d ' ')"
  decls="$(printf '%s\n' "$list" | tr '\n' '\0' | xargs -0 grep -hE "$3" 2>/dev/null | wc -l | tr -d ' ')"
  printf '%-8s %5s files %7s lines %6s test declarations\n' "$1" "$n" "$lines" "$decls"
}
surface ruby "$RB_TEST" '^[[:space:]]*(it|specify|scenario|example|test)[[:space:](]|^[[:space:]]*def test_'
surface js "$JS_TEST" '(^|[^.a-zA-Z_])(it|test)(\.(each|concurrent|skip|only|todo)[^(]*)?\('
surface python "$PY_TEST" '^[[:space:]]*(async )?def test_'
surface rust "$RS_TEST" '#\[([a-z_]+::)?test'
RS_UNIT="$(matching '\.rs$' | grep -vE "$RS_TEST|$FIXTURE_DIRS" | existing | tr '\n' '\0' | xargs -0 grep -l 'cfg(test)' 2>/dev/null)"
if [ -n "$RS_UNIT" ]; then
  printf 'rust     %5s src files with #[cfg(test)], %s test declarations in them\n' \
    "$(printf '%s\n' "$RS_UNIT" | wc -l | tr -d ' ')" \
    "$(printf '%s\n' "$RS_UNIT" | tr '\n' '\0' | xargs -0 grep -hE '#\[([a-z_]+::)?test' | wc -l | tr -d ' ')"
fi
SUPPORT_LIST="$(matching "$SUPPORT" | existing)"
[ -n "$SUPPORT_LIST" ] && printf 'support  %5s files %7s lines\n' \
  "$(printf '%s\n' "$SUPPORT_LIST" | wc -l | tr -d ' ')" \
  "$(printf '%s\n' "$SUPPORT_LIST" | tr '\n' '\0' | xargs -0 cat | wc -l | tr -d ' ')"

section "SKIP_MARKERS"
TEST_LIST="$(matching "$ALL_TEST" | grep -vE "$FIXTURE_DIRS" | existing; printf '%s\n' "$RS_UNIT")"
scan() { # scan <label> <regex>
  local hits
  hits="$(printf '%s\n' "$TEST_LIST" | grep . | tr '\n' '\0' | xargs -0 grep -nE "$2" 2>/dev/null)"
  [ -n "$hits" ] || return
  echo "$1: $(printf '%s\n' "$hits" | wc -l | tr -d ' ')"
  printf '%s\n' "$hits" | head -8 | cut -c1-160 | sed 's/^/  /'
}
{
scan "focused (suite silently shrinks)" '(^|[^a-zA-Z_.])(it|test|describe|context)\.only\(|^[[:space:]]*f(it|describe|context|specify)[[:space:](]|focus: *true|,[[:space:]]*:focus([^a-z_-]|$)'
scan "skipped / pending / ignored" '(^|[^a-zA-Z_.])(it|test|describe)\.(skip|todo)\(|^[[:space:]]*x(it|describe|context|specify|test)[[:space:](]|^[[:space:]]*(skip|pending)([[:space:]]*(\(|$)|[[:space:]]+["'"'"'a-z:])|@pytest\.mark\.(skip|skipif|xfail)|@unittest\.(skip|expectedFailure)|pytest\.(skip|xfail)\(|#\[ignore'
true
} | or_none "$( [ -n "$(printf '%s\n' "$TEST_LIST" | grep .)" ] && echo "(none)" || echo "(no test files found)")"

section "WATCH_RUNNERS"
ps -eo pid=,args= 2>/dev/null \
  | grep -E '(^|[/ ])(vitest|guard|ptw|pytest-watch|bacon|watchexec|nodemon|cargo-watch)( |$)|jest .*--watch|cargo watch' \
  | grep -vE 'grep|test_context\.sh' \
  | while read -r pid args; do
      cwd="$(readlink "/proc/$pid/cwd" 2>/dev/null || lsof -a -d cwd -p "$pid" -Fn 2>/dev/null | sed -n 's/^n//p')"
      case "$cwd" in "$ROOT"*) where="IN THIS CHECKOUT" ;; "") where="cwd unknown" ;; *) where="elsewhere: $cwd" ;; esac
      echo "$pid [$where] $(printf '%s' "$args" | cut -c1-120)"
    done | or_none
exit 0
