# AVIOR M1 Core Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement PRD §9 milestone M1 — the `avior` R package with `init` / `scan` / `assess` / `review` plus the engine adapter layer, score cache, and the `check` gate — fully test-driven, against the v1.6 contracts.

**Architecture:** One R package at the repo root. Layer 0: canonical serialization utilities (FR-X-8) that every artifact writer must go through. Layer 1: config loading/validation. Layer 2: command functions (`avior_init`, `avior_scan`, `avior_assess`, `avior_review`, `avior_check`) that read/write the `validation/` file contracts of PRD §6. Engines plug in via a registry (§7.2); tests use a fixture-driven mock engine so nothing depends on riskmetric being installed. `examples/minimal-project/` is the primary test fixture (copied to tempdir per test).

**Tech Stack:** R ≥ 4.1 (dev env: 4.3.3), Imports: cli, yaml, jsonlite, digest, utils, tools. Suggests: testthat (3e), riskmetric, covr. Hand-written NAMESPACE (no roxygen dependency for now; header comments document exports).

**PR split:** Tasks 1–7 → PR #2 (branch `claude/avior-m1-scaffold-scan`, base = PR #1 branch). Tasks 8–12 → PR #3 (branch `claude/avior-m1-assess-review-check`, base = PR #2 branch).

## Global Constraints

- R ≥ 4.1 language features only; no external runtime beyond R.
- Every generated artifact byte must flow through the canonical writers; C-locale ordering everywhere (`sort(method = "radix")` / `order(method = "radix")`) per FR-X-7.
- Exit codes (FR-X-3): 0 pass, 1 business failure (check red / policy `na_action: fail`), 2 execution error. Command functions return structured lists; only `main()` translates to exit codes.
- Errors raised with class `avior_error` (execution) or reported as structured findings (business): finding = `list(package, type, message, fix)`.
- Determinism: repeated runs on unchanged input produce byte-identical artifacts (timestamps: `scored_at`/`generated_at` honor `SOURCE_DATE_EPOCH` when set).
- All YAML schemas carry `avior: 1`.
- Tests: testthat 3e; fixture helper copies `examples/minimal-project` into a tempdir.

---

### Task 1: Package skeleton

**Files:** Create `DESCRIPTION`, `NAMESPACE`, `LICENSE` note (Apache-2.0 pointer), `.Rbuildignore` (docs/, examples/, .claude/, .agents/, .github/, skills-lock.json, ^\.gitignore$), `R/avior-package.R`, `tests/testthat.R`, `tests/testthat/helper-fixtures.R`.

**Interfaces (produces):** `local_example_project(env = parent.frame())` → copies `examples/minimal-project` to a tempdir, returns its path, auto-cleans; locates the example via `testthat::test_path("../../examples/minimal-project")` fallback `AVIOR_EXAMPLE_DIR` env var.

- [ ] DESCRIPTION: Package avior; Version 0.0.0.9000; Depends R (>= 4.1); Imports cli, digest, jsonlite, tools, utils, yaml; Suggests riskmetric, testthat (>= 3.0.0); License Apache License (>= 2); Config/testthat/edition 3.
- [ ] `R CMD build . && R CMD check --no-manual` → 0 errors 0 warnings (1 note re: hidden dirs acceptable via .Rbuildignore).
- [ ] Commit `feat: avior package skeleton (M1 scaffolding)`.

### Task 2: Canonical serialization (FR-X-8) — `R/canonical.R`

**Interfaces (produces):**
- `avior_format_num(x)` → character; decimal notation, round-half-even 4 fr. digits, trim trailing zeros, keep ≥1 fractional digit; `NA` → `NA_character_`.
- `avior_timestamp(time = NULL)` → `"%Y-%m-%dT%H:%M:%SZ"` UTC; honors `SOURCE_DATE_EPOCH` when `time` is NULL.
- `write_lines_lf(lines, path)` → UTF-8, LF only, trailing newline (opens `wb` connection).
- `write_yaml_canonical(x, path, header = NULL)` → block style, 2-space indent; **custom emitter** (NOT `yaml::as.yaml`, whose output varies by version and emits `yes/no` booleans): supports scalars (numeric via `avior_format_num`, logical as `true`/`false`, NULL as `null`), named maps, unnamed seqs of scalars/maps; strings unquoted only when matching `^[A-Za-z_][A-Za-z0-9._-]*$` and not a YAML reserved word (true/false/null/yes/no/on/off), else double-quoted with `\\` and `\"` escaping; `yaml::read_yaml` used for parsing only. Optional `# comment` header lines.
  Flow maps: `yaml_flow(x)` marks a map to emit inline (`{ k: v }`) at the §6-fixed positions ONLY (inventory package rows, scores `engine`/`metrics` rows, `risk_tiers`, snapshots) — per FR-X-8 block/flow is fixed per artifact, not mixed freely. `yaml_seq(x)` marks a vector to always emit as an inline sequence (`[a]`), needed at length 1 (e.g. decision `tests:`). Reserved words include YAML 1.1 `y`/`n`; embedded `\n`/`\r`/`\t` are escaped inside quoted scalars.
