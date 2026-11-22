import 'dart:math' as math;

import 'package:fluvie/src/composition/runtime/audio_collector.dart';
import 'package:fluvie/src/composition/runtime/reactive_audio_window.dart';
import 'package:fluvie/src/composition/video.dart';
import 'package:fluvie/src/core/anchor.dart';
import 'package:fluvie/src/core/audio/audio_source.dart';
import 'package:fluvie/src/timing/time_scope_data.dart';

/// The reactive audio tracks a composition declares, gathered for the
/// pre-resolve pass.
///
/// [byAnchor] maps each `Audio.track` anchor to its source (for `track:`-scoped
/// reactivity); [defaultSource] is the first declared track (the master mix a
/// reactive effect with no `track:` reads); [allSources] is the deduplicated set
/// the shell hands to `MediaResolver.preResolveReactive` so each track is
/// analysed once before frame 0.
final class ReactiveTracks {
  /// Creates the gathered reactive tracks.
  const ReactiveTracks({
    required this.byAnchor,
    required this.defaultSource,
    required this.allSources,
    this.defaultWindow,
    this.windows = const {},
  });

  /// Per-track sources keyed by the `Audio.track` anchor.
  final Map<Anchor, AudioSource> byAnchor;

  /// The master source (the first declared track), or `null` when silent.
  final AudioSource? defaultSource;

  /// The deduplicated set of sources to analyse before frame 0.
  final Set<AudioSource> allSources;

  /// Playback window for the default source when declared by a scene.
  final ReactiveAudioWindow? defaultWindow;

  /// Scene playback windows by authored track anchor.
  final Map<Anchor, ReactiveAudioWindow> windows;

  /// Includes enough source analysis to read trimmed scene tracks.
  int analysisFrames(int frameCount) => [
    ?defaultWindow,
    ...windows.values,
  ].fold(frameCount, (frames, window) => math.max(frames, window.analysisFrames));
}

/// Gathers every reactive audio track [video] declares — a pure structural read
/// over the constructor data, no mounting and no async.
///
/// The first declared track becomes the default (master) source the reactive
/// scope serves to untracked effects; every track that carries an `Audio.track`
/// anchor is also mapped by that anchor so a `track:`-scoped effect reads its
/// own table. The set is deduplicated so two tracks naming one origin analyse
/// once.
ReactiveTracks collectReactiveTracks(Video video, {int? frameCount}) {
  final placements = collectAudioPlacements(video);
  final defaultSource = placements.isEmpty ? null : placements.first.track.audioSource;
  final byAnchor = <Anchor, AudioSource>{};
  final windows = <Anchor, ReactiveAudioWindow>{};
  ReactiveAudioWindow? defaultWindow;
  final offsets = video.sceneOffsets;
  final duration = frameCount ?? offsets.totalFrames;
  final scope = TimeScopeData(fps: video.fps, startFrame: 0, durationFrames: duration);
  for (final (index, (:track, :sceneIndex)) in placements.indexed) {
    final anchor = track.track;
    if (anchor != null) {
      byAnchor[anchor] = track.audioSource;
      windows.remove(anchor);
    }
    if (sceneIndex == null || (index != 0 && anchor == null)) continue;
    final window = ReactiveAudioWindow(
      resolveAudioPlacement(track, sceneIndex: sceneIndex, offsets: offsets, scope: scope),
      duration,
      fps: video.fps,
    );
    if (index == 0) defaultWindow = window;
    if (anchor != null) windows[anchor] = window;
  }
  return ReactiveTracks(
    byAnchor: byAnchor,
    defaultSource: defaultSource,
    allSources: {for (final placement in placements) placement.track.audioSource},
    defaultWindow: defaultWindow,
    windows: windows,
  );
}
