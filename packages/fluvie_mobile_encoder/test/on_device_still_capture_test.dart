import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluvie/fluvie.dart';
import 'package:fluvie/rendering.dart';
import 'package:fluvie_mobile_encoder/fluvie_mobile_encoder.dart';

class _TesterCaptureHost implements CaptureHost {
  _TesterCaptureHost(this.tester, this.size);

  final WidgetTester tester;
  final Size size;
  bool disposed = false;

  @override
  Future<void> mount(Widget tree) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0;
    await tester.pumpWidget(tree);
  }

  @override
  Future<void> pumpFrame() => tester.pump();

  @override
  Future<void> dispose() async {
    disposed = true;
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  }
}

class _ThrowingDisposeHost extends _TesterCaptureHost {
  _ThrowingDisposeHost(super.tester, super.size);

  @override
  Future<void> dispose() async {
    await super.dispose();
    throw StateError('still dispose boom');
  }
}

class _TrackingResolver implements MediaResolver, DisposableResolver {
  bool disposed = false;

  @override
  void dispose() => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  testWidgets('captures a frame and PNG without invoking the video encoder or sandbox', (
    tester,
  ) async {
    final encoder = FakeMobileVideoEncoder();
    var sandboxCalls = 0;
    late _TesterCaptureHost host;
    final renderer = OnDeviceVideoRenderer(
      encoder: encoder,
      hostFactory: (size) => host = _TesterCaptureHost(tester, size),
      sandboxFactory: () async {
        sandboxCalls++;
        return Directory.systemTemp;
      },
    );
    const composition = Center(
      child: SizedBox(width: 16, height: 16, child: ColoredBox(color: Color(0xFF33AA55))),
    );

    final raw = await tester.runAsync(
      () => renderer.captureFrame(
        composition: composition,
        aspect: Aspect.square,
        at: const Duration(milliseconds: 500),
        longEdge: 48,
      ),
    );
    final png = await tester.runAsync(
      () => renderer.capturePng(
        composition: composition,
        aspect: Aspect.square,
        frame: 15,
        longEdge: 48,
      ),
    );

    expect(raw!.frameIndex, 15);
    expect(raw.width, 48);
    expect(raw.height, 48);
    expect(raw.rgba[3], 0);
    expect(png!.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(host.disposed, isTrue);
    expect(encoder.requests, isEmpty);
    expect(sandboxCalls, 0);
  });

  testWidgets('a metrics report leaves the still frame unchanged', (tester) async {
    final renderer = OnDeviceVideoRenderer(
      encoder: FakeMobileVideoEncoder(),
      hostFactory: (size) => _TesterCaptureHost(tester, size),
      sandboxFactory: () async => Directory.systemTemp,
    );
    const composition = ColoredBox(color: Color(0xFF112233));
    final report = RenderMetrics();

    final timed = await tester.runAsync(
      () => renderer.captureFrame(
        composition: composition,
        aspect: Aspect.square,
        frame: 0,
        longEdge: 16,
        metrics: report,
      ),
    );
    final plain = await tester.runAsync(
      () => renderer.captureFrame(
        composition: composition,
        aspect: Aspect.square,
        frame: 0,
        longEdge: 16,
      ),
    );

    expect(timed!.rgba, plain!.rgba);
    expect(report.frameCount, 1);
    expect(report.preparation.samples, 2);
    expect(report.mounting.samples, 1);
    expect(report.pumping.samples, 1);
    expect(report.readback.samples, 1);
    expect(report.encoding.samples, 0);
    expect(report.cacheHits, 0);
    expect(report.cacheMisses, 0);
  });

  testWidgets('never disposes a caller-injected resolver and surfaces dispose warnings', (
    tester,
  ) async {
    final warnings = <String>[];
    final resolver = _TrackingResolver();
    final renderer = OnDeviceVideoRenderer(
      encoder: FakeMobileVideoEncoder(),
      hostFactory: (size) => _ThrowingDisposeHost(tester, size),
      mediaResolver: resolver,
      onWarning: warnings.add,
    );

    final raw = await tester.runAsync(
      () => renderer.captureFrame(
        composition: const ColoredBox(color: Color(0xFF112233)),
        aspect: Aspect.square,
        longEdge: 32,
      ),
    );

    expect(raw, isNotNull);
    expect(resolver.disposed, isFalse);
    expect(warnings.single, contains('Cleanup after frame capture failed'));
    expect(warnings.single, contains('still dispose boom'));
  });

  test('rejects invalid single-frame arguments before creating a host', () async {
    var hostsCreated = 0;
    final renderer = OnDeviceVideoRenderer(
      encoder: FakeMobileVideoEncoder(),
      hostFactory: (_) {
        hostsCreated++;
        throw StateError('hostFactory must not be called');
      },
    );

    final video24 = Video(
      fps: 24,
      width: 48,
      height: 48,
      scenes: const [
        Scene(duration: Time.seconds(1), children: [SizedBox()]),
      ],
    );
    for (final call in [
      () => renderer.captureFrame(
        composition: const SizedBox(),
        aspect: Aspect.square,
        frame: 1,
        at: Duration.zero,
      ),
      () => renderer.captureFrame(
        composition: const SizedBox(),
        aspect: Aspect.square,
        frame: -1,
      ),
      () => renderer.captureFrame(
        composition: const SizedBox(),
        aspect: Aspect.square,
        at: const Duration(milliseconds: -10),
      ),
      () => renderer.captureFrame(
        composition: const SizedBox(),
        aspect: Aspect.square,
        fps: 0,
      ),
      () => renderer.captureFrame(
        composition: const SizedBox(),
        aspect: Aspect.square,
        longEdge: 0,
      ),
      () => renderer.captureFrame(
        composition: video24,
        aspect: Aspect.square,
        at: const Duration(milliseconds: 500),
        fps: 12,
        longEdge: 48,
      ),
      () => renderer.captureFrame(
        composition: video24,
        aspect: Aspect.square,
        at: const Duration(seconds: 1),
        longEdge: 48,
      ),
      () => renderer.captureFrame(
        composition: Directionality(textDirection: TextDirection.ltr, child: video24),
        aspect: Aspect.square,
        fps: 12,
        longEdge: 48,
      ),
    ]) {
      await expectLater(call(), throwsArgumentError);
    }
    expect(hostsCreated, 0);
  });
}
