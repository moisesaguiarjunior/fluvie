# Rendering roadmap

Recorded 2026-11-19. Updated 2026-11-20. The order is single-frame capture,
scene context, metrics, export modes, then size variants. One reviewed change
per step. The goal is a widget scene that becomes a finished piece: a cover,
a preview, and a social crop, with alpha, a stable seed, and more than one
size. See [The piece](piece.md). Verify Handcrafted as a consumer when a step
names that check. See [External material surfaces](external-materials.md).

## 1. Single-frame capture

Done. On main as `66d2870` (PR #6). Capture a raw RGBA frame or PNG with alpha
from the same scene by zero-based frame index or elapsed time. Use the
composition's FPS for time conversion. Keep direct seek for frame-driven
scenes and offer sequential pumping for widgets that depend on earlier frames.
Prepare only the clip frames the selected mode reads. Check the last frame
interval, invalid inputs, codec failure, and cleanup.

## 2. Scene context

Done. On main as `a3d7f2c` (PR #7), the same tree as reviewed `521fef0`.
`FrameContext` exposes resolved time as `Duration`, the output canvas, the
active aspect, and the deterministic `Video.seed`. The Handcrafted 0.3.1
pilot used typed constructor arguments and one consumer-owned texture cache
per offscreen mount. Add a public resource scope when a consumer needs a
lifecycle the widget tree cannot express. Preserve the existing frame,
progress, noise, and audio behavior for current builders.

## 3. Render metrics

Current change. Optional `RenderMetrics` for `captureFrame`, the shared
sequential frame loop, and `OnDeviceVideoRenderer`. Measure preparation and
mounting, frame pumping, pixel readback, and encoding. Include frame count,
cache hits where the pipeline already exposes them, and per-frame minimum,
mean, 95th percentile, and maximum elapsed time. Reporting leaves captured
pixels identical. That check is in the fluvie tests. The Handcrafted scene
was not measured on both paths in this change.

Guide: [Render metrics](../documentation/guides/render-metrics.md).

## 4. Export modes

Evaluate `Export.still` for PNG with alpha and an explicit frame or instant.
Pass export options through the aspect renderer and reuse single-frame
capture for the mobile PNG path. Add mobile PNG sequences using the existing
sequential capture loop. Keep existing MP4 behavior and verify the supported
alpha modes for each backend.

## 5. Size variants

Keep `Aspect`, `Adaptive`, and `VideoTemplate` as the entry points for common
formats. Add explicit `VideoSize` to `captureFrame` and `render` where a consumer
needs dimensions such as A5. Evaluate a `renderVariants` helper that renders
Story (9:16), Feed (4:5), and square from the same composition. Share media and
caption preparation where the inputs are identical. Resolve each variant's
layout and aspect-dependent resources at its own size.

The recipe, proof, plates, contact sheet, poster loop, and page-and-crop
utilities in [The piece](piece.md) are a later ring. They are not steps 3 to 5.

Use one reviewed change per step. Run the fork gate on each candidate and
follow the [exact-commit review rule](fork-maintenance.md#hooks) before pushing.
