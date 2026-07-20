# avior 0.0.0.9000 (development)

## M2: evidence compilation

* New command `avior test` / `avior_test()` (FR-TEST-1..3, #30): discovers
  testthat files under `validation/tests/`, maps every file to its package
  through the required `# avior-package: <pkg>` header (missing, ambiguous,
  malformed, or out-of-scope mappings are execution errors naming every
  offending file), runs the targeted tests, and writes canonical
  `validation/test-results.yml` with per-test-file results bound to the
  runtime environment (package version, lockfile SHA-256, R
  version/platform) for consumption by `avior check` and `avior bundle`.
  A failing targeted test exits 1; skipped or errored expectations are
  never reported as passes, and a file whose run produced no passing
  test at all (all skipped, or zero `test_that()` blocks) is a business
  failure. The classification is one shared row-level rule (`failed == 0`
  and `passed > 0`) applied identically by the writer, `avior check`
  (per result row — a green file cannot mask an all-skipped sibling;
  `no_passing_tests` finding names the file), the report's test-evidence
  section, and the traceability `test_status` column. The
  `test-results.yml` schema now requires an exact top-level `avior: 1`
  version (FR-X-6 — evidence in an unknown schema is invalid, never
  interpreted), all four counts as reconciling non-negative integers
  (`tests == passed + failed + skipped`), and unique result file paths,
  so hand-edited rows cannot fabricate passing evidence. `avior check` binds evidence to the decision's DECLARED test
  files: every path an `include_with_tests` decision lists must have a
  fresh passing result for that package — adding a required test without
  re-running `avior test` turns the gate red.
  The recorded package version is the installed `DESCRIPTION` `Version`
  literal (lockfile forms like `3.8-6` are preserved), and the check
  reader compares versions with R's `package_version` semantics.
  `--coverage` collects covr coverage as a disclosed, non-gating
  reference metric (`coverage_ref`) when covr is installed (covr is now
  in Suggests).

* New command `avior verify <bundle>` / `avior_verify()` (FR-VERIFY-1..3,
  #31): recomputes the SHA-256 of every file listed in `MANIFEST.sha256`
  for a bundle directory or transport zip and reports missing, modified,
  malformed, duplicate, and unexpected files as typed findings in a
  deterministic order. Runs without any project context — an auditor needs
  only the bundle and this package. On success it emits the SHA-256 of
  `MANIFEST.sha256` itself as the external anchor value (record it in the
  git commit, QMS archive record, or an independent signature; the
  manifest is not a trust root — PRD §5.8). Zip archives are extracted
  safely: absolute paths, drive letters, backslashes, and `..` traversal
  are rejected before extraction — for directory entries too — as are
  entries duplicated byte-for-byte or after ASCII case-folding, and
  non-ASCII entry names outright (NFC/NFD variants of the same text alias
  one path on default macOS filesystems; transport zips only ever carry
  ASCII bundle paths — verify non-ASCII trees as directories).
  Ships with an internal
  deterministic stored-zip writer (`SOURCE_DATE_EPOCH`-stable bytes) used
  for transport artifacts and fixtures.

* New command `avior bundle` / `avior_bundle()` (FR-BUNDLE-1,2,4..8, #32):
  compiles the validated project state into an immutable
  `validation/evidence/bundle-<UTC timestamp>/` directory — byte-identical
  snapshot copies of `avior.yml`/`inventory.yml`/`scores.yml`/
  `test-results.yml`/`decisions/`, the PRD §6.5 `traceability.csv`
  (transitive rows carry `version_managed`; out-of-scope direct rows
  `exempt` or `excluded`), the FR-BUNDLE-5 `environment.json` fingerprint
  (R/OS/platform, repositories incl. PPM snapshot, lockfile SHA-256,
  avior + engine versions, `LC_COLLATE`, BLAS/LAPACK with `"unknown"`
  fallback, container digest or `null`), the full `session-info.txt`,
  `BUNDLE.yml` metadata, and a path-sorted `MANIFEST.sha256` covering
  every file except itself. Compilation is gated on the equivalent of
  `avior check`; `--force` proceeds with a machine-readable disclosure
  (`integrity_check: failed`, `forced: true`, finding count/types) that
  the report cover surfaces; a forced compile tolerates inputs `check`
  reports as findings (unparseable or schema-invalid
  `test-results.yml`/decision records are snapshot verbatim and treated
  as unavailable — decisions are normalized against the reader's
  `invalid_decision` rules with an exact `avior: 1` schema-version match
  shared by every artifact reader (FR-X-6; `1.5`/`true` no longer read
  as v1), and every field the report/trace/counts consume is guaranteed
  scalar while reader-accepted scalar values such as a numeric
  `reviewed_by` are preserved as text rather than silently dropped). The
  same exact-version rule guards the inventory and scores read
  boundaries: `avior check` fails closed with `invalid_inventory`/
  `invalid_scores` findings for unparseable YAML and unknown schema
  versions alike (a raw parser error can never escape the gate),
  command-side readers refuse with an execution error, and a forced
  bundle keeps an unknown-schema or malformed `scores.yml` snapshot
  verbatim without interpreting it (an uninterpretable inventory cannot
  be compiled at all), and
  `counts.decisions_signed` counts decisions with a non-empty
  `reviewed_by` signature, not decision files on disk. Existing bundles
  are never overwritten
  (timestamp collisions abort). For identical inputs the data artifacts
  are byte-identical, and `SOURCE_DATE_EPOCH` fixes embedded timestamps
  for fully reproducible bundles. `--zip` additionally emits a
  deterministic, gitignored transport zip that `avior verify` accepts.
  Report rendering is a clean boundary consumed by the report milestone
  (#33).

* English validation report (issue #33, supersedes the PRD's "Chinese V1"
  language decision — PRD revised to v1.8): `avior bundle` now renders
  `report.html` and `report.docx` through a built-in, dependency-free
  renderer (hand-written self-contained HTML; minimal OOXML DOCX packed
  with the deterministic zip writer — no Quarto/pandoc system
  prerequisite). The report follows the GAMP 5 narrative (methodology and
  four criteria; the fixed scope-and-boundary statement with layered
  base/recommended exemption sourcing; scope and classification; scoring
  and thresholds; decision summary; targeted-test evidence; environment
  and reproducibility; per-package appendix plus an integrity appendix).
  A `--force`d bundle displays the integrity failure prominently on the
  cover of both formats. All narrative strings are externalized in
  versioned locale tables (`inst/report/locales/`): `en` is complete;
  `zh` is a schema-identical placeholder (`status: placeholder`) that
  fails closed with an actionable error if selected, so a partial or
  mixed-language report can never be emitted. `avior init` and the config
  defaults now select English (`report.language: en`).

## Packaging, documentation, and community

* Added the full Apache-2.0 license text (`LICENSE.md`), matching the
  `License: Apache License (>= 2)` field declared in `DESCRIPTION`.
* Added a "Getting started with AVIOR" vignette that walks through the M1
  core loop (`init` → `scan` → `assess` → `review`) and the `check` CI gate.
* Added `\examples{}` to every exported function's help page (`avior_init`
  and `avior_config_load` are runnable; the file/engine/network-dependent
  commands are shown under `\dontrun`).
* Added a package citation entry (`inst/CITATION`) so validation reports can
  cite the tool and version that produced the evidence.
* Added community and security files under `.github/`: `CONTRIBUTING.md`,
  `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1), `SECURITY.md`, issue
  templates, and a pull-request template.
* `DESCRIPTION` now declares `Language: en-US` and `VignetteBuilder: knitr`
  (with `knitr`/`rmarkdown` in `Suggests`); the CI check job installs pandoc
  so the vignette builds during `R CMD check`.

## Post-M1 fixes and deferred items (issues #22–#28)

* `avior assess` — engine adapters can now attribute NA causes; the
  riskmetric adapter tags a CONFIRMED `remote_checks` version mismatch
  (lockfile pinned below CRAN latest) with cause `version`, which never
  triggers the score-cache refresh rule. A repeated online assess over an
  unchanged pinned project is a genuine cache hit: zero engine calls,
  byte-identical output (#27). Indeterminate failures (ref error,
  unreadable remote version, scoring failure) stay cause-less, retryable
  NAs, and `AVIOR_DIAG_REMOTE=1` names the branch per package on stderr,
  including the raw assessment/scored-cell classes before the numeric
  conversion. Instrumented smoke runs diagnosed the spike's all-NA
  shape with class-level evidence: `assess_remote_checks` errors
  internally (`subscriptOutOfBoundsError` in its CRAN-checks page
  parse), riskmetric wraps it as `pkg_metric_error`, and riskmetric's
  `pkg_metric_error` scoring path returns a `pkg_score_error` NA
  directly (the supplied error handler is never invoked) — an upstream
  riskmetric 0.2.7 limitation, contained and disclosed (see
  `docs/riskmetric-spike-results.md`).
* `avior assess --refresh-na true|false` — the CLI now exposes the R
  API's `refresh_na` argument: `false` makes every valid cache entry a
  full hit (no online retry of network-cause NA metrics); duplicates and
  values other than `true|false` are execution errors (exit 2) (#23).
* `avior check` — a `scope.include`/`scope.exclude` entry that names no
  package in the lockfile is now a typed `unknown_scope_reference`
  finding (gate red, exit 1), judged against the live lockfile with the
  inventory as fallback. The scan-time warning remains, but a transient
  console warning is not auditable and never blocked CI (#24).
* `avior scan` — inventory ownership across rescans is now explicit:
  `inventory.yml` is machine-owned and rewritten wholesale, the
  per-package `note:` field is the one supported human annotation and is
  carried over by package name (matching the frozen example), and any
  other hand-added field — package-level or top-level — is discarded
  with a warning naming the field and pointing at the decision records,
  never silently. An existing inventory that no longer parses fails the
  scan closed instead of being overwritten (a malformed hand edit may
  still carry a supported note) (#26).
* `avior scan` — falls back to `DESCRIPTION` (Depends/Imports/LinkingTo)
  when the configured lockfile is absent (FR-SCAN-1). The inventory
  records which source produced it (`lockfile.path`), and each declared
  dependency without call-site evidence records its declaring field
  (`DESCRIPTION Imports`, `DESCRIPTION Depends+Imports`, ... —
  FR-SCAN-3 provenance); versions stay empty rather than fabricated
  (this source pins nothing), and `avior assess` treats an unpinned
  inventory version as "the installed version is the subject". `check`
  drift and scope rules resolve the same source; when neither file
  exists, scan and check keep failing closed (#22).
* `avior init --ci github|gitlab` (FR-INIT-3) — generates a deterministic
  CI workflow (`.github/workflows/avior.yml` or `.gitlab-ci.yml`) that
  runs the read-only `avior check` gate against the committed validation
  baseline. Existing workflow files are never overwritten; unsupported,
  duplicate, or valueless `--ci` options are execution errors (exit 2)
  (#25).

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
