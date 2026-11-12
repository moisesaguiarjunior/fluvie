import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' hide Animation;
import 'package:fluvie/fluvie.dart';
import 'package:fluvie/rendering.dart';
import 'package:fluvie_mobile_encoder/fluvie_mobile_encoder.dart';

/// Ordinary production binding with application-frame scheduling disabled.
///
/// The offscreen pipeline must not depend on unrelated engine frames.
final class CaptureOnlyBinding extends WidgetsFlutterBinding {
  /// Frames [scheduleFrame] was asked to draw.
  int scheduleFrameCalls = 0;

  /// Frames [scheduleWarmUpFrame] was asked to draw.
  int warmUpCalls = 0;

  @override
  void scheduleFrame() {
    scheduleFrameCalls++;
  }

  @override
  void scheduleWarmUpFrame() {
    warmUpCalls++;
  }
}

/// Which caption source a capture contract renders.
enum CaptureCaptionKind { none, inline, srt, vtt }

/// Which render entry a capture contract calls.
enum CaptureEntry { aspect, sandbox }

/// Renders a synthetic 96 by 96 composition and returns the raw frames.
Future<Uint8List> captureFrames({
  required bool motion,
  bool captions = false,
  CaptureCaptionKind captionKind = CaptureCaptionKind.none,
  CaptureEntry entry = CaptureEntry.aspect,
  int frameCount = 30,
  Future<void> Function()? beforeFrame,
  FrameCaptureService capture = const RepaintBoundaryCaptureService(),
  List<OffscreenCaptureHost>? retainHost,
}) async {
  final directory = entry == CaptureEntry.aspect
      ? await Directory.systemTemp.createTemp('capture-contract-')
      : null;
  final sandbox = MemoryRenderSandbox();
  final host = OffscreenCaptureHost(const Size(96, 96));
  final scope = resolverScope(null);
  final child = Container(width: 20, height: 20, color: const Color(0xFFF2C14E));
  final kind = captions ? CaptureCaptionKind.inline : captionKind;
  final video = Video(
    width: 96,
    height: 96,
    captions: _captionsFor(kind),
    scenes: [
      Scene(
        duration: const Time.seconds(1),
        background: Background.color(const Color(0xFF101010)),
        children: [
          Center(
            child: motion
                ? child.animate([
                    Animation.fromTo(
                      const Keyframe(x: -1),
                      const Keyframe(x: 1),
                      phase: AnimationPhase.during,
                      duration: const Time.seconds(1),
                    ),
                  ])
                : child,
          ),
        ],
      ),
    ],
  );
  try {
    final composition = Directionality(textDirection: TextDirection.ltr, child: video);
    Future<void> pump() async {
      await beforeFrame?.call();
      await host.pumpFrame();
    }

    if (entry == CaptureEntry.sandbox) {
      final manifest = await renderToSandbox(
        composition: composition,
        aspect: Aspect.square,
        frameCount: frameCount,
        sandbox: sandbox,
        capture: capture,
        pumpWidget: host.mount,
        pumpFrame: pump,
        longEdge: 96,
        resolver: scope.resolver,
      );
      return await sandbox.readBytes(manifest.framesFileName);
    }
    final result = await render(
      composition: composition,
      aspect: Aspect.square,
      frameCount: frameCount,
      outDir: directory!,
      service: RenderService(capture: capture),
      pumpWidget: host.mount,
      pumpFrame: pump,
      longEdge: 96,
      resolver: scope.resolver,
    );
    return await File('${directory.path}/${result.manifest.framesFileName}').readAsBytes();
  } finally {
    await host.dispose();
    retainHost?.add(host);
    await scope.dispose();
    if (directory != null) await directory.delete(recursive: true);
  }
}

/// Counts gold motion pixels in packed RGBA bytes.
///
/// The synthetic child is `Color(0xFFF2C14E)`.
int goldPixelCount(Uint8List rgba) {
  var count = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i] > 180 && rgba[i + 1] > 120 && rgba[i + 2] < 140) count++;
  }
  return count;
}

/// Counts near-white pixels in packed RGBA bytes.
int whitePixelCount(Uint8List rgba) {
  var count = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i] > 220 && rgba[i + 1] > 220 && rgba[i + 2] > 220) count++;
  }
  return count;
}

Captions? _captionsFor(CaptureCaptionKind kind) => switch (kind) {
  CaptureCaptionKind.none => null,
  CaptureCaptionKind.inline => Captions.words(
    const [CaptionWord('A', at: Time.zero)],
    style: const CaptionStyle.subtitle(),
    position: const CaptionPosition.center(),
  ),
  CaptureCaptionKind.srt => const Captions.fromSrt(
    'assets/synthetic-a.srt',
    style: CaptionStyle.subtitle(),
    position: CaptionPosition.center(),
  ),
  CaptureCaptionKind.vtt => const Captions.fromVtt(
    'assets/synthetic-a.vtt',
    style: CaptionStyle.subtitle(),
    position: CaptionPosition.center(),
  ),
};
