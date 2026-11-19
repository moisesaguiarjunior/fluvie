# Capturing a single frame

Capture one deterministic frame of a Fluvie composition at any instant without
running a multi-frame video encode. Use this to pick a video cover, preview a
point on the timeline, or export a still PNG with alpha transparency (such as a
partially revealed stitch or watercolor layer).

Call `captureCover()` from your Flutter app after the widgets binding has
initialized. You get PNG bytes for the middle of a one-second composition.

<!-- code-excerpt "packages/fluvie_mobile_encoder/example/still_capture.dart (on-device)" -->
```dart
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:fluvie/fluvie.dart';
import 'package:fluvie/rendering.dart';
import 'package:fluvie_mobile_encoder/fluvie_mobile_encoder.dart';

Video coverScene() => Video(
  width: 96,
  height: 96,
  scenes: const [
    Scene(
      duration: Time.seconds(1),
      children: [
        Center(
          child: SizedBox(
            width: 64,
            height: 64,
            child: ColoredBox(color: Color(0xFF2A9D8F)),
          ),
        ),
      ],
    ),
  ],
);

Future<Uint8List> captureCover() => OnDeviceVideoRenderer().capturePng(
  composition: coverScene(),
  aspect: Aspect.square,
  at: const Duration(milliseconds: 500),
  longEdge: 96,
);
```

Use `OnDeviceVideoRenderer.captureFrame` when you need raw RGBA8888 pixels.
Both methods skip the platform video encoder and the temporary video sandbox.

If you own the capture host, use `package:fluvie/rendering.dart` and pass
callbacks that mount and pump its 96-by-96 canvas. Dispose your host when you
finish. Pass a media resolver when your composition declares media.

<!-- code-excerpt "packages/fluvie_mobile_encoder/example/still_capture.dart (custom-host)" -->
```dart
Future<Uint8List> captureCoverWithHost({
  required ShellMount mount,
  required ShellFramePump pump,
}) async {
  final raw = await captureFrame(
    composition: Directionality(textDirection: TextDirection.ltr, child: coverScene()),
    aspect: Aspect.square,
    frame: 15,
    longEdge: 96,
    pumpWidget: mount,
    pumpFrame: pump,
  );
  return encodeRawFramePng(raw);
}
```

## Time, clock, and range contract

Pass either `frame` (zero-based index) or `at` (wall-clock `Duration`). Leave
both `null` to capture frame `0`.

- **Floor mapping per frame interval.** `frameIndexFor(at, fps: fps)` uses exact
  integer floor division (`(at.inMicroseconds * fps) ~/ 1000000`). Frame `k`
  covers the half-open interval `[k / fps, (k + 1) / fps)`. In a 1 second,
  30 fps `Video` (frames `0..29`), `999ms` maps to frame `29` (the last valid
  frame) instead of rounding past the end.
- **Single clock on `Video` compositions.** When `composition` wraps a `Video`,
  omitting `fps` uses `video.fps`. Passing an explicit `fps` that disagrees with
  `video.fps` throws an `ArgumentError`, so time conversion and scene timing
  always share one clock.
- **Out-of-range frames fail loudly.** When `composition` wraps a `Video`, any
  target frame at or beyond `video.totalFrames` (for example `1000ms` or
  `frame: 30` on a 30-frame video) throws a `RangeError` before mounting rather
  than returning blank transparent pixels.

## Parity with full video rendering

`captureFrame` supports two modes through `stepThrough`:

- **`stepThrough: false` (default, direct seek).** Capture mounts at frame 0,
  seeks to the target, and pumps once. Use this for frame-driven work such as
  Fluvie animations, captions, clips, or a Handcrafted painter driven by
  `FrameBuilder` progress. Compare pixels against a sequential render on the
  same host with the same media and render settings.
- **`stepThrough: true` (sequential).** Capture pumps frames 0 through the
  target in order and reads the target pixels. Use this when widget state
  depends on visiting earlier frames. Native Flutter tickers need elapsed
  time from the host. The default mobile host only pumps the offscreen tree.
  Drive native effects from the frame index or provide a host that advances
  ticker time.

Clip preparation samples the frames used by the chosen mode. The mount at
frame 0 also needs its clip frames.

## Transparency and error handling

- **Alpha channel preserved.** `RawFrame` stores raw RGBA8888 pixels, and
  `encodeRawFramePng` writes PNG bytes without flattening transparency.
- **Input validation.** Invalid `frame` (`< 0`), negative `at`, passing both
  `frame` and `at`, non-positive `fps` or `longEdge`, an `fps` mismatch against
  `Video.fps`, or a `RawFrame` with non-positive dimensions throws an
  `ArgumentError` (or `RangeError` for out-of-range `Video` frames) before
  mounting or invoking the image codec.
- **Codec failures.** `encodeRawFramePng` checks the dimensions and buffer
  length. Decode and encode failures complete the returned `Future` with an
  error.

## Where to next

- [On-device mobile rendering](on-device-mobile-rendering.md) to render full MP4
  videos on Android and iOS.
- [Exporting your video](exporting-your-video.md) for MP4, GIF, image sequence,
  and transparent video exports.
- [External material surfaces](../../docs/external-materials.md) to compose
  `handcrafted_flutter` materials around declared Fluvie media.
