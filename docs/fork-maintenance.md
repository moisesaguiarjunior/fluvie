# Fork maintenance

Recorded 2026-11-12. This is a maintainer decision for this fork. It is not
an upstream Fluvie decision, and it does not change Social Studio until a
later reviewed step says so.

## Base

This fork starts at tag `v0.3.1`, commit
`4134dbb0d7dd873c5bdecaccb020183369a0e2e7` (`chore(release): 0.3.1`).
Upstream `main` (`10e442c`) is not the base. Its CI was already failing, and
the capture work targets the published 0.3.1 sources.

The MIT `LICENSE` and Simon Auer's copyright stay. `NOTICE` names the base
tag and says the upstream project has not endorsed this fork.

## What this fork maintains

`tool/maintained-packages.txt` names the packages `tool/check.sh` and the
quality workflow always check:

- `packages/fluvie`
- `packages/fluvie_mobile_encoder`

Left at upstream v0.3.1, present in the tree, and not in that list:

- `packages/fluvie_lints` and its example
- `packages/fluvie_cli`
- `packages/fluvie_ai`
- `packages/fluvie_validate`
- `packages/fluvie_server`
- `packages/fluvie_editor`
- `packages/fluvie_presenter`
- `packages/fluvie_web_encoder` and its example
- `apps/slides`
- `examples/gallery`, `examples/kitten_kit`, `examples/cli_quickstart`,
  `examples/web_browser_studio`, `examples/web_server_studio`,
  `examples/desktop_studio`, `examples/mobile_purrfect`

A commit that touches one of those paths is still checked by the hooks.
Deleting the list makes `tool/check.sh` check every package again. A listed
path with no `pubspec.yaml` fails closed.

## Flutter pin

The fork gate pins Flutter 3.47.9 in `.github/workflows/quality.yml`. That
is the SDK used to review the capture corrections. Upstream `ci.yaml` still
pins Flutter 3.44.0 for the jobs that succeeded on the tag. Those jobs were
not re-run here, and their pin was left alone so a version bump would not
turn a previously green job red.

`dart pub get --enforce-lockfile` on Flutter 3.47.9 cannot satisfy the
published 0.3.1 lock. The resolver reports it would change `matcher`
0.12.19 to 0.12.20, `meta` 1.18.0 to 1.19.0, `test` 1.31.0 to 1.31.1,
`test_api` 0.7.11 to 0.7.12, `test_core` 0.6.17 to 0.6.18, and `vector_math`
2.2.0 to 2.4.4. The setup commit refreshes `pubspec.lock` for that reason.
It is not a casual dependency bump.

Flutter 3.47.9 also rewrites plugin `analysis_options.yaml` files so later
`flutter test` runs stay stable. `packages/fluvie` excludes `build/**`.
`packages/fluvie_mobile_encoder` excludes `build/**`, `android/**`, and
`ios/**`. Both files ignore `analysis_options_deprecated_plugins` and
`included_file_warning` with a dated comment. `custom_lint` stays, so
`fluvie_lints` still runs. The ignore also hides other included-file
warnings in those two packages.

The same SDK run rewrites `analysis_options.yaml` in packages this fork
does not maintain, adding `build/**` and platform excludes. Those rewrites
are restored and are not part of this commit. Keeping them would make the
commit touch those packages, and the hook would then run their suites.
A later strict analyze of one of them on Flutter 3.47.9 still reports the
legacy plugin registration until that package gets the same dated ignore.

Four `prefer_if_elements_to_conditional_expressions` infos and one
`unnecessary_unawaited` info are fixed in the library. They are new against
the Flutter 3.44 analyzer that the tag's quality job used. They are not
capture patches.

## Tests the fork gate runs

For Flutter packages, `tool/check.sh` uses the same exclude tags as upstream
`melos run test:flutter`:

`golden || snapshot || ffmpeg || wasm || render || generative`

That is upstream's own opt-in split. Golden baselines are Linux images.
The excluded tags are separate jobs upstream. The default suite still runs.
This delivery does not claim those opt-in jobs were re-run.

## Upstream CI on the tag

GitHub Actions run `29481384753` for commit `4134dbb`:

- `test (ubuntu-latest)`, job `87565709409`, failed.
- `test (macos-latest)`, job `87565709453`, cancelled.
- `coverage`, job `87565709425`, failed.
- The job logs returned HTTP 410, so the failing test names were not
  recovered. The commit status API was `pending` with no statuses. That is
  not a green result and it is not a list of failures.

Those jobs are absent from `.github/workflows/ci.yaml`. A job named `test`
or `coverage` that only printed this record would show as a green check.
The quarantine is a recorded skip of the workspace-wide suite, kept in
this file on 2026-11-12. It does not claim the historical failures are
fixed. The fork's required check is the `Repository checks` job in
`.github/workflows/quality.yml`.

