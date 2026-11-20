# Rendering roadmap

Recorded 2026-11-19 from the Fluvie review and planning discussion with Neon.
The order is single-frame capture, scene context, metrics, export modes, then
size variants. The goal is to support cover images, timeline previews, and
crafted scenes in Family Story and Social Studio. Verify Handcrafted as a
consumer. See [External material surfaces](external-materials.md).

## 1. Single-frame capture

Close the first PR on `feat/single-frame-capture`. Capture a raw RGBA frame or
PNG with alpha from the same scene by zero-based frame index or elapsed time.
Use the composition's FPS for time conversion. Keep direct seek for
frame-driven scenes and offer sequential pumping for widgets that depend on
earlier frames. Prepare only the clip frames the selected mode reads. Check
the last frame interval, invalid inputs, codec failure, and cleanup. Compare
the same frame against sequential capture in a real Handcrafted consumer.

## 2. Scene context

Extend `FrameContext` where compatible. Consider a `SceneRenderContext` if the
new contract needs a separate type. Expose resolved time as `Duration`, canvas
size and aspect, and a deterministic integer seed propagated through the scene.
Evaluate typed scene parameters and render-scoped resources against a concrete
consumer scene. A prepared resource should be created once per render and
released on success or failure. Validate this with Handcrafted textures, volume, or
stitch geometry. Preserve the existing frame, progress, noise, and audio
behavior for current builders.

The first change adds `time`, `size`, `aspect`, and `seed` to `FrameContext`.
The Handcrafted 0.3.1 pilot used typed constructor arguments and prepared one
consumer-owned texture cache per offscreen mount. The cache was released after
successful capture and a failed pixel readback. Add a public resource scope when
a consumer needs a lifecycle the widget tree cannot express.

## 3. Render metrics

Measure preparation and mounting, frame pumping, pixel readback, and encoding.
Evaluate an optional `RenderMetrics` report or callback for `captureFrame`, the
shared sequential frame loop, and `OnDeviceVideoRenderer`. Include frame count
and per-frame minimum, mean, p95, and maximum elapsed time. Include cache hits
where the pipeline already exposes them. Measure the Handcrafted scene on both
paths and verify that reporting leaves captured pixels identical.

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

Use one reviewed change per step. Run the fork gate on each candidate and
follow the [exact-commit review rule](fork-maintenance.md#hooks) before pushing.
