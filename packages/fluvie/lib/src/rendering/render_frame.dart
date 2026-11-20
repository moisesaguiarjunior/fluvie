import 'package:flutter/widgets.dart' show GlobalKey, Widget;
import 'package:fluvie/src/composition/runtime/aspect_scope.dart';
import 'package:fluvie/src/core/aspect.dart';
import 'package:fluvie/src/core/contracts/clip_frame_preparer.dart';
import 'package:fluvie/src/core/contracts/generative_resolver.dart'
    show GenerativeProgress, GenerativeResolver;
import 'package:fluvie/src/core/contracts/media_resolver.dart' show MediaResolver;
import 'package:fluvie/src/core/defaults.dart';
import 'package:fluvie/src/rendering/capture/capture_shell.dart';
import 'package:fluvie/src/rendering/capture/frame_capture_service.dart';
import 'package:fluvie/src/rendering/capture/raw_frame.dart';
import 'package:fluvie/src/rendering/capture/repaint_boundary_capture_service.dart';
import 'package:fluvie/src/rendering/frame_capture_target.dart';
import 'package:fluvie/src/rendering/no_generative_resolver.dart';
import 'package:fluvie/src/rendering/prepare_composition_media.dart';
import 'package:fluvie/src/rendering/render_aspect.dart' show ShellFramePump, ShellMount;
import 'package:fluvie/src/rendering/render_metrics.dart' show RenderMetrics;
import 'package:fluvie/src/rendering/runtime/render_controller.dart';

export 'package:fluvie/src/rendering/frame_capture_target.dart'
    show frameIndexFor, resolveFrameCapture;

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
///
/// Pass [metrics] to record preparation, mounting, each pump, and the pixel
/// readback. `stepThrough` records one pumping sample per visited frame and
/// still consumes a single frame. Omit [metrics] and this capture allocates
/// no timing state. The returned pixels do not depend on the report.
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
  RenderMetrics? metrics,
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
  final mediaWatch = metrics == null ? null : (Stopwatch()..start());
  try {
    await prepareCompositionMedia(
      composition: composition,
      totalFrames: targetFrame + 1,
      clipFrames: stepThrough || targetFrame == 0 ? framesToPump : [0, targetFrame],
      resolver: resolver,
      generative: generative,
      onGenerativeProgress: onGenerativeProgress,
    );
  } finally {
    if (mediaWatch != null) {
      mediaWatch.stop();
      metrics!.addPreparation(mediaWatch.elapsed);
    }
  }
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
    final clipWatch = metrics == null ? null : (Stopwatch()..start());
    try {
      await preparer?.prepareClipFrames(0);
    } finally {
      if (clipWatch != null) {
        clipWatch.stop();
        metrics!.addPreparation(clipWatch.elapsed);
      }
    }
    final mountWatch = metrics == null ? null : (Stopwatch()..start());
    try {
      await pumpWidget(shell.tree);
    } finally {
      if (mountWatch != null) {
        mountWatch.stop();
        metrics!.addMounting(mountWatch.elapsed);
      }
    }
    for (final current in framesToPump) {
      final pumpWatch = metrics == null ? null : (Stopwatch()..start());
      try {
        await preparer?.prepareClipFrames(current);
        controller.seek(current);
        shell.mountedSnapshotScope?.resetCursor();
        await pumpFrame();
      } finally {
        if (pumpWatch != null) {
          pumpWatch.stop();
          metrics!.addPumping(pumpWatch.elapsed);
        }
      }
    }
    final readbackWatch = metrics == null ? null : (Stopwatch()..start());
    final RawFrame raw;
    try {
      raw = await capture.capture(
        boundaryKey: boundaryKey,
        frameIndex: targetFrame,
        width: size.width,
        height: size.height,
      );
    } finally {
      if (readbackWatch != null) {
        readbackWatch.stop();
        metrics!.addReadback(readbackWatch.elapsed);
      }
    }
    metrics?.addFrame();
    return raw;
  } finally {
    controller.dispose();
  }
}