- `write_json_canonical(x, path)` → jsonlite pretty 2-space, `auto_unbox`, LF, trailing newline; doubles pre-rounded to 4 decimals so no value escapes to scientific notation (FR-X-8).
- `write_csv_canonical(df, path)` → header + rows; quote a field iff it contains `[",\n\r]` **or any non-ASCII byte** (FR-X-8: CN `notes` must be quoted); doubles quoted quotes; NA → empty field.
- `sort_c(x)` / `order_c(...)` → radix (C-locale byte order).

- [ ] Failing tests first (`tests/testthat/test-canonical.R`): num formatting table (`1 → "1.0"`, `0.61000000001 → "0.61"`, `0.00005 → "0.0"`, `1e-04 → "0.0001"`, `0.12345 → "0.1234"` round-half-even); timestamp respects SOURCE_DATE_EPOCH (`withr`-free: `Sys.setenv`/`on.exit`); files contain no `\r` byte (readBin check) and end with `\n`; yaml round-trips via `yaml::read_yaml` to equal data; double-run byte-identical; `sort_c(c("jsonlite","Matrix")) == c("Matrix","jsonlite")`.
- [ ] Implement; tests green; commit `feat: canonical serialization utilities (FR-X-8)`.

### Task 3: Shared helpers — `R/utils.R`

**Interfaces (produces):** `sha256_file(path)`; `avior_abort(msg, class = "avior_error")`; `validation_dir(config)`; `finding(package, type, message, fix)`.

- [ ] Tests: `sha256_file` on a fixture file matches `sha256sum` output; `avior_abort` signals condition class. Commit `feat: hashing and error helpers`.

### Task 4: Config load/validate — `R/config.R`

**Interfaces (produces):** `avior_config_load(root = ".")` → list with classes filled from defaults (`project$validation_dir` = "validation", `scope$intended_for_use` = "auto", include/exclude = character(0), `policy$na_action` = "reweight", `depth_by_risk` defaults, `report` defaults) + `$root`, `$paths$validation`; hard validation errors (class `avior_config_error`): missing/`!= 1` `avior`, missing `policy$weights` (non-empty named numerics ≥ 0), invalid `risk_tiers` (`low_max < high_min`, both in (0,1)), bad `na_action`. Soft flag: `$rationale_todo` TRUE when rationale missing/empty/contains "TODO" (check turns it red; load does not error).

- [ ] Tests: loads example config; each invalid mutation errors with `avior_config_error`; TODO rationale sets flag. Commit.

### Task 5: Lockfile parsing + classification — `R/lockfile.R`

**Interfaces (produces):**
- `read_renv_lock(path)` → data.frame(name, version, source, repository) + attr `r_version`; error `avior_error` when missing/malformed.
- `classify_packages(lock, config)` → adds `classification` (base|recommended|contributed|custom). Constants `BASE_PACKAGES`, `RECOMMENDED_PACKAGES` vendored. custom: renv Source ∈ {GitHub, GitLab, Bitbucket, Local, Remote, git2r} or RemoteUsername/repo matches a `scope$custom_orgs` glob.

- [ ] Tests: example renv.lock → 5 rows, survival=recommended, rest=contributed; synthetic lock with GitHub source → custom; custom_orgs `"our-org/*"` match → custom. Commit.

### Task 6: Static call scan — `R/scan-calls.R`

**Interfaces (produces):** `scan_direct_calls(root, exclude_dirs)` → data.frame(package, file, line) — first occurrence per package (files in C-locale path order, then line); detects `library()`, `require()`, `requireNamespace()`, `loadNamespace()` first-arg (symbol or string; skips computed args), and `pkg::`/`pkg:::` via `getParseData()` token `SYMBOL_PACKAGE`; unparseable files → warning + skip, recorded in attr `skipped`.