Other upstream jobs that succeeded on that run stay in `ci.yaml` on Flutter
3.44.0. They were not re-run locally before the fork was public. Browser
render, pana, phone render, ffmpeg integration, and `melos run gate`
(including the 97% coverage gate) were not re-run locally.

## Flutter 3.44 workspace analyze

The `quality` job in `.github/workflows/ci.yaml` ran format, analyze, and
lint for the whole workspace on Flutter 3.44.0. On pull request 1, Actions
run `43325730971` finished that job red. `melos run analyze` failed in the
two maintained packages:

- `packages/fluvie`: `analysis_options_deprecated_plugins` is not a
  diagnostic on Flutter 3.44.0 (`unrecognized_error_code` at
  `analysis_options.yaml:18`). `live_player.dart:78` reports
  `discarded_futures` for `Ticker.start`.
- `packages/fluvie_mobile_encoder`: the same unrecognized code at
  `analysis_options.yaml:17`, plus `cascade_invocations` at
  `lib/src/offscreen_capture_host.dart:138` and
  `test/capture/host_lifecycle_test.dart:343`.

The ignore stays so Flutter 3.47.9 can keep the `custom_lint` plugin.
Wrapping that ticker call in `unawaited` is what 3.44.0 asks for, and it is
what 3.47.9 reports as `unnecessary_unawaited`. One analyze command cannot
be strict on both pins. The job is absent from `ci.yaml`. The fork gate
remains `Repository checks` in `.github/workflows/quality.yml` on Flutter
3.47.9. The other fourteen jobs in run `43325730971` passed, including
`ffmpeg_integration` and `example_mobile_render`. This commit does not
re-run them and does not claim the historical coverage failure is fixed.

## Capture corrections

Recorded 2026-11-12, on top of the repository gates. The maintained
packages are `0.3.1+socialstudio.1`. The build metadata keeps a dependency
written as `fluvie: ^0.3.1` valid. Nothing in this delivery was published
to pub.dev.

`render` and `renderToSandbox` pre-resolve inline, SRT, and VTT captions
in the existing media pass. Callers do not have to call
`preResolveCaptions` first. `OffscreenCaptureHost` drains composition
preparation without an application frame, rejects `mount` and `pumpFrame`
during an application build, and returns one dispose future. Dispose
started from `State.dispose` waits for that frame's post-frame callbacks,
then releases the `RenderView` and the `PipelineOwner`. A preparation that
keeps scheduling itself stops after 8 passes with `StateError` (`Offscreen
capture preparation did not finish.`).

The regression test for that cap sets a 2 second timeout. A `package:test`
timeout uses a timer, so it does not interrupt a synchronous loop that
never yields. The cap is what makes the failure return.

Not verified:

- Release and profile builds. `BuildOwner.debugBuilding` is false there,
  including during `build`, and those builds strip Flutter's re-entrant
  `buildScope` assert.
- The browser `WebVideoRenderer`.
- Phones. The desktop widget tests do not certify a phone.
- Native memory. `debugRenderViewDisposed` records disposal of the view
  object. It is null when asserts are disabled.
- Nested `Video` discovery. `compositionVideo` does not cross a `Builder`
  or another `Video`. A null resolver still skips preparation.

## Publish and deploy

`publish.yml`, `images.yml`, `docs.yml`, and `website.yml` are blocked.
Tag pushes of `publish.yml` and `images.yml` fail closed. Docs and website
deploys do not run on push. Git history of `v0.3.1` still has the original
workflows. This fork is not published to pub.dev. A later publication needs
a new package name and a maintainer decision.

## Ruleset

`.github/rulesets/main.json` declares pull-request merges, linear history,
no force-push, no branch deletion, and a strict required check named
`Repository checks`. It was not applied on GitHub: this delivery does not
create the public fork. The pull-request rule sets
`required_approving_review_count` to 0, so the JSON is not a server-side
approval requirement. Independent review of the exact commit is the local
pre-push record, and it applies in a checkout that uses `tool/hooks`. The
local pre-push hook already refuses a push to `main` and a remote branch
deletion.

## Hooks

`tool/install-hooks.sh` sets `core.hooksPath` to `tool/hooks`.

- `pre-commit` runs the upstream grep, size, docs-voice, and format gate
  from `.githooks/_lib.sh`, then format, strict analysis, and tests for
  each staged package. The workspace root is not treated as one package.
  A change to the root lockfile checks the maintained packages.
- `commit-msg` enforces Conventional Commits, using `.githooks/commit-msg`
  when that file is present.
- `pre-push` refuses `main` and branch deletion, requires
  `no-blocking-findings` for the exact commit, and checks every commit that
  would become public. The author cannot record their own review.
  Records live in `.git` under `fluvie-reviews` and are not pushed.
- `tool/check.sh` is what CI runs: the hook suite, the upstream hook
  self-test, and the maintained packages.

`tool/test_hooks.sh` is the regression suite. It builds its own schema
fixture. It does not copy another project's spec.
