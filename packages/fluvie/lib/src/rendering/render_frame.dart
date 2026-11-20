import 'package:flutter/widgets.dart' show GlobalKey, Widget;
import 'package:fluvie/src/composition/runtime/aspect_scope.dart';
import 'package:fluvie/src/composition/video.dart';
import 'package:fluvie/src/core/aspect.dart';
import 'package:fluvie/src/core/contracts/clip_frame_preparer.dart';
import 'package:fluvie/src/core/contracts/generative_resolver.dart'
    show GenerativeProgress, GenerativeResolver;
import 'package:fluvie/src/core/contracts/media_resolver.dart' show MediaResolver;
import 'package:fluvie/src/core/defaults.dart';
import 'package:fluvie/src/core/video_size.dart';
import 'package:fluvie/src/rendering/capture/capture_shell.dart';
import 'package:fluvie/src/rendering/capture/frame_capture_service.dart';
import 'package:fluvie/src/rendering/capture/raw_frame.dart';
import 'package:fluvie/src/rendering/capture/repaint_boundary_capture_service.dart';
import 'package:fluvie/src/rendering/collect_composition_media.dart';
import 'package:fluvie/src/rendering/no_generative_resolver.dart';
import 'package:fluvie/src/rendering/prepare_composition_media.dart';
import 'package:fluvie/src/rendering/render_aspect.dart' show ShellFramePump, ShellMount;
import 'package:fluvie/src/rendering/runtime/render_controller.dart';

/// Converts a wall-clock instant [at] into a zero-based frame index at [fps].
///
/// Each frame `k` covers the half-open interval `[k / fps, (k + 1) / fps)`, so
/// instants inside the final frame interval (such as `999ms` in a 1 s, 30 fps
/// video) map to the last valid frame (`29`) via integer floor division.
///
/// Throws an [ArgumentError] when [fps] is not positive or [at] is negative,
/// and a [RangeError] when the result cannot fit in an `int`.
int frameIndexFor(Duration at, {int fps = VideoDefaults.fps}) {
  if (fps <= 0) {
    throw ArgumentError.value(fps, 'fps', 'must be positive');
  }
  if (at.isNegative) {
    throw ArgumentError.value(at.toString(), 'at', 'must be >= Duration.zero');
  }
  final index =
      BigInt.from(at.inMicroseconds) *
      BigInt.from(fps) ~/
      BigInt.from(Duration.microsecondsPerSecond);
  if (!index.isValidInt) throw RangeError('The frame index for $at at $fps fps is too large.');
  return index.toInt();
}

/// Resolves the frame and canvas for a still capture before allocating a host.
///
/// Uses the same clock and range validation as [captureFrame].
({int frame, VideoSize size}) resolveFrameCapture({
  required Widget composition,
  required Aspect aspect,
  int? frame,
  Duration? at,
  int? fps,
  int longEdge = VideoDefaults.longEdge,
}) {
  final video = compositionVideo(composition);
  final resolvedFps = _resolveCaptureFps(video: video, explicitFps: fps);
  return (
    frame: _resolveTargetFrame(frame: frame, at: at, fps: resolvedFps, video: video),
    size: aspect.sizeFor(longEdge),
  );
}

