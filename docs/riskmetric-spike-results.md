# Real 50-package riskmetric spike results

## Evidence and scope

The `Riskmetric smoke` workflow performed a real 50-package assessment on
2026-07-16. The authoritative
[workflow run](https://github.com/Thynexa/AVIOR/actions/runs/29484932589)
finished with status `completed` and conclusion `success`; this document records
the workflow's measured output, not estimated values.

| Run metadata | Value |
| --- | --- |
| Event | `workflow_dispatch` |
| Started | `2026-07-16T08:50:49Z` |
| Runner | Ubuntu 24.04.4 LTS (`ubuntu-24.04` image) |
| Evidence commit | [`3745a964db057ec8bc932897ad65f0b96c2a924e`](https://github.com/Thynexa/AVIOR/commit/3745a964db057ec8bc932897ad65f0b96c2a924e) |
| Status / conclusion | `completed` / `success` |

## Measured result

| Versions | Package count | Timings | Threshold outcome | NA disclosure |
| --- | ---: | --- | --- | --- |
| R: `R version 4.6.1 (2026-06-24)`<br>avior: `0.0.0.9000`<br>riskmetric: `0.2.7` | 50 | Cold: `32.62` seconds<br>Hot: `19.739` seconds | Cold: `32.62 <= 1800` — **PASS**<br>Hot: `19.739 <= 300` — **PASS** | The hot-run summary reported `na_metrics = [last_30_bugs_status, remote_checks]`. Metric coverage was therefore not fully non-NA. |

The successful workflow is the performance evidence: both measured elapsed
times satisfied the runner's explicit limits. The NA result is preserved as
part of the evidence and is not converted into a complete-coverage claim.

## Workflow security posture

The evidence workflow grants the GitHub token only `contents: read`, and its
`actions/checkout@v6` step sets `persist-credentials: false`.

## Diagnostic history and integration follow-up

The earlier
[run 29474425566](https://github.com/Thynexa/AVIOR/actions/runs/29474425566)
failed after exposing a dash-versus-dot package-version representation issue
(for example, `0.1-6` versus `0.1.6`). That run is diagnostic history, not
performance evidence.

The successful evidence SHA is the remote PR branch's parallel fix for semantic
package-version comparison. The final integrated head will retain an equivalent
or stricter semantic comparison and, after the final push, will be revalidated
by the PR-triggered 5-package `Riskmetric smoke` check.

## Root-cause note: all-NA `remote_checks` (issue #27)

The spike's hot and cold runs reported `remote_checks` as NA for every
package even though the assessment library was freshly installed from CRAN
(installed version == CRAN latest, so the adapter's version guard should
have passed). The adapter code at the spike SHA compared
`pkg_ref(pkg, source = "pkg_cran_remote")$version` against the lockfile
version with a fail-closed comparison: any shape that does not parse as a
package version — including a `NULL`/absent `$version` on the remote ref —
was treated as a mismatch and swallowed to a bare NA by the surrounding
`tryCatch`. A remote ref whose version is populated lazily (or a transient
CRAN checks scrape failure) therefore produced the observed all-NA column
without leaving a distinguishable trace. This is an upstream shape issue we
contain rather than fix: riskmetric is maintenance-only.

The adapter now separates the two situations explicitly (issue #27):

- **Confirmed mismatch** — the remote version is readable and differs from
  the pinned version. The NA carries cause `version`; it can never self-heal
  by going online, so it does not trigger the score-cache refresh rule. A
  lockfile version change alters the cache key and re-assesses naturally.
- **Indeterminate** — the remote ref fails or its version is unreadable
  (the spike shape). The NA stays cause-less and maps to the registry
  default `network`, so the next online run retries it.

A future spike re-run will show which of the two shapes the runner actually
hits; either way the NA disclosure in `scores.yml` is unchanged.
