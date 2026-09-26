# Stack notes

How the rules in [SKILL.md](../SKILL.md) map onto each language. Read only the
sections for the stacks in scope. The commands here are defaults; the
repo's own wrappers and `AGENTS.md`/`CLAUDE.md` rules win.

Contents: [Ruby](#ruby) · [JavaScript / TypeScript](#javascript--typescript) ·
[Python](#python) · [Rust](#rust)

## Ruby

**Focused run.** RSpec: `bundle exec rspec spec/models/user_spec.rb:42`, or
`-e '<example text>'`; `--only-failures` after a first run. Rails Minitest:
`bin/rails test test/models/user_test.rb:42`, or `-n /pattern/`. Plain
Minitest: `bundle exec ruby -Itest test/foo_test.rb -n /pattern/`. System and
integration tests often need `bin/rails test:system` or a running database;
check `bin/ci` or `config/ci.rb` for setup steps.

**Table-driven.** An array of cases with `each` that defines `it` or `test`
blocks; `shared_examples` with `it_behaves_like`. Extend these before adding
a sibling test.

**Test-only seams.**
- `send(:private_method)`, `instance_variable_get`/`set`: the test reaches
  past the public API. Move it to the public method that owns the behavior.
- `attr_accessor`, `attr_writer`, or `public` added only so a test can set or
  read state.
- `if Rails.env.test?` or `ENV["TEST"]` branches in production code.
- `reset!`, `clear_cache!`, or class-level setters (`self.client = ...`) that
  only specs and test helpers call.

**Mocks and fakes.**
- `expect(obj).to receive(:x).with(...)` is a call-shape test. Keep it only
  when the call is the observable effect (a mailer sent, a job enqueued, an
  external API hit); otherwise assert the result.
- `double` accepts any message; `instance_double` and `class_double` fail when
  the real interface changes. A plain `double` standing in for a real class is
  a candidate for "one mock standing in for different APIs".
- `allow_any_instance_of` and `receive_message_chain` usually mean the test
  is coupled to internals.
- WebMock and VCR are boundary fakes and are fine. A cassette is a copied
  fixture: check it still matches the real API shape it claims.
- `let!` blocks and factories that build the state the code under test should
  produce match "fixtures that supply the result".

**Stack-specific junk.**
- shoulda-matchers one-liners (`it { is_expected.to validate_presence_of(:name) }`)
  restate a declaration. They fail only when someone deletes the line on
  purpose. Keep one when the validation is a user-facing contract nothing
  else tests (an API error message, a form rule); otherwise test the behavior
  (saving an invalid record fails with the right error).
- Controller specs asserting `assigns` or `render_template`: implementation.
  Request or integration tests are the boundary.
- Tests that exercise Rails or a gem rather than app code (that `has_many`
  returns a relation, that `to_json` produces JSON).

**Non-test callers.** Ruby is dynamic, so a grep for `method_name` is not
enough. Also search for `:method_name` and `"method_name"` (`send`,
`public_send`, `try`, callbacks like `before_action :name`, `delegate`),
`method_missing` and `respond_to_missing?`, `constantize` and `safe_constantize`
on built strings, routes (`config/routes.rb`), views and partials, jobs and
mailers referenced by name, Zeitwerk autoload by file path, initializers, and
`config/*.yml`. Coverage gives hints only.

**Dependency source.** `bundle info <gem> --path`, then read the files there.
`bundle exec gem contents <gem>` lists them.

**Coverage.** SimpleCov, usually behind `COVERAGE=true` or always-on in
`test_helper.rb`/`spec_helper.rb`; read that file. `minimum_coverage` there
can fail CI after deletions.

**Format and lint.** `bundle exec rubocop -a <files>` or
`bundle exec standardrb --fix <files>`.

**Watchers.** `guard`, and `bin/dev` setups that run it.

## JavaScript / TypeScript

**Focused run.** Use the repo's package manager (`npx`, `pnpm exec`, `yarn`,
`bunx`). Vitest: `npx vitest run <path> -t '<name>'`; plain `vitest` in a
terminal is watch mode. Jest: `npx jest <path> -t '<name>'`. Mocha:
`npx mocha <path> --grep '<name>'`. Node's runner:
`node --test --test-name-pattern='<name>' <path>`. Bun: `bun test <path> -t
'<name>'`. Playwright: `npx playwright test <path> -g '<name>'`, with the
config the package script passes (`--config=...`). In a workspace monorepo,
run from the package directory or use the workspace filter
(`pnpm --filter <pkg>`, `npm -w <pkg>`, `yarn workspace <pkg>`).

**Table-driven.** `it.each`, `test.each`, `describe.each`, or a loop over a
case array.

**Test-only seams.**
- Exports only tests import: `_internal`, `__test__`, `__resetForTests`,
  `testOnly`. `knip` or `ts-prune` finds unused exports; confirm the only
  importers are test files.
- `if (process.env.NODE_ENV === 'test')` branches in production code.
- Optional parameters or options objects that default to the real
  implementation and that no production caller passes.
- Module-level singletons with a reset function for tests.

**Mocks and fakes.**
- `vi.mock`/`jest.mock` of the module under test, or of a sibling module whose
  behavior the test then asserts: the mock implements the asserted behavior.
- `toHaveBeenCalledWith` on an internal collaborator when the returned value
  or rendered output is available: a call-shape test.
- `mockImplementation` that re-implements the production logic.
- MSW, nock, and supertest against a real handler are boundary fakes and are
  fine.

**Stack-specific junk.**
- Large `toMatchSnapshot` trees nobody reads. Keep a snapshot when it pins
  user-facing output bytes (CLI output, a serialized format, generated code)
  and is small enough to review; otherwise assert the fields that matter.
- React tests that read component state, hook internals, or class names
  instead of what the user sees. Testing Library role and text queries are the
  boundary.
- Tests of what the type checker already guarantees (a field exists, a
  function accepts a string).

**Stack-specific keepers.** Type-level tests for a public API (`expectTypeOf`,
`tsd`, `// @ts-expect-error` lines) guard a contract the runtime tests cannot.

**Non-test callers.** Delete the export and run `npx tsc --noEmit`; a clean
build means no static importers. Then search for dynamic ones: string-based
`import()` or `require(variable)`, framework file routing (Next.js `app/` and
`pages/`, Remix and React Router route modules, where the export name itself
is the contract: `loader`, `action`, `default`), and plugins or handlers named
in config files.

**Dependency source.** `node_modules/<pkg>/` and its `.d.ts` files;
`npm ls <pkg>` shows which version resolved.

**Coverage.** `vitest run --coverage`, `jest --coverage`, or `c8`.
`coverageThreshold` (Jest) and `coverage.thresholds` (Vitest) can fail CI
after deletions.

**Format and lint.** Prettier or Biome, ESLint, and `tsc --noEmit` (or the
repo's `typecheck` script, which may use `tsc -b`).

**Watchers.** `vitest` without `run`, `jest --watch`, `nodemon`, dev servers
that run tests.

## Python

**Focused run.** Prefix with the env runner the repo uses (`uv run`,
`poetry run`, `pdm run`, `pipenv run`), or activate its venv. pytest:
`pytest tests/test_x.py::TestX::test_y -q`, `-k '<expr>'`, `--lf` after a
first run, `-m '<marker>'` for marked suites (check CI for the markers it
selects or excludes, such as `-m "not integration"`). unittest:
`python -m unittest pkg.tests.test_x.TestX.test_y`. Django without
pytest-django: `python manage.py test app.tests.test_x`. tox and nox run the
matrix; use them for the final gate, not the focused run.

**Table-driven.** `@pytest.mark.parametrize`, fixtures with `params=`,
`self.subTest` in unittest.

**Test-only seams.**
- Tests importing `_private` names from the module under test.
- `if TESTING:` or `settings.TESTING` branches in production code.
- Optional `client=None` or `clock=None` parameters that only tests pass.
- Module globals reset by fixtures, and `__all__` lists copied into tests.

**Mocks and fakes.**
- `mock.patch` of a function in the module under test: the test proves the
  patch. Patch at the boundary (network, clock, filesystem) instead.
- `MagicMock()` accepts any attribute and any call, so the test can pass
  against the wrong API. `create_autospec` or `patch(..., autospec=True)` makes
  it fail when the real signature changes.
- `assert_called_once_with` on an internal helper is a call-shape test.
- `responses`, `respx`, `vcrpy`, `freezegun`, and `monkeypatch` of
  environment or clock are boundary fakes and are fine.

**Stack-specific junk.** syrupy or snapshottest snapshots accepted without
review; tests that check a dataclass or pydantic model has the fields it
declares.

**Stack-specific keepers.** Hypothesis property tests usually cover many
example tests at once; they are not duplicates of them. Doctests
(`--doctest-modules`) keep documented examples true.

**Non-test callers.** Search for the name as a string too: `getattr`,
`importlib.import_module`, entry points in `pyproject.toml`
(`[project.scripts]`, `[project.entry-points]`), Django URL confs, settings
and `INSTALLED_APPS`, Celery task names, and signal receivers. pytest fixtures
are used by argument name, so search every test for a fixture's name before
deleting it from `conftest.py`. `vulture` gives hints only.

**Dependency source.** With the env prefix:
`python -c 'import pkg, os; print(os.path.dirname(pkg.__file__))'`, then read
the files there.

**Coverage.** `pytest --cov=<pkg> --cov-report=term-missing`, or
`coverage run -m pytest`. `fail_under` in `[tool.coverage.report]` and
`--cov-fail-under` can fail CI after deletions.

**Format and lint.** `ruff format` and `ruff check --fix`, or `black` and
`isort`; `mypy` or `pyright` with the paths CI checks.

**Watchers.** `ptw` or `pytest-watch`, `pytest -f` (pytest-xdist looponfail).

## Rust

**Focused run.** From the workspace root: `cargo test -p <crate> <filter>`,
where the filter is a substring of the test path (`module::tests::name`);
add `-- --exact` for one test. `--lib` runs unit tests only,
`--test <file-stem>` one integration file, `--doc` doctests. `-- --ignored`
runs `#[ignore]` tests. Feature-gated tests run only with `--features <f>` or
`--all-features`; check which features CI enables. nextest:
`cargo nextest run -p <crate> <filter>`; it skips doctests, so run
`cargo test --doc` as well.

**Unit tests are not seams.** A `#[cfg(test)] mod tests` block with
`use super::*` that tests private functions is normal Rust. Judge it by what
it asserts, not by its access to private items. Integration tests in
`tests/` see only the public API.

**Table-driven.** A loop over an array of cases, `rstest` with `#[case]`, or
`test-case`.

**Test-only seams.**
- Visibility widened for integration tests: `pub` where `pub(crate)` would do,
  or `#[doc(hidden)] pub`.
- A `test_utils` or `testing` module compiled into the main crate without
  `#[cfg(test)]` or a feature gate.
- A trait with one production implementation that exists so tests can mock it
  (`mockall::automock`).
- `#[cfg(test)]` alternative implementations of production logic, and
  `#[allow(dead_code)]` on items only tests use.

**Mocks and fakes.** mockall expectations with `.times(1)` are call-shape
tests. `wiremock` and `httpmock` are boundary fakes and are fine.

**Stack-specific junk.** Tests of what the compiler already guarantees: that
a derived `Clone`, `Debug`, `PartialEq`, or `Default` works, that a struct has
a field, or `assert!(x.is_some())` right after building `Some(x)`. `insta`
snapshots accepted with `cargo insta accept` and never reviewed.

**Stack-specific keepers.** `trybuild` and `compile_fail` doctests guard a
public API's compile-time contract. `proptest` and `quickcheck` properties
cover many example tests at once.

**Non-test callers.** Delete the item and run `cargo check -p <crate>` (a
non-test build). A clean build means no non-test callers in that crate; for a
`pub` item, run `cargo check --workspace --all-features` too. Then search
macros, `build.rs`, and FFI or `#[no_mangle]` exports, which the check may not
reach.

**Dependency source.** `~/.cargo/registry/src/*/<crate>-<version>/`;
`cargo metadata --format-version 1` gives the exact path and version.

**Coverage.** `cargo llvm-cov -p <crate>` or `cargo tarpaulin`.

**Format and lint.** `cargo fmt` and `cargo clippy -p <crate> --all-targets`,
with the `-D warnings` and feature flags CI uses.

**Watchers.** `cargo watch`, `bacon`, `watchexec`.

**Diff split caveat.** `test_context.sh diff` counts edits inside
`#[cfg(test)] mod tests` blocks as production lines. Count those by hand when
a Rust diff edits them.
