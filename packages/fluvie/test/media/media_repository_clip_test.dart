// WI-15 (D7/D8): the MediaRepository clip path. preResolveClip probes the
// source (via a fake VideoProbeService) and extracts the listed source frames
// (via a fake FrameExtractionService), decoding each RawFrame to a cached
// ui.Image; clipMetadataFor and decodedClipFrame serve them synchronously and
// enforce the pass ordering. A real video file is never touched here.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Size, SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluvie/fluvie.dart' show Aspect, Clip, Scene, Time, Transition, Video;
import 'package:fluvie/rendering.dart'
    show MemoryRenderSandbox, RepaintBoundaryCaptureService, renderToSandbox;
import 'package:fluvie/src/core/errors/fluvie_render_exception.dart';
import 'package:fluvie/src/core/media/media_source.dart';
import 'package:fluvie/src/media/media_bytes_loader.dart';
import 'package:fluvie/src/media/media_repository.dart';
import 'package:fluvie/src/media/net/media_http_client.dart';
import 'package:fluvie/src/media/net/network_allowlist.dart';
import 'package:fluvie/src/media/runtime/clip_resolve_cache.dart';
import 'package:fluvie/src/rendering/capture/raw_frame.dart';
import 'package:fluvie/src/rendering/encoding/frame_extraction_service.dart';
import 'package:fluvie/src/rendering/encoding/video_probe_service.dart';
import 'package:fluvie/src/rendering/pre_resolve_clips.dart';
import 'package:fluvie/src/rendering/render_frame.dart';

class _MapBundle extends CachingAssetBundle {
  _MapBundle(this._data);
  final Map<String, Uint8List> _data;
  @override
  Future<ByteData> load(String key) async {
    final bytes = _data[key];
    if (bytes == null) throw FluvieRenderException('asset not found: $key');
    return ByteData.view(bytes.buffer);
  }
}

class _MemoryClipStore implements ClipFrameStore {
  final _frames = <(String, int), Uint8List>{};

  @override
  Future<void> put(String clipKey, int frame, Uint8List rgba) async =>
      _frames[(clipKey, frame)] = rgba;

  @override
  Future<Uint8List?> get(String clipKey, int frame) async => _frames[(clipKey, frame)];

  @override
  Future<void> dispose() async => _frames.clear();
}

class _NoHttp implements MediaHttpClient {
  @override
  Future<Uint8List> get(Uri url) async => throw FluvieRenderException('no network: $url');
}

/// A probe that ignores the path and returns canned facts; counts calls.
class _FakeProbe implements VideoProbeService {
  _FakeProbe(this.result);
  final VideoProbeResult result;
  int calls = 0;
  @override
  Future<VideoProbeResult> probe(String filePath) async {
    calls++;
    return result;
  }
}

/// An extractor that serves canned 2x2 frames per index; counts calls and
/// records the decoder each extraction was asked for.
class _FakeExtractor implements FrameExtractionService {
  int calls = 0;
  final extracted = <int>[];
  final decoders = <String?>[];
  @override
  Future<RawFrame> extractFrame(
    Uri source,
    int frameIndex, {
    required int width,
    required int height,
    String? decoder,
  }) async {
    calls++;
    extracted.add(frameIndex);
    decoders.add(decoder);
    return RawFrame(
      frameIndex: frameIndex,
      width: width,
      height: height,
      rgba: Uint8List(width * height * 4)..fillRange(0, width * height * 4, frameIndex % 256),
    );
  }

  @override
  Future<Map<int, RawFrame>> extractFrames(
    Uri source,
    Iterable<int> frameIndices, {
    required int width,
    required int height,
    String? decoder,
  }) async => {
    for (final index in frameIndices)
      index: await extractFrame(source, index, width: width, height: height, decoder: decoder),
  };
}

MediaRepository _repo({
  required Map<String, Uint8List> assets,
  required VideoProbeService probe,
  required FrameExtractionService extractor,
  ClipFrameStore? clipFrameStore,
}) => MediaRepository(
  loader: MediaBytesLoader(
    bundle: _MapBundle(assets),
    httpClient: _NoHttp(),
    allowlist: NetworkAllowlist.allowAny(),
  ),
  probeService: probe,
  frameExtractor: extractor,
  clipFrameStore: clipFrameStore,
);

