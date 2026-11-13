# Contributing to Fluvie

Thanks for wanting to help. This page is the short version; the long version
lives in [documentation/contributing/](documentation/contributing/).

## This fork

This repository is a fork of SimonErich/fluvie at tag `v0.3.1`. Read
[docs/fork-maintenance.md](docs/fork-maintenance.md) before opening a pull
request. The upstream project has not endorsed the fork.

Nothing reaches the public remote before an independent local review of the
exact commit. Work on a branch. Do not commit to `main`.

```sh
dart pub get
bash tool/install-hooks.sh
```

The hooks live in `tool/hooks`. They chain the upstream grep, size, and
format gate, and they require a review record from `tool/record-review.sh`.
The author cannot record their own review. Records stay in `.git` and are
not pushed. The pre-push hook refuses a push to `main`.

The fork's required check is `bash tool/check.sh` (hook regressions, the
upstream hook self-test, format, strict analysis, and the default tests for
`packages/fluvie` and `packages/fluvie_mobile_encoder`). CI runs that script
on Flutter 3.47.9. See the quality workflow.

`CI=true dart run melos run gate` remains the upstream standard, including
coverage of packages this fork does not maintain. The tag's coverage job
failed, and this fork does not claim that gate is green. Do not publish to
pub.dev from this fork.

## Setup

```sh
git clone https://github.com/SimonErich/fluvie.git && cd fluvie
dart pub get                       # resolves the workspace root
dart run melos bootstrap           # resolves all packages
bash tool/install-hooks.sh         # fork hooks (required)
```

You need Flutter 3.47.9 for the fork gate. Upstream documented Flutter 3.44+
and Dart 3.12+. `ffmpeg` is still required for the render-integration tests,
which are outside the default fork gate.

## The rules that get PRs merged

1. **Test first.** Every change starts with a failing test. No production code
   without one.
2. **The fork gate is green**: `bash tool/check.sh`. The upstream command
   `CI=true dart run melos run gate` still means format, analyze,
   custom_lint, tests, and coverage of at least 97% across the workspace.
   This fork does not claim that coverage job is green. See
   [docs/fork-maintenance.md](docs/fork-maintenance.md).
3. **Conventional Commits**, one concern per commit (`feat(timing): …`,
   `fix(rendering): …`). The commit-msg hook enforces the format.
4. **Small files**: ≤200 lines per production file, ≤80 lines per `build`.
   The pre-commit hook enforces this.
5. **Determinism is sacred**: no wall-clock, no unseeded randomness in render
   code. Goldens must be byte-stable; regenerate with
   `flutter test --update-goldens --tags golden` and review the PNG.
6. **Docs ship with features.** A new public API needs dartdoc; a new
   capability needs its page in `documentation/` (see the voice rules in
   [documentation/README.md](documentation/README.md)).
7. **One home per fake.** A fake that package consumers use in their own tests
   ships in `lib/src/fake/` and is exported from the barrel; a fake only this
   repository's tests use lives in `test/**/fakes/` next to its suite.

## Where things live

- `packages/fluvie` — the library. `packages/fluvie_lints` — custom lints.
- `packages/fluvie_cli` — the headless renderer. `examples/gallery/` — the 12 lessons.
- `examples/` — one small app per rendering path (CLI, desktop, mobile, browser, server) sharing `examples/kitten_kit`.
- `documentation/` — the guides, reference, and contributing pages.

## Reporting issues

Use the issue templates. For security reports, see [SECURITY.md](SECURITY.md).
