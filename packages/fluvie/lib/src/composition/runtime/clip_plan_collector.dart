import 'package:flutter/widgets.dart';
import 'package:fluvie/src/animation/motion_target.dart';
import 'package:fluvie/src/composition/runtime/scene_tree_walk.dart';
import 'package:fluvie/src/composition/scene.dart';
import 'package:fluvie/src/core/contracts/generative_resolver.dart';
import 'package:fluvie/src/core/media/clip_audio.dart';
import 'package:fluvie/src/core/media/clip_source_kind.dart';
import 'package:fluvie/src/core/media/generative_kind.dart';
import 'package:fluvie/src/core/media/media_carrier.dart';
import 'package:fluvie/src/core/media/media_source.dart';
import 'package:fluvie/src/core/time_range.dart';
import 'package:fluvie/src/elements/clip.dart';
import 'package:fluvie/src/elements/generative_media.dart';
import 'package:fluvie/src/timing/placement/scene_frame_resolver.dart';
import 'package:fluvie/src/timing/placement/window_resolver.dart';
import 'package:fluvie/src/timing/time_scope_data.dart';

/// A clip-painting carrier paired with what the pre-pass plans against: the
/// resolved scene or element window, and its `trim` (`null` for a
/// `Background.video`, which plays the whole source).
typedef ClipPlan = ({
  MediaSource source,
  int sceneIndex,
  int windowStart,
  int windowLength,
  TimeRange? trim,
});

/// Pairs each clip-painting carrier in [scenes] with its trim and its resolved
/// scene or enclosing element window in frames at [fps].
///
/// Walks [declaredChildren] and resolves animated element windows against the
/// same enclosing scope as the mounted clip painter.
/// Pass [sceneStartFrames] and [videoFrames] to use the resolved video
/// timeline, including overlaps and its root scope.
List<ClipPlan> collectClipPlans(
  List<Scene> scenes,
  int fps, {
  GenerativeResolver? generative,
  List<int>? sceneStartFrames,
  int? videoFrames,
}) {
  final plans = <ClipPlan>[];
  _walkClipWindows(scenes, fps, sceneStartFrames, videoFrames, (widget, scope, sceneIndex) {
    if (widget is GenerativeMedia && widget.source.kind == GenerativeKind.video) {
      if (generative == null) return;
      plans.add((
        source: generative.mediaFor(widget.source),
        sceneIndex: sceneIndex,
        windowStart: scope.startFrame,
        windowLength: scope.durationFrames,
        trim: widget.trim,
      ));
      return;
    }
    if (widget is MediaCarrier) {
      final source = (widget as MediaCarrier).mediaSource;
      if (source != null && isClipSource(source)) {
        plans.add((
          source: source,
          sceneIndex: sceneIndex,
          windowStart: scope.startFrame,
          windowLength: scope.durationFrames,
          trim: widget is Clip ? widget.trim : null,
        ));
      }
    }
  });
  return plans;
}

/// One clip's embedded-audio plan: the `source` to extract audio from, where it
/// starts in the composition (`startFrame`), how long it plays (`windowFrames`
/// — its resolved element or scene window), plus the clip's `audio` policy and any `trim`.
typedef ClipAudioPlan = ({
  MediaSource source,
  int startFrame,
  int windowFrames,
  ClipAudio audio,
  TimeRange? trim,
});

/// Gathers an audio plan for every `Clip` whose [ClipAudio] keeps its track,
/// using [sceneStartFrames] when supplied so audio starts with the image,
/// including during overlaps. Pass [videoFrames] for the root video scope.
/// Walks the same scoped tree as
/// [collectClipPlans]; a muted clip or a non-clip source contributes nothing.
List<ClipAudioPlan> collectClipAudioPlans(
  List<Scene> scenes,
  int fps, {
  GenerativeResolver? generative,
  List<int>? sceneStartFrames,
  int? videoFrames,
}) {
  final plans = <ClipAudioPlan>[];
  _walkClipWindows(scenes, fps, sceneStartFrames, videoFrames, (widget, scope, _) {
    if (scope.durationFrames == 0) return;
    if (widget is GenerativeMedia && widget.source.kind == GenerativeKind.video) {
      if (generative == null || widget.audio.muted) return;
      if (!generative.metaFor(widget.source).hasAudio) return;
      plans.add((
        source: generative.mediaFor(widget.source),
        startFrame: scope.startFrame,
        windowFrames: scope.durationFrames,
        audio: widget.audio,
        trim: widget.trim,
      ));
      return;
    }
    if (widget is! Clip || widget.audio.muted) return;
    final source = widget.mediaSource;
    if (source == null || !isClipSource(source)) return;
    plans.add((
      source: source,
      startFrame: scope.startFrame,
      windowFrames: scope.durationFrames,
      audio: widget.audio,
      trim: widget.trim,
    ));
  });
  return plans;
}

void _walkClipWindows(
  List<Scene> scenes,
  int fps,
  List<int>? sceneStartFrames,
  int? videoFrames,
  void Function(Widget, TimeScopeData, int) visit,
) {
  final videoScope = videoFrames == null
      ? null
      : TimeScopeData(fps: fps, startFrame: 0, durationFrames: videoFrames);
  var windowStart = 0;
  for (var s = 0; s < scenes.length; s++) {
    final scene = scenes[s];
    final windowLength = resolveSceneDurationFrames(scene.duration, fps, 'scenes[$s]');
    final start = sceneStartFrames?[s] ?? windowStart;
    final sceneScope = TimeScopeData(
      fps: fps,
      startFrame: start,
      durationFrames: windowLength,
      parent: videoScope,
    );
    void walk(Widget widget, TimeScopeData scope) {
      visit(widget, scope, s);
      final childScope = widget is MotionTarget ? elementScopeFor(widget.window, scope) : scope;
      for (final child in declaredChildren(widget)) {
        walk(child, childScope);
      }
    }

    final background = scene.background;
    if (background != null) walk(background, sceneScope);
    for (final child in scene.children) {
      walk(child, sceneScope);
    }
    windowStart += windowLength;
  }
}
