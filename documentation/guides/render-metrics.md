# Render metrics

Pass an optional `RenderMetrics` when you want to know where a render spent
its time. Omit it and the pipeline allocates no stopwatch and no sample list.
The captured pixels are the same either way.

The report is for you. It does not change the frame loop, the cache, or the
encoder. Wall-clock samples vary from machine to machine. Read the counts.
Do not expect a particular number of milliseconds.

<!-- code-excerpt "packages/fluvie_mobile_encoder/example/still_capture.dart (metrics)" -->
```dart
Future<RawFrame> captureCoverMeasured({
  required ShellMount mount,
  required ShellFramePump pump,
  required RenderMetrics metrics,
}) => captureFrame(
  composition: Directionality(textDirection: TextDirection.ltr, child: coverScene()),
  aspect: Aspect.square,
  frame: 0,
  longEdge: 96,
  pumpWidget: mount,
  pumpFrame: pump,
  metrics: metrics,
);
```

`captureFrame`, `render`, `renderVideo`, `renderToSandbox`, and
`OnDeviceVideoRenderer.render`, `captureFrame`, and `capturePng` all accept
the same report. `RenderService.captureToDirectory` and `RenderService.render`
accept it too.

## What the report contains

| Field | What it counts |
| --- | --- |
| `frameCount` | Frames consumed. A still capture counts one. |
| `cacheHits` | Frames whose pixels came from a valid cache entry. Zero when the cache is off. |
| `cacheMisses` | Frames captured because the cache was on and had no valid entry. A stored buffer of the wrong length is a miss. Zero when the cache is off. |
| `preparation` | Media pre-resolution. `captureFrame` adds a second sample for the clip window warmed before the tree mounts. `render` and `renderVideo` add that clip sample, then `RenderService.captureToDirectory` adds one sample around its own media pre-resolution, audio pre-resolution, and mix staging. `renderToSandbox` records only its media sample. |
| `mounting` | The call that mounts the capture tree. |
| `pumping` | One sample per pumped frame. A cache hit still pumps. `stepThrough` also counts each intermediate pump, so this can exceed `frameCount`. |
| `readback` | One sample per pixel readback. A cache hit does not add a sample. Cache lookup is not a readback. |
| `encoding` | One sample per encoder call. Empty for `captureFrame`, `renderVideo`, `capturePng`, and a `renderToSandbox` that writes raw frames. `renderToSandbox` records one sample per frame when `frameEncoder` writes a PNG. `RenderService.render` adds a second sample when it also writes a poster. `OnDeviceVideoRenderer.render` times the hardware encode. |

Each stage reports its sample count and the minimum, mean, 95th percentile,
and maximum. The mean is the sum of the sample microseconds divided by the
sample count, truncated toward zero. The 95th percentile is the sample at
`ceil(95 * n / 100) - 1` after sorting ascending, using integer arithmetic.
One sample makes every rank equal that sample. Zero samples are
`Duration.zero`.

## Where to next

- [Capturing a single frame](capturing-a-single-frame.md) for covers and
  previews.
- [Performance](../advanced/performance.md) for the frame cache. A hit still
  pumps the tree and skips the pixel readback.
