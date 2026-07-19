---
name: Bug report
about: Report a defect in AVIOR
title: "[bug] "
labels: bug
assignees: ''
---

## Summary

<!-- A clear and concise description of what the bug is. -->

## Reproduction

Steps to reproduce the behaviour:

1. Project layout / relevant `validation/avior.yml` policy (redact as needed)
2. Command run (e.g. `avior scan`, or the R call `avior_scan(".")`)
3. What happened

```
<!-- paste the exact command output or error here -->
```

## Expected behaviour

<!-- What you expected to happen instead. If it concerns a generated
     artifact, note which file contract (PRD §6) you expected. -->

## Environment

* AVIOR version: <!-- packageVersion("avior") -->
* R version: <!-- R.version.string -->
* OS:
* Engine installed (if relevant): <!-- e.g. riskmetric version -->
* Network available during the run: <!-- yes / no -->

## Additional context

<!-- Anything else that helps: whether the run was --deep, whether it was a
     cache hit, sanitized fragments of inventory.yml / scores.yml, etc. -->
