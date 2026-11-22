import 'dart:math' as math;

import 'package:fluvie/src/audio/encoding/resolved_audio_track.dart';
import 'package:fluvie/src/composition/runtime/audio_collector.dart';
import 'package:fluvie/src/composition/runtime/clip_plan_collector.dart';
import 'package:fluvie/src/composition/video.dart';
import 'package:fluvie/src/core/contracts/generative_resolver.dart';
import 'package:fluvie/src/core/contracts/media_resolver.dart';
import 'package:fluvie/src/core/media/media_source.dart';
import 'package:fluvie/src/elements/runtime/clip_frame_planner.dart';
import 'package:fluvie/src/timing/time_scope_data.dart';

/// Resolves [video]'s declared `Audio` tracks into an encoder-neutral
/// [ResolvedAudioMix] for a non-FFmpeg encoder (such as `fluvie_mobile_encoder`).
///
/// It collects the tracks in deterministic declaration order and resolves every
/// track's delay, trim, gain, and fades against [fps] and the [totalFrames]
/// window — the same timing math the FFmpeg mix uses, so an on-device render
/// matches a desktop render. Pure and synchronous: it reads no files, so each
/// track keeps its authored [ResolvedAudioTrack.source]; the custom encoder
/// materializes those sources itself. The default render path never calls this;
/// it is the opt-in seam for custom encoders. A video with no audio yields an
/// empty mix. Supply [clipMetadataFor] to resolve frame and relative trims
/// against the source and omit clips with no audio stream. Without metadata,
/// trims use the clip window as the scope.
ResolvedAudioMix resolveAudioMix({
  required Video video,
  required int fps,
  int totalFrames = 0,
  GenerativeResolver? generative,
  ClipMetadata Function(MediaSource)? clipMetadataFor,
}) {
  final scope = TimeScopeData(fps: fps, startFrame: 0, durationFrames: totalFrames);
  final tracks = <ResolvedAudioTrack>[
    ...resolveDeclaredAudioTracks(
      video,
      fps: fps,
      totalFrames: totalFrames,
      generative: generative,
    ),
    // A clip's embedded audio (including a generated video's, for example Veo 3)
    // plays over the same resolved window as the image.
    for (final plan in collectClipAudioPlans(
      video.scenes,
      video.fps,
      generative: generative,
      sceneStartFrames: video.sceneStartFrames,
      videoFrames: video.totalFrames,
    ))
      ?resolveClipAudioTrack(plan, scope, clipMetadataFor: clipMetadataFor),
  ];
  return ResolvedAudioMix(tracks: tracks);
}

/// Resolves authored music and one-shots on the video or declaring scene clock.
List<ResolvedAudioTrack> resolveDeclaredAudioTracks(
  Video video, {
  required int fps,
  required int totalFrames,
  GenerativeResolver? generative,
}) {
  final composition = TimeScopeData(fps: fps, startFrame: 0, durationFrames: totalFrames);
  final offsets = video.sceneOffsets;
  final tracks = <ResolvedAudioTrack>[];
  for (final (:track, :sceneIndex) in collectAudioPlacements(video, generative: generative)) {
    final resolved = resolveAudioPlacement(
      track,
      sceneIndex: sceneIndex,
      offsets: offsets,
      scope: composition,
    );
    if (resolved.maxPlaybackSeconds != 0) tracks.add(resolved);
  }
  return tracks;
}

/// Resolves one clip-audio [plan] to an encoder-neutral track: its source file
/// (the video — the encoder extracts the audio track), delayed to the clip's
/// start and trimmed to its window, at the clip's authored volume and fade-in.
ResolvedAudioTrack? resolveClipAudioTrack(
  ClipAudioPlan plan,
  TimeScopeData scope, {
  ClipMetadata Function(MediaSource)? clipMetadataFor,
}) {
  final fps = scope.fps;
  final windowSeconds = plan.windowFrames / fps;
  final metadata = clipMetadataFor?.call(plan.source);
  if (metadata?.hasAudio == false) return null;
  final trim = plan.trim;
  var start = 0.0;
  var end = windowSeconds;
  if (trim != null) {
    if (metadata == null) {
      final sceneScope = TimeScopeData(fps: fps, startFrame: 0, durationFrames: plan.windowFrames);
      final bounds = trim.resolveFrames(sceneScope);
      start = math.max(0, bounds.start) / fps;
      end = bounds.end / fps;
    } else {
      final bounds = resolveClipTrimBounds(trim, metadata);
      start = bounds.start / metadata.fps;
      end = bounds.end / metadata.fps;
    }
    end = math.min(end, start + windowSeconds);
  }
  if (end <= start) return null;
  final fadeIn = plan.audio.fadeIn.resolveFrames(scope) / fps;
  return ResolvedAudioTrack(
    source: _sourceString(plan.source),
    delayMs: (plan.startFrame / fps * 1000).round(),
    volume: plan.audio.volume,
    trimStartSeconds: start,
    trimEndSeconds: end,
    fadeInSeconds: fadeIn > 0 ? fadeIn : null,
  );
}

/// The authored source string the audio materializer resolves: a file path for
/// a device clip, an asset key for a bundled clip.
String _sourceString(MediaSource source) => switch (source) {
  AssetSource(:final name) => name,
  FileSource(:final path) => path,
  NetworkSource(:final url) => url.toString(),
  MemorySource() => '',
};
