# Contributing overview

This fork's required check is `bash tool/check.sh` on Flutter 3.47.9. Install
`tool/hooks` with `bash tool/install-hooks.sh`. Clone
`https://github.com/moisesaguiarjunior/fluvie.git`. Do not commit to `main`.
The upstream command `CI=true melos run gate`, including its 97% coverage
floor, is not this fork's gate and is not claimed green. The sections below
keep the upstream workflow for the packages this fork does not maintain.

## Set up the workspace

Clone this fork and resolve the workspace, then install the fork hooks:

```sh
git clone https://github.com/moisesaguiarjunior/fluvie.git && cd fluvie
dart pub get                  # resolves the workspace root
melos bootstrap               # resolves all packages
bash tool/install-hooks.sh    # fork hooks (required)
```

You need Flutter 3.47.9 for the fork gate. Upstream documented Flutter 3.44+
and Dart 3.12+. `ffmpeg` on your PATH is still required for the
render-integration tests, which are outside the default fork gate.

## Test first, always

Every change starts with a failing test. No production `.dart` file lands before
its test exists and has failed for the right reason. Red, then green, then
refactor. See the [Testing guide](testing.md) for the suites and fakes.

## The quality gate

The gate is four steps, each its own melos script:

- `melos run format` checks `dart format` left nothing to change.
- `melos run analyze` runs `dart analyze` with `--fatal-infos` and
  `--fatal-warnings`, so an info is a failure.
- `melos run lint --no-select` runs the custom lints (`dart run custom_lint`).
- `melos run coverage:check` enforces the 97% line-coverage floor.

Goldens run separately with `melos run test:goldens` on the Linux baseline. Run
`melos` non-interactively with `CI=true` to avoid the prompt path.

## The layering law

Dependencies point down only, inside `packages/fluvie/lib/src/`:

```text
core            pure Dart: Time, Keyframe, enums, Defaults, contracts
  ^
timing          TimeScope, frame resolution, the trigger/anchor resolver
  ^
features        rendering, animation, composition, elements, media, audio, theme
  ^
diagnostics     the inspector model and timeline table; nothing depends on it
```

`core` depends on nothing but Flutter math types. `timing` depends only on
`core`. A feature may depend on `core` and `timing`, never on `diagnostics`.
Nothing imports another package's `src/`. The `layering` and `no_src_import`
custom lints enforce all of this, so a violation fails `melos run lint`.

A forward dependency goes through an interface in the lowest stable layer, with a
fake for tests and the real implementation injected through a Riverpod provider.

## Capture is headless

In capture mode the frame is the only clock: no wall-clock and no async work
inside a frame, and media is pre-resolved before the loop. For effects, prefer
seeded `noise(seed)` and `random(seed)` so a golden stays stable run to run.
Fluvie does not guarantee byte-identical output across machines or encoders.
Regenerate goldens with `flutter test --update-goldens --tags golden` and review
the PNG.

## Code standards

- One primary public type per file. No `utils.dart` dumping grounds.
- 200 lines per production file, 80 lines per widget `build`. The pre-commit
  hook enforces the file budget.
- Every public member of `packages/fluvie` carries dartdoc.
- No `TODO`, `FIXME`, `print`, or unjustified `dynamic`.
- Page width 100, trailing commas required.
- A new public API needs its dartdoc and its documentation page, in the same
  change. Docs snippets come from compiled sources, never hand-typed; see the
  voice rules in [the documentation map](https://github.com/SimonErich/fluvie/blob/main/documentation/README.md).

## Commits

Use Conventional Commits, one concern per commit (`feat(timing): …`,
`fix(rendering): …`). Bundle nothing unrelated. The commit-msg hook enforces the
format.

## Where to next

- [Testing guide](testing.md): the suites, the tags, and the fakes.
- [Coverage and the ignore policy](coverage.md): the 97% floor and when an
  ignore is allowed.
