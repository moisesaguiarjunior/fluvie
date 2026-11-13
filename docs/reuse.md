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
