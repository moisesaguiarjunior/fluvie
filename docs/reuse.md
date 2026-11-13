# Reuse map

One line per need this fork maintains. Update this file in the same change
that adds or removes one of these solutions. Packages outside
`tool/maintained-packages.txt` stay as upstream published them.

| Need | Use | Where | Example consumer |
| --- | --- | --- | --- |
| Format, strict analysis, and default tests for a maintained package | `check_package` | `tool/hooks/lib.sh` | pre-commit, pre-push, `tool/check.sh` |
| Hook regressions for a tool or workflow change | `check_hook_suite` | `tool/hooks/lib.sh` | `tool/test_hooks.sh` |
| The fork gate | `bash tool/check.sh` on Flutter 3.47.9 | `tool/check.sh` | `.github/workflows/quality.yml` |
| Caption preparation while rendering an aspect | The existing collector and `preResolveCaptions`, called from `render` | `packages/fluvie/lib/src/rendering/render_aspect.dart` | `packages/fluvie_mobile_encoder/test/capture/aspect_captions_test.dart` |
| Caption preparation while rendering to a sandbox | The same collector, called from `renderToSandbox` | `packages/fluvie/lib/src/rendering/render_to_sandbox.dart` | `packages/fluvie_mobile_encoder/test/capture/sandbox_captions_test.dart` |
| Offscreen capture without an application frame | `OffscreenCaptureHost` | `packages/fluvie_mobile_encoder/lib/src/offscreen_capture_host.dart` | `packages/fluvie_mobile_encoder/test/capture/host_lifecycle_test.dart` |
| Preserve stateful animations while reusing cached pixels | `runFrameCaptureLoop` pumps every frame before cache selection | `packages/fluvie/lib/src/rendering/frame_capture_loop.dart` | `renderVideo`, aspect render and sandbox capture |
| Advance the generated CLI host without cumulative rounding | Rounded absolute frame timestamps in the existing pump callback; no new SDK requirement | `packages/fluvie_cli/lib/src/templates/file_harness_template.dart` | A generated harness stays compatible with projects using the published SDK |
| Protect generated CLI timing in the required gate without an encoder | `native_capture_harness_test.dart` executes `fileHarnessSource`; shared native ticker and disposable-project helpers | `packages/fluvie_cli/test/support/` | Default CLI suite and supplementary encoded-video regression |