/// Captures a single deterministic [RawFrame] of [composition] for [aspect] at
/// any point on its timeline, without running a multi-frame video encode.
///
/// Specify the target instant with either [frame] (zero-based index) or [at]
/// (wall-clock duration converted via [frameIndexFor]); passing both throws an
/// [ArgumentError], and omitting both captures frame `0`.
///
/// Clock and range rules for `Video` compositions:
/// - When [fps] is omitted it defaults to `video.fps` (or [VideoDefaults.fps]
///   for non-`Video` compositions). Passing an explicit [fps] that differs from
///   `video.fps` throws an [ArgumentError] so time conversion and scene timing
///   cannot disagree.
/// - The target frame must lie in `0 .. video.totalFrames - 1`; requests at or
///   beyond `video.totalFrames` throw a [RangeError] instead of returning blank
///   pixels.
///
/// Parity mode:
/// - When [stepThrough] is `false` (default), capture mounts at frame `0` and
///   seeks directly to the target frame. Frame-driven widgets can produce the
///   same pixels as sequential capture on the same host.
/// - Set [stepThrough] to `true` to pump every intermediate frame `0..target`
///   before reading back the target frame. This preserves frame-index history.
///   Native Flutter animations also require a host that advances ticker time
///   during [pumpFrame].
Future<RawFrame> captureFrame({
  required Widget composition,
  required Aspect aspect,
  required ShellMount pumpWidget,
  required ShellFramePump pumpFrame,
  int? frame,
  Duration? at,
  int? fps,
  int longEdge = VideoDefaults.longEdge,
  bool stepThrough = false,
  FrameCaptureService capture = const RepaintBoundaryCaptureService(),
  MediaResolver? resolver,
  GenerativeResolver generative = const NoGenerativeResolver(),
  void Function(GenerativeProgress progress)? onGenerativeProgress,
}) async {
  final (frame: targetFrame, :size) = resolveFrameCapture(
    composition: composition,
    aspect: aspect,
    frame: frame,
    at: at,
    fps: fps,
    longEdge: longEdge,
  );
  final framesToPump = stepThrough
      ? Iterable<int>.generate(targetFrame).followedBy([targetFrame])
      : [targetFrame];
  await prepareCompositionMedia(
    composition: composition,
    totalFrames: targetFrame + 1,
    clipFrames: stepThrough || targetFrame == 0 ? framesToPump : [0, targetFrame],
    resolver: resolver,
    generative: generative,
    onGenerativeProgress: onGenerativeProgress,
  );
  final controller = RenderController();
  final boundaryKey = GlobalKey();
  final shell = buildCaptureShell(
    composition: AspectScope(aspect: aspect, child: composition),
    boundaryKey: boundaryKey,
    controller: controller,
    canvasSize: size,
    resolver: resolver,
    generativeResolver: generative,
  );
  final preparer = resolver != null && resolver is ClipFramePreparer
      ? resolver as ClipFramePreparer
      : null;
  try {
    await preparer?.prepareClipFrames(0);
    await pumpWidget(shell.tree);
    for (final current in framesToPump) {
      await preparer?.prepareClipFrames(current);
      controller.seek(current);
      shell.mountedSnapshotScope?.resetCursor();
      await pumpFrame();
    }
    return await capture.capture(
      boundaryKey: boundaryKey,
      frameIndex: targetFrame,
      width: size.width,
      height: size.height,
    );
  } finally {
    controller.dispose();
  }
}

int _resolveCaptureFps({required Video? video, required int? explicitFps}) {
  if (explicitFps != null && explicitFps <= 0) {
    throw ArgumentError.value(explicitFps, 'fps', 'must be positive');
  }
  if (video != null && explicitFps != null && explicitFps != video.fps) {
    throw ArgumentError.value(
      explicitFps,
      'fps',
      'must match the Video composition fps (${video.fps})',
    );
  }
  return explicitFps ?? video?.fps ?? VideoDefaults.fps;
}

int _resolveTargetFrame({
  required int? frame,
  required Duration? at,
  required int fps,
  required Video? video,
}) {
  if (frame != null && at != null) {
    throw ArgumentError('Specify either frame or at, not both.');
  }
  final int target;
  if (frame != null) {
    if (frame < 0) {
      throw ArgumentError.value(frame, 'frame', 'must be >= 0');
    }
    target = frame;
  } else if (at != null) {
    target = frameIndexFor(at, fps: fps);
  } else {
    target = 0;
  }
  if (video != null && target >= video.totalFrames) {
    throw RangeError.range(
      target,
      0,
      video.totalFrames - 1,
      'frame',
      'target frame exceeds the Video length (${video.totalFrames} frames at $fps fps)',
    );
  }
  return target;
}
