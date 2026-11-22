// fluvie:large-file-ok: the canonical multi-aspect render entry; one public render() plus its private helpers
import 'dart:io';

import 'package:flutter/widgets.dart' show BuildContext, Element, GlobalKey, Widget;
import 'package:fluvie/src/audio/encoding/audio_mix_staging.dart';
import 'package:fluvie/src/composition/runtime/aspect_scope.dart';
import 'package:fluvie/src/composition/runtime/audio_collector.dart';
import 'package:fluvie/src/composition/runtime/clip_plan_collector.dart'
    show ClipAudioPlan, collectClipAudioPlans;
import 'package:fluvie/src/composition/runtime/frame_scene_scope.dart';
import 'package:fluvie/src/composition/video.dart';
import 'package:fluvie/src/core/aspect.dart';
import 'package:fluvie/src/core/audio/audio_source.dart';
import 'package:fluvie/src/core/contracts/clip_frame_preparer.dart';
import 'package:fluvie/src/core/contracts/generative_resolver.dart'
    show GenerativeProgress, GenerativeResolver;
import 'package:fluvie/src/core/contracts/media_resolver.dart' show MediaResolver;
import 'package:fluvie/src/core/defaults.dart';
import 'package:fluvie/src/rendering/audio_mix_resolution.dart' show resolveDeclaredAudioTracks;
import 'package:fluvie/src/rendering/capture/capture_shell.dart';
import 'package:fluvie/src/rendering/capture/render_manifest.dart';
import 'package:fluvie/src/rendering/clip_audio_staging.dart';
import 'package:fluvie/src/rendering/collect_composition_media.dart';
import 'package:fluvie/src/rendering/encoding/content_hash.dart';
import 'package:fluvie/src/rendering/no_generative_resolver.dart';
import 'package:fluvie/src/rendering/prepare_composition_media.dart';
import 'package:fluvie/src/rendering/render_config.dart';
import 'package:fluvie/src/rendering/render_metrics.dart';
import 'package:fluvie/src/rendering/render_service.dart';
import 'package:fluvie/src/rendering/runtime/render_controller.dart';

/// Mounts [tree] (the full capture shell) into the host's element tree before
/// the frame loop starts. A widget test passes `tester.pumpWidget`; the CLI
/// passes its binding's pump.
typedef ShellMount = Future<void> Function(Widget tree);

/// Pumps the host one frame after the controller seeks, so the just-seeked
/// frame is fully built before its pixels are read. A widget test passes
/// `() => tester.pump()`; the CLI passes its binding's pump.
typedef ShellFramePump = Future<void> Function();

/// What [render] returns: the captured `manifest` and the `config` whose width
/// and height were re-derived from `Aspect.sizeFor` for the rendered aspect.
typedef RenderAspectResult = ({RenderManifest manifest, RenderConfig config});