- [ ] Tests: fixture source exercising every form + a syntax-error file; provenance `file:line` correct; deterministic across runs. Commit.

### Task 7: `avior_scan()` + `avior_init()` + CLI + CI  → **close PR #2**

**Files:** `R/scan.R`, `R/init.R`, `R/cli.R`, `inst/exec/avior`, `.github/workflows/ci.yml`, tests.

**Interfaces (produces):**
- `avior_scan(root = ".")` → writes `<validation>/inventory.yml` (schema per §6.1/example: avior, generated_by, lockfile{path,sha256}, packages[{name,version,classification,role,in_scope,source,overridden?,override_source?,note?}], summary{total,direct,transitive,in_scope_assessed,recommended_exempt,force_included}); returns the inventory invisibly. Scope logic: direct = in scan_direct_calls; base/recommended exempt unless in `scope$include` (then `overridden: TRUE`, `override_source: "avior.yml scope.include"`); `scope$exclude` forces `in_scope: FALSE` + overridden; transitive → in_scope FALSE, source = "<parent> Requirements" not required for V1 — record `"renv.lock"`.
- `avior_init(root = ".", ci = NULL)` → creates validation/ tree + avior.yml skeleton (rationale: "TODO — 记录阈值与权重的组织理由") + decisions/ tests/ .cache/(.gitignore "*") ; idempotent: existing files untouched, returns list(created=, skipped=).
- `main(argv)` → dispatch init|scan (+ later assess|review|check), `--format json`, returns integer exit code; `inst/exec/avior` Rscript shim calling `avior::main(commandArgs(TRUE))` + `quit(status=)`.

- [ ] Tests: init on empty dir creates contract tree; second run skips all; scan on example fixture → parsed inventory **semantically equals** parsed `examples/.../inventory.yml` (same packages/fields/summary/lockfile sha — normalize note fields formatting-only differences by comparing all fields except free-text `note`); byte-identical on rerun; survival override recorded; `main(c("scan","--format","json"))` exit 0 + valid JSON on stdout.
- [ ] `.github/workflows/ci.yml`: matrix ubuntu/macos/windows, r-lib/actions setup-r + deps, `R CMD check --no-manual`, run testthat.
- [ ] `R CMD check` clean → commit → dispatch reviewer subagent on diff vs base branch → fix findings → push → **create PR #2**.

### Task 8: Engine adapter layer — `R/engine.R` (starts PR #3 branch)

**Interfaces (produces):**
- `avior_engine(id, version, metrics, assess)` → classed list; `metrics`: function() → data.frame(id, description, needs_network(lgl), cost ∈ {metadata,network,execution}); `assess`: function(pkg, version, metric_ids, opts) → data.frame(metric_id, value(dbl 0–1 or NA), status ∈ {ok,na,error}).
- `engine_register(engine)` / `engine_get(id)` (package-env registry); `engine_metric_registry(id)` works WITHOUT the engine package installed (static registry) — `check` depends on this.
- Built-in: `engine_riskmetric()` — static metric registry vendored (metadata-tier: has_vignettes, has_news, news_current, has_examples, has_bug_reports_url, has_maintainer, has_source_control, license, exported_namespace; network-tier: downloads_1yr, reverse_dependencies, last_30_bugs_status; execution-tier: covr_coverage, r_cmd_check); `assess` errors `avior_error` unless riskmetric installed (`requireNamespace`), then maps `pkg_ref → pkg_assess → pkg_score` per metric.
- Test helper `mock_engine(values)`: fixture-driven — `values` = nested list pkg→metric→value.

- [ ] Tests: registry round-trip; unknown engine errors; riskmetric registry has the §6.2 ids incl. `last_30_bugs_status` and marks `covr_coverage` cost "execution"; mock engine returns declared frame shape. Commit.

### Task 9: `avior_assess()` + cache — `R/assess.R`

