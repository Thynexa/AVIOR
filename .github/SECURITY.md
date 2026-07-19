# Security Policy

AVIOR compiles validation evidence for use in regulated submissions, so the
integrity of the tool and of the artifacts it produces matters. We take security
reports seriously.

## Supported versions

AVIOR is pre-1.0 and under active development. Security fixes are applied to the
`main` branch and released in the next version. There is no long-term support
branch yet.

| Version | Supported |
| ------- | --------- |
| `main` (development) | ✅ |
| Older tagged releases | ❌ |

## Reporting a vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, use one of the following private channels:

* Preferred: open a
  [GitHub private security advisory](https://github.com/Thynexa/AVIOR/security/advisories/new)
  for this repository.
* Alternatively, email **opensource@thynexa.com** with the details.

Please include, where possible:

* a description of the issue and its impact (for example, whether it could allow
  a tampered evidence bundle to pass verification);
* the affected component or file contract;
* steps to reproduce, or a proof of concept;
* any suggested remediation.

## What to expect

* We aim to acknowledge a report within a few business days.
* We will investigate, keep you informed of progress, and coordinate a
  disclosure timeline with you.
* With your permission, we will credit you in the release notes once a fix is
  available.

## Scope

Because AVIOR is local-first and produces a signature-ready bundle whose
tamper-evidence anchor lives **outside** the tool (git history, the customer's
QMS, or a signature — see PRD §5.8), reports that concern the integrity of the
generated manifest, hashing, or verification logic are especially in scope.
