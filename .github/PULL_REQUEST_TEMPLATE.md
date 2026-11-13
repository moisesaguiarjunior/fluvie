<!-- Thanks for contributing. Keep one PR to one logical change. -->

## Problem

<!-- Link the issue or describe the problem this change solves, and why. -->

## What this changes

<!-- A short summary of the change and why. -->

## Reuse

<!-- What you searched for, what you reused, what you created, and why the existing code did not fit. -->

## System review

<!-- Canonical implementation and callers checked.
Why the change belongs here.
Second sources of truth avoided.
Acceptance criteria the tests might miss.
Code, tests, and documentation agreeing does not prove the premise is right.
If this changes a gate and its tests together, inspect removed or weakened
assertions and challenge the gate with an independent invalid case. A green
suite from the same snapshot cannot establish its own adequacy. -->

## Verification

<!-- Commands, results, relevant software versions, and unverified behavior.
No identifying machine or device details. Distinguish retained regression
tests from disposable experiments. -->

## Checklist

- [ ] Linked issue or clear problem statement
- [ ] Reuse checked (what was searched, what was reused)
- [ ] Tests added or updated first (red, then green), and they assert behavior
- [ ] `bash tool/check.sh` is green for this fork (hooks, format, strict analysis, maintained-package tests)
- [ ] New behavior covered by tests that fail without it
- [ ] `melos run test:goldens` reviewed image by image, if anything visual changed
- [ ] Public members carry dartdoc; doc snippets flow from compiled sources
- [ ] The layering law holds (dependencies point down only)
- [ ] Renders stay deterministic (no `DateTime.now()`, no unseeded `Random()`)
- [ ] README, NOTICE, and docs/fork-maintenance.md updated when they would otherwise lie
- [ ] One Conventional Commit per logical change
- [ ] Independent local review done before the first push; outcome attached
- [ ] Fork boundaries held: no pub.dev publish, capture limits kept honest

## Independent review

<!-- Done locally before the first push. Reviewer, outcome (no blocking findings / changes required / verification incomplete), findings, and checks run. The author does not record this review. -->
