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
have passed). At the spike SHA every failure inside the remote_checks block
was swallowed to a bare NA by one `tryCatch`, so the candidate boundaries
are externally indistinguishable in that run's output:

1. `pkg_ref(pkg, source = "pkg_cran_remote")` itself erroring;
2. the remote ref's `$version` being absent/unreadable, which the
   fail-closed comparison treated as a mismatch (note: upstream
   `riskmetric` initialises the CRAN-remote ref's version eagerly from
   `available.packages()`, which makes this shape unlikely unless the
   index fetch itself degraded);
3. the CRAN-checks scrape (`pkg_assess`/`pkg_score` on the remote ref)
   failing, or riskmetric scoring the assessment to NA via
   `score_error_NA`.

**Which boundary fired is not yet established** — the spike run predates
the instrumentation, so this section deliberately does not claim a root
cause. The adapter now names the branch per package on stderr when
`AVIOR_DIAG_REMOTE=1` is set (ref failure / unreadable version / confirmed
mismatch / scoring failure / scored-to-NA), and the `riskmetric-smoke`
workflow runs with it enabled, so any PR or dispatch run produces the
missing evidence. Update this section with the observed branch once a
diagnosed run exists.

Independent of that diagnosis, the adapter now separates the containment
outcomes (issue #27):

- **Confirmed mismatch** — the remote version is readable and differs from
  the pinned version. The NA carries cause `version`; it can never self-heal
  by going online, so it does not trigger the score-cache refresh rule. A
  lockfile version change alters the cache key and re-assesses naturally.
- **Indeterminate** — the remote ref fails, its version is unreadable, or
  scoring fails. The NA stays cause-less and maps to the registry default
  `network`, so the next online run retries it.
