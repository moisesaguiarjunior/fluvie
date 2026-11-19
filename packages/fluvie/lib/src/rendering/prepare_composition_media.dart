import 'package:flutter/widgets.dart' show Widget;
import 'package:fluvie/src/composition/runtime/caption_collector.dart';
import 'package:fluvie/src/core/contracts/generative_resolver.dart'
    show GenerativeProgress, GenerativeResolver;
import 'package:fluvie/src/core/contracts/media_resolver.dart' show MediaResolver;
import 'package:fluvie/src/rendering/collect_composition_media.dart';
import 'package:fluvie/src/rendering/no_generative_resolver.dart';
import 'package:fluvie/src/rendering/pre_resolve_clips.dart';

/// Runs the shared media, caption, generative, and clip pre-resolution pass
/// before mounting a capture shell.
///
/// Order matters: generative sources materialize files first, `preResolveAll`
/// warms the decoded image/clip cache, captions resolve into parsed cues, and
/// `preResolveCompositionClips` probes clips and extracts source frames across
/// [totalFrames] or at the supplied [clipFrames] composition indices.
/// A `null` [resolver] is a no-op (media-less capture).
Future<void> prepareCompositionMedia({
  required Widget composition,
  required int totalFrames,
  required MediaResolver? resolver,
  Iterable<int>? clipFrames,
  GenerativeResolver generative = const NoGenerativeResolver(),
  void Function(GenerativeProgress progress)? onGenerativeProgress,
}) async {
  if (resolver == null) return;
  await generative.generateAll(
    collectCompositionGenerative(composition),
    onProgress: onGenerativeProgress,
  );
  await resolver.preResolveAll(collectCompositionMedia(composition, generative: generative));
  final video = compositionVideo(composition);
  final captionSource = video == null ? null : collectCaptionSource(video);
  if (captionSource != null) {
    await resolver.preResolveCaptions(captionSource);
  }
  await preResolveCompositionClips(
    composition: composition,
    resolver: resolver,
    totalFrames: totalFrames,
    compositionFrames: clipFrames,
    generative: generative,
  );
}
