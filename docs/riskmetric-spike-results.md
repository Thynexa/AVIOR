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
