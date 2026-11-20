import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' hide Animation, Clip;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluvie/fluvie.dart';
import 'package:fluvie/rendering.dart';
import 'package:mocktail/mocktail.dart';

class _MockResolver extends Mock implements MediaResolver {}

class _StubCapture implements FrameCaptureService {
  @override
  Future<RawFrame> capture({
    required GlobalKey boundaryKey,
    required int frameIndex,
    required int width,
    required int height,
  }) async => RawFrame(
    frameIndex: frameIndex,
    width: width,
    height: height,
    rgba: Uint8List(width * height * 4),
  );
}

/// Stateful widget matching the review reproduction: flips red once it observes
/// frame 3, otherwise stays blue.
class _Frame3Latch extends StatefulWidget {
  const _Frame3Latch();

  @override
  State<_Frame3Latch> createState() => _Frame3LatchState();
}

class _Frame3LatchState extends State<_Frame3Latch> {
  bool _sawFrame3 = false;

  @override
  Widget build(BuildContext context) {
    final frame = FrameProvider.of(context).frame;
    if (frame == 3) _sawFrame3 = true;
    return SizedBox.expand(
      child: ColoredBox(color: _sawFrame3 ? const Color(0xFFD62828) : const Color(0xFF1D4ED8)),
    );
  }
}

void _configureView(WidgetTester tester, Size size) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });
}

