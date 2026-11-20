import 'package:flutter/widgets.dart' show Widget;
import 'package:fluvie/src/composition/video.dart';
import 'package:fluvie/src/core/aspect.dart';
import 'package:fluvie/src/core/defaults.dart';
import 'package:fluvie/src/core/video_size.dart';
import 'package:fluvie/src/rendering/collect_composition_media.dart';

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
/// Uses the same clock and range validation as `captureFrame`.
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
