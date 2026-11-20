import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluvie/fluvie.dart';
import 'package:fluvie/rendering.dart';
import 'package:fluvie/src/rendering/encoding/audio_graph_nodes.dart';
import 'package:fluvie/src/rendering/frame_capture_loop.dart';
import 'package:mocktail/mocktail.dart';

class _MockFfmpegRunner extends Mock implements FfmpegRunner {}

void main() {
  test('stage timing ranks an empty list, one sample, and the 95th percentile', () {
    expect(StageTiming.fromMicroseconds(const []), StageTiming.empty);
    final only = StageTiming.fromMicroseconds(const [7]);
    expect(only.samples, 1);
    expect(only.minimum, const Duration(microseconds: 7));
    expect(only.mean, const Duration(microseconds: 7));
    expect(only.p95, const Duration(microseconds: 7));
    expect(only.maximum, const Duration(microseconds: 7));

    final pair = StageTiming.fromMicroseconds(const [2, 1]);
    expect(pair.minimum, const Duration(microseconds: 1));
    expect(pair.mean, const Duration(microseconds: 1));
    expect(pair.p95, const Duration(microseconds: 2));
    expect(pair.maximum, const Duration(microseconds: 2));

    final twenty = StageTiming.fromMicroseconds([for (var i = 1; i <= 20; i++) i]);
    expect(twenty.p95, const Duration(microseconds: 19));
    expect(twenty.mean, const Duration(microseconds: 10));
  });

  testWidgets('captureFrame keeps the same pixels when metrics are recorded', (tester) async {
    tester.view
      ..physicalSize = const ui.Size(16, 16)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const composition = ColoredBox(color: Color(0xFF112233));

    Future<RawFrame> shoot({RenderMetrics? metrics, int frame = 0, bool stepThrough = false}) {
      return captureFrame(
        composition: composition,
        aspect: Aspect.square,
        frame: frame,
        longEdge: 16,
        stepThrough: stepThrough,
        pumpWidget: tester.pumpWidget,
        pumpFrame: tester.pump,
        metrics: metrics,
      );
    }

    final report = RenderMetrics();
    final timed = (await tester.runAsync(() => shoot(metrics: report)))!;
    final plain = (await tester.runAsync(shoot))!;
    expect(timed.rgba, plain.rgba);
    expect(timed.rgba[0], 0x11);
    expect(timed.rgba[1], 0x22);
    expect(timed.rgba[2], 0x33);
    expect(timed.rgba[3], 0xFF);
    expect(report.frameCount, 1);
    expect(report.preparation.samples, 2);
    expect(report.mounting.samples, 1);
    expect(report.pumping.samples, 1);
    expect(report.readback.samples, 1);
    expect(report.encoding.samples, 0);
    expect(report.cacheHits, 0);
    expect(report.cacheMisses, 0);

    final stepped = RenderMetrics();
    final steppedFrame = (await tester.runAsync(
      () => shoot(metrics: stepped, frame: 2, stepThrough: true),
    ))!;
    final steppedPlain = (await tester.runAsync(() => shoot(frame: 2, stepThrough: true)))!;
    expect(steppedFrame.rgba, steppedPlain.rgba);
    expect(stepped.frameCount, 1);
    expect(stepped.pumping.samples, 3);
    expect(stepped.readback.samples, 1);
  });

  testWidgets('the capture loop counts cache hits without changing pixels', (tester) async {
    tester.view
      ..physicalSize = const ui.Size(16, 16)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = RenderController();
    addTearDown(controller.dispose);
    final boundaryKey = GlobalKey();
    Future<void> mount(Color color) => tester.pumpWidget(
      RenderControllerScope(
        controller: controller,
        child: RepaintBoundary(
          key: boundaryKey,
          child: ColoredBox(color: color),
        ),
      ),
    );
    await mount(const Color(0xFF112233));
    final config = RenderConfig(width: 16, height: 16, frameCount: 2);
    final cache = FrameCache(_tempDir('metrics-cache'));
    final store = FrameCacheStore(cache);

    Future<List<int>> render(RenderMetrics? metrics, String digest) async {
      final sandbox = MemoryRenderSandbox();
      final sink = sandbox.openFrames('frames.rgba');
      try {
        await runFrameCaptureLoop(
          config: config,
          digest: digest,
          pump: (frame) async {
            controller.seek(frame);
            await tester.pump();
          },
          boundaryKey: boundaryKey,
          capture: const RepaintBoundaryCaptureService(),
          store: store,
          sink: sink,
          metrics: metrics,
        );
      } finally {
        await sink.close();
      }
      return sandbox.readBytes('frames.rgba');
    }

    final cold = RenderMetrics();
    final coldBytes = (await tester.runAsync(() => render(cold, 'scene')))!;
    final plain = (await tester.runAsync(() => render(null, 'plain')))!;
    await mount(const Color(0xFFABCDEF));
    final warm = RenderMetrics();
    final warmBytes = (await tester.runAsync(() => render(warm, 'scene')))!;

    expect(coldBytes.sublist(0, 4), [0x11, 0x22, 0x33, 0xFF]);
    expect(cold.frameCount, 2);
    expect(cold.cacheHits, 0);
    expect(cold.cacheMisses, 2);
    expect(cold.pumping.samples, 2);
    expect(cold.readback.samples, 2);
    expect(plain, coldBytes);
    expect(warm.frameCount, 2);
    expect(warm.cacheHits, 2);
    expect(warm.cacheMisses, 0);
    expect(warm.pumping.samples, 2);
    expect(warm.readback.samples, 0);
    expect(warmBytes, coldBytes);

    final planted = FrameCache(_tempDir('metrics-short'));
    final miss = RenderMetrics();
    final recovered = (await tester.runAsync(() async {
      // Real file IO only completes inside runAsync. Awaiting it from the
      // test body blocks the fake-async zone forever.
      await planted.store(planted.frameKey('short', 0), Uint8List(1));
      final sandbox = MemoryRenderSandbox();
      final sink = sandbox.openFrames('frames.rgba');
      try {
        await runFrameCaptureLoop(
          config: RenderConfig(width: 16, height: 16, frameCount: 1),
          digest: 'short',
          pump: (frame) async {
            controller.seek(frame);
            await tester.pump();
          },
          boundaryKey: boundaryKey,
          capture: const RepaintBoundaryCaptureService(),
          store: FrameCacheStore(planted),
          sink: sink,
          metrics: miss,
        );
      } finally {
        await sink.close();
      }
      return sandbox.readBytes('frames.rgba');
    }))!;
    expect(miss.cacheHits, 0);
    expect(miss.cacheMisses, 1);
    expect(miss.readback.samples, 1);
    expect(recovered, hasLength(16 * 16 * 4));
  });

  testWidgets('encoding metrics count each encoder call and keep the frames', (tester) async {
    setUpFallback();
    tester.view
      ..physicalSize = const ui.Size(16, 16)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: const ColoredBox(color: Color(0xFF010203)),
      ),
    );
    Future<void> pump(int frame) => tester.pump();
    final config = RenderConfig(width: 16, height: 16, frameCount: 2, cacheEnabled: false);

    var staged = 0;
    Future<Directory> render(RenderMetrics? metrics, {int? posterFrame}) async {
      final outDir = _tempDir('metrics-encode');
      final runner = _MockFfmpegRunner();
      when(
        () => runner.encode(
          args: any(named: 'args'),
          sandbox: any(named: 'sandbox'),
        ),
      ).thenAnswer((_) async {});
      await RenderService(capture: const RepaintBoundaryCaptureService()).render(
        config: config,
        outDir: outDir,
        pump: pump,
        boundaryKey: boundaryKey,
        compositionKey: 'metrics',
        runner: runner,
        posterFrame: posterFrame,
        stageAudio: ({required resolver, required sandbox}) async {
          staged += 1;
          return (nodes: const <FfmpegAudioNode>[], amix: null);
        },
        metrics: metrics,
      );
      return outDir;
    }

    final report = RenderMetrics();
    final timedDir = (await tester.runAsync(() => render(report)))!;
    final plainDir = (await tester.runAsync(() => render(null)))!;
    expect(report.preparation.samples, 1);
    expect(staged, 2);
    expect(report.encoding.samples, 1);
    expect(report.frameCount, 2);
    expect(report.readback.samples, 2);
    expect(
      File('${timedDir.path}/frames.rgba').readAsBytesSync(),
      File('${plainDir.path}/frames.rgba').readAsBytesSync(),
    );

    final poster = RenderMetrics();
    await tester.runAsync(() => render(poster, posterFrame: 1));
    expect(poster.preparation.samples, 1);
    expect(poster.encoding.samples, 2);
    expect(staged, 3);
  });

  testWidgets('sandbox PNG encoding is one sample per frame', (tester) async {
    tester.view
      ..physicalSize = const ui.Size(16, 16)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var encodes = 0;

    Future<MemoryRenderSandbox> shoot(RenderMetrics? metrics, {FrameEncoder? encode}) {
      final sandbox = MemoryRenderSandbox();
      return renderToSandbox(
        composition: const ColoredBox(color: Color(0xFF112233)),
        aspect: Aspect.square,
        frameCount: 2,
        longEdge: 16,
        sandbox: sandbox,
        capture: const RepaintBoundaryCaptureService(),
        pumpWidget: tester.pumpWidget,
        pumpFrame: tester.pump,
        frameEncoder: encode,
        metrics: metrics,
      ).then((_) => sandbox);
    }

    Future<Uint8List> encodePng(Uint8List rgba, int width, int height) async {
      encodes += 1;
      return Uint8List.fromList([width, height, rgba[0], rgba[3]]);
    }

    final report = RenderMetrics();
    final timed = (await tester.runAsync(() => shoot(report, encode: encodePng)))!;
    final plain = (await tester.runAsync(() => shoot(null, encode: encodePng)))!;
    expect(encodes, 4);
    expect(report.encoding.samples, 2);
    expect(report.frameCount, 2);
    expect(report.preparation.samples, 1);
    expect(report.readback.samples, 2);
    expect(report.cacheHits, 0);
    expect(report.cacheMisses, 0);
    expect(await timed.readBytes('frame_000000.png'), await plain.readBytes('frame_000000.png'));
    expect(await timed.readBytes('frame_000001.png'), await plain.readBytes('frame_000001.png'));

    final raw = RenderMetrics();
    await tester.runAsync(() => shoot(raw));
    expect(raw.encoding.samples, 0);
    expect(raw.frameCount, 2);
  });
}

Directory _tempDir(String label) {
  final dir = Directory.systemTemp.createTempSync('fluvie_metrics_${label}_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

void setUpFallback() {
  registerFallbackValue(<String>[]);
  registerFallbackValue(Directory('/tmp'));
}