void main() {
  test('only prepares clip frames read at mount and during still capture', () async {
    const source = MediaSource.asset('clip.mp4');
    final video = Video(
      fps: 24,
      transition: const Transition.crossFade(Time.frames(12)),
      scenes: [
        const Scene(duration: Time.frames(24), children: [SizedBox()]),
        Scene(
          duration: const Time.frames(96),
          children: [
            Clip.asset('clip.mp4', trim: const Time.frames(3).to(const Time.frames(60))).animate(
              const [],
              window: const Time.frames(2).to(const Time.frames(72)),
            ),
          ],
        ),
      ],
    );
    final resolver = _MockResolver();
    final requested = <int>[];
    when(() => resolver.preResolveAll({source})).thenAnswer((_) async {});
    when(() => resolver.probeClip(source)).thenAnswer(
      (_) async => (fps: 24.0, frameCount: 96, width: 32, height: 32, hasAudio: false),
    );
    when(() => resolver.preResolveClip(source, any())).thenAnswer((invocation) async {
      requested.addAll(invocation.positionalArguments[1] as Iterable<int>);
    });

    Future<void> capture(int frame, {bool stepThrough = false}) => captureFrame(
      composition: video,
      aspect: Aspect.square,
      longEdge: 32,
      frame: frame,
      stepThrough: stepThrough,
      resolver: resolver,
      capture: _StubCapture(),
      pumpWidget: (_) async {},
      pumpFrame: () async {},
    );

    await capture(0);
    expect(requested, [3]);
    requested.clear();
    await capture(18);
    expect(requested, [3, 7]);
    requested.clear();
    await capture(18, stepThrough: true);
    expect(requested, [3, 4, 5, 6, 7]);
  });

  test('large positive instants preserve the frame index or fail on overflow', () {
    const instant = Duration(microseconds: 1 << 61);
    expect(frameIndexFor(instant), 69175290276410);
    expect(() => frameIndexFor(instant, fps: 1 << 62), throwsRangeError);
  });

  test('rejects an explicit fps that disagrees with Video.fps before mounting', () async {
    var mounted = false;
    final video = Video(
      fps: 24,
      width: 32,
      height: 32,
      scenes: const [
        Scene(duration: Time.seconds(1), children: [SizedBox()]),
      ],
    );
    await expectLater(
      captureFrame(
        composition: Directionality(textDirection: TextDirection.ltr, child: video),
        aspect: Aspect.square,
        at: const Duration(milliseconds: 500),
        fps: 12,
        longEdge: 32,
        pumpWidget: (_) async => mounted = true,
        pumpFrame: () async {},
      ),
      throwsArgumentError,
    );
    expect(mounted, isFalse);
  });

  testWidgets('maps 999ms on a 1s 30fps Video to frame 29 and rejects out-of-range instants', (
    tester,
  ) async {
    _configureView(tester, const Size(32, 32));
    final video = Video(
      width: 32,
      height: 32,
      scenes: [
        Scene(
          duration: const Time.seconds(1),
          background: Background.color(const Color(0xFF2A9D8F)),
          children: const [SizedBox.expand()],
        ),
      ],
    );
    final wrapped = Directionality(textDirection: TextDirection.ltr, child: video);

    final last = (await tester.runAsync(
      () => captureFrame(
        composition: wrapped,
        aspect: Aspect.square,
        at: const Duration(milliseconds: 999),
        pumpWidget: tester.pumpWidget,
        pumpFrame: tester.pump,
        longEdge: 32,
      ),
    ))!;

    expect(last.frameIndex, 29);
    expect(last.rgba[0], 0x2A);
    expect(last.rgba[1], 0x9D);
    expect(last.rgba[2], 0x8F);
    expect(last.rgba[3], 255);

    var mounted = false;
    for (final call in [
      () => captureFrame(
        composition: wrapped,
        aspect: Aspect.square,
        at: const Duration(seconds: 1),
        pumpWidget: (_) async => mounted = true,
        pumpFrame: () async {},
        longEdge: 32,
      ),
      () => captureFrame(
        composition: wrapped,
        aspect: Aspect.square,
        frame: 30,
        pumpWidget: (_) async => mounted = true,
        pumpFrame: () async {},
        longEdge: 32,
      ),
    ]) {
      await expectLater(call(), throwsRangeError);
    }
    expect(mounted, isFalse);
  });

  testWidgets(
    'stepThrough preserves sequential parity for stateful widgets while direct seek jumps',
    (
      tester,
    ) async {
      _configureView(tester, const Size(32, 32));
      final video = Video(
        width: 32,
        height: 32,
        scenes: const [
          Scene(duration: Time.seconds(1), children: [_Frame3Latch()]),
        ],
      );
      final wrapped = Directionality(textDirection: TextDirection.ltr, child: video);
      final sandbox = MemoryRenderSandbox();
      final full = (await tester.runAsync(
        () => renderToSandbox(
          composition: wrapped,
          aspect: Aspect.square,
          frameCount: 9,
          sandbox: sandbox,
          capture: const RepaintBoundaryCaptureService(),
          pumpWidget: tester.pumpWidget,
          pumpFrame: tester.pump,
          longEdge: 32,
        ),
      ))!;
      final all = await sandbox.readBytes(full.framesFileName);
      const frameBytes = 32 * 32 * 4;
      final sequentialFrame8 = all.sublist(8 * frameBytes, 9 * frameBytes);

      final stepped = (await tester.runAsync(
        () => captureFrame(
          composition: wrapped,
          aspect: Aspect.square,
          frame: 8,
          stepThrough: true,
          pumpWidget: tester.pumpWidget,
          pumpFrame: tester.pump,
          longEdge: 32,
        ),
      ))!;
      final direct = (await tester.runAsync(
        () => captureFrame(
          composition: wrapped,
          aspect: Aspect.square,
          frame: 8,
          pumpWidget: tester.pumpWidget,
          pumpFrame: tester.pump,
          longEdge: 32,
        ),
      ))!;

      expect(stepped.rgba, sequentialFrame8);
      expect(stepped.rgba[0], 0xD6, reason: 'stepThrough visited frame 3 and turned red');
      expect(direct.rgba[2], 0xD8, reason: 'direct seek jumped over frame 3 and stayed blue');
    },
  );

  test('encodeRawFramePng rejects non-positive dimensions without hanging', () async {
    final zeroWidth = RawFrame(frameIndex: 0, width: 0, height: 1, rgba: Uint8List(0));
    final zeroHeight = RawFrame(frameIndex: 0, width: 1, height: 0, rgba: Uint8List(0));
    await expectLater(encodeRawFramePng(zeroWidth), throwsArgumentError);
    await expectLater(encodeRawFramePng(zeroHeight), throwsArgumentError);
  });

  test('encodeRawFramePng rejects dimensions whose pixel count overflows', () async {
    final frame = RawFrame(frameIndex: 0, width: 1 << 62, height: 1, rgba: Uint8List(0));
    final result = Completer<Object>();
    final uncaught = <Object>[];
    await runZonedGuarded(
      () async {
        try {
          result.complete(await encodeRawFramePng(frame).timeout(const Duration(seconds: 1)));
        } on Object catch (error) {
          result.complete(error);
        }
      },
      (error, _) => uncaught.add(error),
    );
    expect(await result.future, isArgumentError);
    expect(uncaught, isEmpty);
  });
}