const _clip = MediaSource.asset('clip_1s.mp4');
const _probeResult = VideoProbeResult(
  codec: 'h264',
  width: 2,
  height: 2,
  nbFrames: 30,
  durationSeconds: 1,
);

void main() {
  testWidgets('a still warms the held outgoing clip frame in a non-overlap blend', (tester) async {
    tester.view
      ..physicalSize = const Size(16, 16)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final extractor = _FakeExtractor();
    final repo = _repo(
      assets: {'clip_1s.mp4': Uint8List(16)},
      probe: _FakeProbe(_probeResult),
      extractor: extractor,
      clipFrameStore: _MemoryClipStore(),
    );
    addTearDown(repo.dispose);
    final video = Video(
      transition: const Transition.crossFade(Time.frames(4), overlap: false),
      scenes: [
        Scene(duration: const Time.frames(10), children: [Clip.asset('clip_1s.mp4')]),
        const Scene(duration: Time.frames(10), children: [SizedBox()]),
      ],
    );

    Future<RawFrame> shoot({bool stepThrough = false}) => captureFrame(
      composition: video,
      aspect: Aspect.square,
      frame: 12,
      longEdge: 16,
      resolver: repo,
      pumpWidget: tester.pumpWidget,
      pumpFrame: tester.pump,
      stepThrough: stepThrough,
    );

    final direct = (await tester.runAsync(shoot))!;
    expect(extractor.extracted, [0, 9]);
    final sequential = (await tester.runAsync(() => shoot(stepThrough: true)))!;
    expect(direct.rgba, sequential.rgba);
  });

  test('streaming warms distinct placements and keeps them across a source refresh', () async {
    final store = _MemoryClipStore();
    final extractor = _FakeExtractor();
    final repo = _repo(
      assets: {'clip_1s.mp4': Uint8List(16)},
      probe: _FakeProbe(_probeResult),
      extractor: extractor,
      clipFrameStore: store,
    );
    addTearDown(repo.dispose);
    await repo.preResolveAll([_clip]);
    for (final trim in [0, 10]) {
      repo.registerClipPlan(
        source: _clip,
        windowStart: 0,
        windowLength: 30,
        compFps: 30,
        trimStartFrames: trim,
        trimEndFrames: 30,
      );
    }
    await repo.preResolveClip(_clip, [0, 1, 10, 11]);
    await repo.prepareClipFrames(0);
    expect(repo.decodedClipFrame(_clip, 0).width, 2);
    expect(repo.decodedClipFrame(_clip, 10).width, 2);

    await repo.preResolveAll(const []);
    await repo.prepareClipFrames(1);
    expect(repo.decodedClipFrame(_clip, 1).width, 2);
    expect(repo.decodedClipFrame(_clip, 11).width, 2);

    await expectLater(repo.prepareClipFrames(2), throwsA(isA<FluvieRenderException>()));
    await preResolveCompositionClips(composition: const SizedBox(), resolver: repo, totalFrames: 1);
    await repo.prepareClipFrames(2);
    await repo.preResolveClip(_clip, [0, 1, 10, 11]);
    expect(extractor.extracted, [0, 1, 10, 11]);
  });

  test('preResolveClip probes once and extracts the listed frames', () async {
    final probe = _FakeProbe(_probeResult);
    final extractor = _FakeExtractor();
    final repo = _repo(assets: {'clip_1s.mp4': Uint8List(16)}, probe: probe, extractor: extractor);

    await repo.preResolveClip(_clip, [0, 10, 20]);

    expect(probe.calls, 1);
    expect(extractor.extracted, [0, 10, 20]);
  });

  test('clipMetadataFor returns the probed fps and frame count', () async {
    final repo = _repo(
      assets: {'clip_1s.mp4': Uint8List(16)},
      probe: _FakeProbe(_probeResult),
      extractor: _FakeExtractor(),
    );

    await repo.preResolveClip(_clip, [0]);
    final meta = repo.clipMetadataFor(_clip);

    expect(meta.fps, 30);
    expect(meta.frameCount, 30);
    expect(meta.width, 2);
    expect(meta.height, 2);
  });

  test('decodedClipFrame returns a sync ui.Image per source frame', () async {
    final repo = _repo(
      assets: {'clip_1s.mp4': Uint8List(16)},
      probe: _FakeProbe(_probeResult),
      extractor: _FakeExtractor(),
    );

    await repo.preResolveClip(_clip, [0, 5]);

    expect(repo.decodedClipFrame(_clip, 0).width, 2);
    expect(repo.decodedClipFrame(_clip, 5).height, 2);
  });

  test('preResolveClip is idempotent: a re-extracted frame is skipped', () async {
    final extractor = _FakeExtractor();
    final repo = _repo(
      assets: {'clip_1s.mp4': Uint8List(16)},
      probe: _FakeProbe(_probeResult),
      extractor: extractor,
    );

    await repo.preResolveClip(_clip, [0, 5]);
    await repo.preResolveClip(_clip, [5, 10]);

    expect(extractor.extracted, [0, 5, 10], reason: 'frame 5 must not re-extract');
  });

  test('clipMetadataFor before preResolveClip throws StateError', () {
    final repo = _repo(
      assets: const {},
      probe: _FakeProbe(_probeResult),
      extractor: _FakeExtractor(),
    );
    expect(() => repo.clipMetadataFor(_clip), throwsA(isA<StateError>()));
  });

  test('decodedClipFrame of an un-extracted frame throws a typed error', () async {
    final repo = _repo(
      assets: {'clip_1s.mp4': Uint8List(16)},
      probe: _FakeProbe(_probeResult),
      extractor: _FakeExtractor(),
    );

    await repo.preResolveClip(_clip, [0]);

    expect(
      () => repo.decodedClipFrame(_clip, 99),
      throwsA(isA<FluvieRenderException>().having((e) => e.message, 'message', contains('99'))),
    );
  });

  test('a clip missing the extraction services throws a clear error', () async {
    final repo = MediaRepository(
      loader: MediaBytesLoader(
        bundle: _MapBundle({'clip_1s.mp4': Uint8List(16)}),
        httpClient: _NoHttp(),
        allowlist: NetworkAllowlist.allowAny(),
      ),
    );

    await expectLater(() => repo.preResolveClip(_clip, [0]), throwsA(isA<FluvieRenderException>()));
  });

  test('probeClip returns metadata and probes once (cached)', () async {
    final probe = _FakeProbe(_probeResult);
    final repo = _repo(
      assets: {'clip_1s.mp4': Uint8List(16)},
      probe: probe,
      extractor: _FakeExtractor(),
    );

    final meta = await repo.probeClip(_clip);
    final again = await repo.probeClip(_clip);

    expect(meta.frameCount, 30);
    expect(meta.width, 2);
    expect(again, meta);
    expect(probe.calls, 1, reason: 'metadata is cached after the first probe');
  });

  test('probeClip without a VideoProbeService throws a clear error', () async {
    final repo = MediaRepository(
      loader: MediaBytesLoader(
        bundle: _MapBundle({'clip_1s.mp4': Uint8List(16)}),
        httpClient: _NoHttp(),
        allowlist: NetworkAllowlist.allowAny(),
      ),
      frameExtractor: _FakeExtractor(),
    );

    await expectLater(() => repo.probeClip(_clip), throwsA(isA<FluvieRenderException>()));
  });

  // The clip's fps drives the resampler (which source frame each composition
  // frame paints), so the metadata must carry the probe's rate verbatim.
  group('the clip fps follows the probe', () {
    Future<double> fpsFor(VideoProbeResult probed) async {
      final repo = _repo(
        assets: {'clip_1s.mp4': Uint8List(16)},
        probe: _FakeProbe(probed),
        extractor: _FakeExtractor(),
      );
      final meta = await repo.probeClip(_clip);
      return meta.fps;
    }

    test('a declared rate beats the rate derived from the duration', () async {
      // A webm's container duration spans its audio tail: 106 frames over
      // 3.55s derives 29.86 for a clip that declares, and really runs at, 30.
      expect(
        await fpsFor(
          const VideoProbeResult(
            codec: 'vp9',
            width: 2,
            height: 2,
            nbFrames: 106,
            durationSeconds: 3.55,
            declaredFps: 30,
          ),
        ),
        30,
      );
    });

    test('an NTSC declared rate reaches the metadata unrounded', () async {
      expect(
        await fpsFor(
          const VideoProbeResult(
            codec: 'h264',
            width: 2,
            height: 2,
            nbFrames: 300,
            durationSeconds: 10.01,
            declaredFps: 30000 / 1001,
          ),
        ),
        closeTo(29.97002997, 1e-6),
      );
    });

    test('a probe with no declared rate still derives frames over duration', () async {
      expect(await fpsFor(_probeResult), 30, reason: '30 frames over 1s');
    });
  });

  // VP9 codes alpha as a separate layer that only libvpx-vp9 reads; the native
  // vp9 decoder drops it (a transparent clip renders over black) but is far
  // faster, so it stays the choice for everything else.
  group('the extraction decoder follows the probe', () {
    Future<List<String?>> decodersFor(VideoProbeResult probed) async {
      final extractor = _FakeExtractor();
      final repo = _repo(
        assets: {'clip_1s.mp4': Uint8List(16)},
        probe: _FakeProbe(probed),
        extractor: extractor,
      );
      await repo.preResolveClip(_clip, [0]);
      return extractor.decoders;
    }

    test('a vp9 source with alpha extracts with libvpx-vp9', () async {
      expect(
        await decodersFor(
          const VideoProbeResult(
            codec: 'vp9',
            width: 2,
            height: 2,
            nbFrames: 30,
            durationSeconds: 1,
            hasAlpha: true,
          ),
        ),
        ['libvpx-vp9'],
      );
    });

    test('a vp9 source without alpha keeps the default decoder', () async {
      expect(
        await decodersFor(
          const VideoProbeResult(
            codec: 'vp9',
            width: 2,
            height: 2,
            nbFrames: 30,
            durationSeconds: 1,
          ),
        ),
        [null],
        reason: 'the native vp9 decoder is much faster and loses nothing here',
      );
    });

    test('an h264 source keeps the default decoder', () async {
      expect(await decodersFor(_probeResult), [null]);
    });
  });

  test('dispose releases extracted clip frames and is idempotent', () async {
    final repo = _repo(
      assets: {'clip_1s.mp4': Uint8List(16)},
      probe: _FakeProbe(_probeResult),
      extractor: _FakeExtractor(),
    );
    await repo.preResolveClip(_clip, [0]);
    final frame = repo.decodedClipFrame(_clip, 0);

    repo.dispose();

    expect(frame.debugDisposed, isTrue);
    expect(repo.dispose, returnsNormally, reason: 'a second dispose is a no-op');
  });

  testWidgets('sandbox warms streaming clip frames before mounting and pumping', (tester) async {
    final extractor = _FakeExtractor();
    final repo = _repo(
      assets: {'clip_1s.mp4': Uint8List(16)},
      probe: _FakeProbe(_probeResult),
      extractor: extractor,
      clipFrameStore: _MemoryClipStore(),
    );
    addTearDown(repo.dispose);
    tester.view
      ..physicalSize = const Size(16, 16)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sandbox = MemoryRenderSandbox();
    final manifest = await tester.runAsync(
      () => renderToSandbox(
        composition: Video(
          width: 16,
          height: 16,
          scenes: [
            Scene(duration: const Time.frames(2), children: [Clip.asset('clip_1s.mp4')]),
          ],
        ),
        aspect: Aspect.square,
        frameCount: 2,
        sandbox: sandbox,
        capture: const RepaintBoundaryCaptureService(),
        pumpWidget: tester.pumpWidget,
        pumpFrame: tester.pump,
        longEdge: 16,
        resolver: repo,
      ),
    );

    expect(extractor.extracted, [0, 1]);
    final rgba = await sandbox.readBytes(manifest!.framesFileName);
    expect(rgba, hasLength(2 * 16 * 16 * 4));
  });

  tearDownAll(() {
    // Clean any stray clip materialization temp dirs the repo may have made.
    for (final entry in Directory.systemTemp.listSync()) {
      if (entry is Directory && entry.path.contains('fluvie_clip_src_')) {
        entry.deleteSync(recursive: true);
      }
    }
  });
}
