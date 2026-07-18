# avior 0.0.0.9000 (development)

## Post-M1 fixes and deferred items (issues #22–#28)

* `avior assess` — engine adapters can now attribute NA causes; the
  riskmetric adapter tags a CONFIRMED `remote_checks` version mismatch
  (lockfile pinned below CRAN latest) with cause `version`, which never
  triggers the score-cache refresh rule. A repeated online assess over an
  unchanged pinned project is a genuine cache hit: zero engine calls,
  byte-identical output (#27). An unreadable remote version stays a
  cause-less, retryable NA (the spike's all-NA shape — see
  `docs/riskmetric-spike-results.md`).

Milestone M1 of the PRD (v1.6 contracts), merged via PRs #17–#19.

## Commands

* `avior_init()` / `avior init` — idempotent scaffold of the `validation/`
  contract tree; default policy weights use metadata/network-tier metrics
  only, `rationale` is a deliberate TODO that fails `check` until the
  organisation records its reasoning (FR-INIT-1/2).
* `avior_scan()` / `avior scan` — renv.lock parsing, base/recommended/
  contributed/custom classification (renv `Priority` field + vendored
  constants; source-based custom detection beats name lists), static
  intended-for-use detection with `file:line` provenance, transitive
  `<parent> Requirements` attribution, scope overrides recorded in-band,
  lockfile SHA-256 drift baseline (FR-SCAN-1..5). Unparseable source files
  are persisted as `scan: {complete: false, skipped_files}` and make the
  command exit non-zero — never a silent scope gap.
* `avior_assess()` / `avior assess` — risk scoring through the engine
  adapter layer (FR-X-4/§7.2) with a static per-adapter metric registry
  (offline policy validation), cost tiers `metadata|network|execution`
  (`--deep` opt-in for execution metrics; `--offline` skips network
  metrics entirely), `na_action: reweight|zero|fail`, `run: {deep,
  network}` disclosure, and an NA-cause-aware score cache keyed on the
  full policy metric set (FR-X-5). Fully-cached reruns are byte-identical.
* `avior_review()` / `avior review` — decision stubs per PRD §6.3
  (including the reserved `assessment_type`/`supersedes` V2 fields) and
  completeness validation (FR-REVIEW-3/4/5): signatures, rationale,
  version and score-snapshot freshness (engine/score/tier drift),
  package-identity binding, targeted-test paths confined to
  `validation/tests/*.R`, AI dual sign-off.
* `avior_check()` / `avior check` — the read-only CI gate (FR-CHECK-1..4,
  pulled forward from M2): per-package lockfile drift, policy validity,
  decision completeness, test-result freshness including the runtime
  environment binding (FR-TEST-2), `excluded_but_present`,
  `scan_incomplete`. Every finding names a package, a defect type and a
  fix suggestion (NFR-8).

## Infrastructure

* Canonical serialization layer (FR-X-7/8): custom YAML/JSON emitters and
  a CSV writer with fixed byte-level rules — C-locale ordering, LF-only
  UTF-8, decimal-only numbers (max 4 fractional digits, `.0` kept),
  per-artifact flow maps, locale-independent readers. Repeated runs
  produce byte-identical artifacts; `SOURCE_DATE_EPOCH` is honored.
* CLI envelope: `--format json` with type-stable collection fields
  (always arrays), unknown arguments rejected; exit codes 0 (pass),
  1 (validation failure), 2 (execution error) per FR-X-3.
* CI matrix: Linux / macOS / Windows plus the R 4.1 floor; ~490 tests
  including a drift-guarded fixture copy of `examples/minimal-project`.

## Not yet implemented (milestone M2)

* `avior test` (targeted testthat runner), `avior bundle` (evidence
  bundle compiler + report), `avior verify` (standalone integrity
  verification), Chinese report template.