**Interfaces (produces):** `avior_assess(root=".", only=NULL, deep=FALSE, engine=NULL, refresh_na=TRUE, network_available=TRUE)` → writes `<validation>/scores.yml` (schema per example: avior, generated_by, engine{id,version}, scored_at, **`run: {deep, network}`** run-mode disclosure (FR-ASSESS-1), packages(named, C-sorted){version, metrics{...}, score, tier, na_metrics? when non-empty}, na_metrics aggregate). Aggregation: `risk = 1 - weighted.mean(value, w)` over policy weights ∩ engine registry (weights referencing unregistered ids → `avior_error`; engine values must be in [0,1] or NA; zero effective weight → `avior_error`); execution-cost metrics excluded unless `deep`; na_action: reweight (drop NA), zero (value := 0), fail (`avior_error` subclass `avior_na_error` → exit 1). **Score rounded to 4 decimals BEFORE tiering** so the recorded score and tier can never contradict. Tiers: `risk <= low_max` low; `>= high_min` high; else medium. Cache: keyed on `digest(pkg, version, engine id, engine version, **full policy metric set**, deep)` under `<validation>/.cache/scores/`, storing metrics + na_metrics + **na_causes** + scored_at; a hit whose metric set ≠ current policy is invalidated. **NA-cause aware (B2/FR-X-5)**: each NA carries a cause — `network` (may self-heal online → triggers refresh when `network_available`) or `execution` (only `--deep` resolves it → NEVER auto-refreshed, so a plain run does not loop). `refresh_na` toggles the network refresh.

- [ ] Tests (mock engine): scores/tiers per fixture table (jsonlite→low, mvtnorm→medium, lme4/survival→high); NA reweight vs zero vs fail; only=; cache: 2nd run zero engine calls (closure counter) + byte-identical when fully cached (scored_at from cache + SOURCE_DATE_EPOCH); network-cause NA hit re-scored, execution-cause NA hit NOT re-scored; policy metric-set change invalidates the cache entry; `run` field values; values outside [0,1] and zero effective weight abort. Commit.

### Task 10: `avior_review()` — `R/review.R`

**Interfaces (produces):** `avior_review(root=".")` → (a) generates stubs `<validation>/decisions/<pkg>.yml` for in-scope packages lacking one — schema §6.3 v1.6: avior, package, version, score_snapshot{score,tier,scored_at,engine}, use_statement:"", decision:"", rationale:"", tests:[], reviewed_by:"", date:"", ai_assisted:false, confirmed_by:null, assessment_type:"initial", supersedes:null; (b) `review_findings(root)` → list of findings: missing_decision, invalid_decision (bad enum), unsigned (reviewed_by empty), empty_rationale, stale_score (decision version ≠ inventory version), missing_use_statement (tier ∈ {medium,high}), missing_tests (decision include_with_tests with no existing test file), unconfirmed_ai (ai_assisted && !confirmed_by).

- [ ] Tests: on example fixture (post-assess with mock) findings empty; each mutation (delete decision file / blank rationale / bump version in decision / drop use_statement on medium / point tests at missing file / ai_assisted true) yields exactly the expected finding with package name + type (FR-REVIEW AC). Stub generation idempotent. Commit.

### Task 11: `avior_check()` — `R/check.R`

**Interfaces (produces):** `avior_check(root=".", format="text")` → list(status ∈ pass|fail|error, findings); findings = review_findings + drift (lockfile sha vs inventory sha → added/removed/changed packages listed) + config (`rationale_todo`, weights vs registry) + test_results freshness (per test-results.yml: package version ≠ inventory OR lockfile_sha256 ≠ inventory sha → stale_tests; missing results for include_with_tests → missing_test_results) + `excluded_but_present` (decision exclude & pkg still in lockfile). Human output groups by package with `fix` suggestions (cli); `--format json` full structure. `main()` maps: pass→0, fail→1, `avior_error`→2 (FR-X-3).

- [ ] Tests: example fixture green (exit 0); PRD §5.7 AC scenarios — version bump in renv.lock → drift red; new package added → missing_decision red; blanked rationale → red; plus excluded_but_present and stale test (lockfile hash) scenarios; every red names package + defect type + fix hint; json output parses.
- [ ] E2E test `test-e2e.R`: fresh fixture → scan → assess(mock) → review (no findings) → check pass; tamper → check fail. Commit.

### Task 12: CLI wiring + review gate → **close PR #3**

- [ ] `main()` gains assess/review/check (+ `--only`, `--deep`, `--format json`); exec shim already routes.
- [ ] Full `R CMD check --no-manual` clean; whole test suite green.
- [ ] Dispatch reviewer subagent (contract conformance vs PRD v1.6 §5/§6 + code quality); fix CONFIRMED findings; push; **create PR #3** (base = PR #2 branch), body notes the PR chain and M2 leftovers (`test`/`bundle`/`verify`).