/// Renders [composition] for a single [aspect] — the canonical multi-aspect
/// entry.
///
/// It re-derives the canvas size from `aspect.sizeFor(longEdge)` (ignoring any
/// size the composition declares for itself), mounts an [AspectScope] over the
/// composition so every `Adaptive` and `AspectScope.of(context)` branch lays out
/// for this aspect, builds the production [buildCaptureShell] around it, and runs the
/// shell once through [RenderService.captureToDirectory]. Timing and animations
/// resolve identically across aspects — the same plan resolves; only layout
/// branches — so the per-aspect renders share a clock and differ only in shape.
///
/// This is distinct from [RenderService.render], the instance method that
/// captures and encodes one fixed-size composition: [render] is the free
/// function that re-derives the size per aspect and drives that same service.
/// (It is also distinct from `renderTemplate`, which renders a parameterized
/// `VideoTemplate` — Dart has no overloading, so each is its own free function.)
///
/// The host owns the pumping mechanics through [pumpWidget] and [pumpFrame],
/// which keeps this offline and gate-runnable (the example and goldens pass a
/// `flutter_test` pump; the CLI passes its binding's). To encode the result, run
/// the returned manifest's ffmpeg args through an `FfmpegRunner`.
///
/// When [composition] is a [Video] that declares `Audio`, its tracks are staged
/// into the encoder mix by default: the resulting
/// file is **not silent**. Pass [stageAudio] (with [audioSources]) to override
/// the default — for example when the audio-bearing `Video` is wrapped in
/// another widget the auto-collect cannot reach. A `Video` with no audio (or a
/// non-`Video` composition) stages nothing, so the encoder's `-an` path stands.
///
/// Pass a [resolver] to render declared media: its sources are collected from
/// [composition] and pre-resolved before the first pump, and it is mounted as
/// the `ImageResolverScope` the elements paint from. A null [resolver] keeps the
/// media-less path (a composition that declares an `Image`/`Clip` then throws a
/// `FluvieRenderException` naming the missing pre-resolution).
///
/// Each [aspect] re-derives its size from [longEdge] and renders independently,
/// so the same [composition] renders the same frames for that aspect; the encode
/// arg array, including the mix, is built from the plan.
///
/// [compositionKey] identifies the composition in the frame cache. The cache
/// key also gains the active aspect and the seed of every video mounted on the
/// initial pump. A video that first mounts on a later frame is absent from
/// that list, so [compositionKey] has to include its seed.
///
/// Pass [metrics] to record preparation, mounting, frame pumping, pixel
/// readback, and cache hits. Omit it and this render allocates no timing
/// state. The captured frames do not depend on the report.
Future<RenderAspectResult> render({
  required Widget composition,
  required Aspect aspect,
  required int frameCount,
  required Directory outDir,
  required RenderService service,
  required ShellMount pumpWidget,
  required ShellFramePump pumpFrame,
  int longEdge = VideoDefaults.longEdge,
  int fps = VideoDefaults.fps,
  String compositionKey = 'render',
  bool cacheEnabled = false,
  AudioMixStager? stageAudio,
  Iterable<AudioSource>? audioSources,
  MediaResolver? resolver,
  GenerativeResolver generative = const NoGenerativeResolver(),
  void Function(GenerativeProgress progress)? onGenerativeProgress,
  RenderMetrics? metrics,
}) async {
  final size = aspect.sizeFor(longEdge);
  final config = RenderConfig(
    width: size.width,
    height: size.height,
    fps: fps,
    frameCount: frameCount,
    cacheEnabled: cacheEnabled,
  );
  // Pre-resolve declared and generated media before reading audio: generation
  // produces the files, the media pre-pass warms the decode cache, and the clip
  // pre-pass probes each clip — so the audio collector below knows which clips
  // actually carry an audio track. A null resolver is a media-less render.
  final mediaWatch = metrics == null ? null : (Stopwatch()..start());
  try {
    await prepareCompositionMedia(
      composition: composition,
      totalFrames: frameCount,
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
  // The encoder audio mix: an explicit stager wins; otherwise a `Video`
  // composition's own `Audio` tracks (plus any generated audio and a clip's
  // embedded audio) are collected and staged so a public `render(video, aspect:)`
  // of an audio composition is not silent.
  final audio = _audioFor(
    composition,
    explicitStager: stageAudio,
    explicitSources: audioSources,
    fps: fps,
    totalFrames: frameCount,
    generative: resolver != null ? generative : null,
    resolver: resolver,
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
  // Warm the first frame's clip window before the tree mounts: the initial
  // pumpWidget builds at frame 0, before the capture loop's first decode-ahead,
  // so without this the first build's synchronous clip lookup would miss (that
  // build is not captured — the loop re-pumps frame 0 — but it would still throw).
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
  final manifest = await service.captureToDirectory(
    config: config,
    outDir: outDir,
    pump: (frame) async {
      // Decode-ahead: a streaming resolver warms just the clip frames this
      // composition frame paints before the tree builds, so paint's
      // synchronous clip lookup is a hit without holding every frame in memory.
      await preparer?.prepareClipFrames(frame);
      controller.seek(frame);
      shell.mountedSnapshotScope?.resetCursor();
      await pumpFrame();
    },
    boundaryKey: boundaryKey,
    compositionKey: frameCacheCompositionKey(
      compositionKey,
      aspectName: aspect.name,
      // The initial pump is frame 0. Seeds joined here are the videos mounted
      // now, in tree order. A video that first mounts on a later frame is not
      // in this list; the caller-supplied compositionKey has to include it.
      seeds: _cacheSeeds(boundaryKey.currentContext, composition),
    ),
    audioSources: audio.audioSources,
    stageAudio: audio.stageAudio,
    metrics: metrics,
  );
  return (manifest: manifest, config: config);
}

/// Seeds that distinguish [composition] in the frame cache.
///
/// Videos mounted on the initial pump win, in the order their scopes appear
/// under the capture boundary. With none mounted, the key keeps the single
/// seed [compositionVideo] can see, or zero. A video that first mounts on a
/// later frame is absent; the caller-supplied composition key carries it.
List<int> _cacheSeeds(BuildContext? boundary, Widget composition) {
  final mounted = _mountedVideoSeeds(boundary);
  if (mounted.isNotEmpty) return mounted;
  return [compositionVideo(composition)?.seed ?? 0];
}

/// Seeds of the mounted videos under [boundary], in child order.
///
/// [compositionVideo] only sees a [Video] already present in the widget
/// configuration. A `Builder` creates that video while the shell builds, and
/// more than one video may mount, so the walk keeps going after the first
/// scope. Each [FrameSceneScope] that carries a composition size is a video.
/// The capture shell's own scope has no composition size and is skipped.
List<int> _mountedVideoSeeds(BuildContext? boundary) {
  if (boundary is! Element) return const [];
  final seeds = <int>[];
  void visit(Element element) {
    final widget = element.widget;
    if (widget is FrameSceneScope && widget.compositionSize != null) {
      seeds.add(widget.seed);
    }
    element.visitChildren(visit);
  }

  boundary.visitChildElements(visit);
  return seeds;
}

/// Resolves the encoder audio mix for [composition]: an explicit
/// [explicitStager]/[explicitSources] pair wins; otherwise a [Video]
/// composition's declared `Audio` tracks are collected and turned into a
/// [stageResolvedAudioMix] closure against [fps]/[totalFrames] (so `Audio.sfx(at:)`
/// resolves its `adelay`). A non-`Video` or track-less composition yields
/// `(null, const [])`, so the encoder's `-an` path is unchanged.
({AudioMixStager? stageAudio, Iterable<AudioSource> audioSources}) _audioFor(
  Widget composition, {
  required AudioMixStager? explicitStager,
  required Iterable<AudioSource>? explicitSources,
  required int fps,
  required int totalFrames,
  GenerativeResolver? generative,
  MediaResolver? resolver,
}) {
  if (explicitStager != null) {
    return (stageAudio: explicitStager, audioSources: explicitSources ?? const []);
  }
  final video = compositionVideo(composition);
  if (video == null) return (stageAudio: null, audioSources: const []);
  final tracks = resolveDeclaredAudioTracks(
    video,
    fps: fps,
    totalFrames: totalFrames,
    generative: generative,
  );
  // Only clips that actually carry an audio track join the mix (each was probed
  // above); a silent clip would otherwise fail the encoder's `[N:a]` map.
  final clipMetadataFor = resolver?.clipMetadataFor;
  final clipPlans = clipMetadataFor == null
      ? const <ClipAudioPlan>[]
      : collectClipAudioPlans(
          video.scenes,
          video.fps,
          sceneStartFrames: video.sceneStartFrames,
          videoFrames: video.totalFrames,
          generative: generative,
        ).where((plan) => clipMetadataFor(plan.source).hasAudio).toList();
  if (tracks.isEmpty && clipPlans.isEmpty) {
    return (stageAudio: null, audioSources: const []);
  }
  return (
    stageAudio: ({required resolver, required sandbox}) async {
      // A clip's embedded audio (including a generated video's) is staged from
      // the clip's video file and joins the same amix as the declared tracks.
      final clipNodes = await stageClipAudio(
        plans: clipPlans,
        clipMetadataFor: clipMetadataFor,
        resolver: resolver,
        sandbox: sandbox,
        fps: fps,
        totalFrames: totalFrames,
      );
      final plan = await stageResolvedAudioMix(
        tracks: tracks,
        resolver: resolver,
        sandbox: sandbox,
        extraNodes: clipNodes,
      );
      return (nodes: plan.tracks, amix: plan.amix);
    },
    audioSources: {
      ...collectAudioSources(video, generative: generative),
      for (final plan in clipPlans) clipAudioSourceFor(plan.source),
    },
  );
}
