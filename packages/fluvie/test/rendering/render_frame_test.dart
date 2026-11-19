import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' hide Animation, Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluvie/fluvie.dart';
import 'package:fluvie/rendering.dart';

class _ProgressiveReveal extends StatelessWidget {
  const _ProgressiveReveal();

  @override
  Widget build(BuildContext context) => FrameBuilder(
    (ctx) => Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: ctx.progress.clamp(0.0, 1.0),
        heightFactor: 0.5,
        child: const ColoredBox(color: Color(0xFFE05A47)),
      ),
    ),
  );
}

class _MaterialEnvelope extends StatefulWidget implements CollectibleChildren {
  const _MaterialEnvelope({required this.child});
  final Widget child;
  @override
  Iterable<Widget> get collectibleChildren => [child];
  @override
  State<_MaterialEnvelope> createState() => _MaterialEnvelopeState();
}

class _MaterialEnvelopeState extends State<_MaterialEnvelope> {
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: Color(0xFFF3EADC)),
      widget.child,
      const _ProgressiveReveal(),
    ],
  );
}

int _countRed(Uint8List rgba) {
  var count = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i] > 200 && rgba[i + 1] < 110 && rgba[i + 2] < 100 && rgba[i + 3] == 255) count++;
  }
  return count;
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
  test('frameIndexFor converts durations and rejects invalid inputs', () {
    expect(frameIndexFor(Duration.zero), 0);
    expect(frameIndexFor(const Duration(milliseconds: 500)), 15);
    expect(frameIndexFor(const Duration(milliseconds: 500), fps: 24), 12);
    expect(() => frameIndexFor(Duration.zero, fps: 0), throwsArgumentError);
    expect(() => frameIndexFor(const Duration(milliseconds: -1)), throwsArgumentError);
  });

  testWidgets('captureFrame matches exact frame from full sandbox capture', (tester) async {
    _configureView(tester, const Size(64, 64));
    final sandbox = MemoryRenderSandbox();
    final wrapped = Directionality(
      textDirection: TextDirection.ltr,
      child: Video(
        width: 64,
        height: 64,
        scenes: [
          Scene(
            duration: const Time.seconds(1),
            background: Background.color(const Color(0xFF101010)),
            children: const [_ProgressiveReveal()],
          ),
        ],
      ),
    );
    final full = (await tester.runAsync(
      () => renderToSandbox(
        composition: wrapped,
        aspect: Aspect.square,
        frameCount: 16,
        sandbox: sandbox,
        capture: const RepaintBoundaryCaptureService(),
        pumpWidget: tester.pumpWidget,
        pumpFrame: tester.pump,
        longEdge: 64,
      ),
    ))!;
    final all = await sandbox.readBytes(full.framesFileName);
    const frameBytes = 64 * 64 * 4;
    final single = (await tester.runAsync(
      () => captureFrame(
        composition: wrapped,
        aspect: Aspect.square,
        frame: 10,
        pumpWidget: tester.pumpWidget,
        pumpFrame: tester.pump,
        longEdge: 64,
      ),
    ))!;
    expect(single.frameIndex, 10);
    expect(single.rgba, all.sublist(10 * frameBytes, 11 * frameBytes));
  });

  testWidgets('captureFrame resolves at with Video.fps and renders material reveal', (
    tester,
  ) async {
    _configureView(tester, const Size(64, 64));
    final wrapped = Directionality(
      textDirection: TextDirection.ltr,
      child: Video(
        fps: 24,
        width: 64,
        height: 64,
        scenes: const [
          Scene(
            duration: Time.seconds(1),
            children: [_MaterialEnvelope(child: SizedBox.shrink())],
          ),
        ],
      ),
    );
    Future<RawFrame> atMs(int ms) async => (await tester.runAsync(
      () => captureFrame(
        composition: wrapped,
        aspect: Aspect.square,
        at: Duration(milliseconds: ms),
        pumpWidget: tester.pumpWidget,
        pumpFrame: tester.pump,
        longEdge: 64,
      ),
    ))!;
    final early = await atMs(250);
    final late = await atMs(750);
    expect(early.frameIndex, 6);
    expect(late.frameIndex, 18);
    expect(_countRed(late.rgba), greaterThan(_countRed(early.rgba) * 2));
    expect(await atMs(750), late);
  });

  testWidgets('captureFrame + encodeRawFramePng preserves alpha transparency', (tester) async {
    _configureView(tester, const Size(32, 32));
    const box = Center(
      child: SizedBox(width: 12, height: 12, child: ColoredBox(color: Color(0xFF2288CC))),
    );
    final raw = (await tester.runAsync(
      () => captureFrame(
        composition: box,
        aspect: Aspect.square,
        pumpWidget: tester.pumpWidget,
        pumpFrame: tester.pump,
        longEdge: 32,
      ),
    ))!;
    expect(raw.frameIndex, 0);
    expect(raw.rgba[3], 0);
    final png = (await tester.runAsync(() => encodeRawFramePng(raw)))!;
    expect(png.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final decoded = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(png);
      final info = await codec.getNextFrame();
      try {
        return (await info.image.toByteData())!.buffer.asUint8List();
      } finally {
        info.image.dispose();
        codec.dispose();
      }
    });
    expect(decoded, raw.rgba);
  });

  test('captureFrame rejects invalid arguments before mounting', () async {
    var mounted = false;
    Future<void> fail(Widget _) async => mounted = true;
    Future<void> noop() async {}
    for (final args in const [
      (1, Duration.zero, 30, 64),
      (-1, null, 30, 64),
      (0, null, 0, 64),
      (0, null, 30, 0),
    ]) {
      await expectLater(
        captureFrame(
          composition: const SizedBox(),
          aspect: Aspect.square,
          frame: args.$1,
          at: args.$2,
          fps: args.$3,
          longEdge: args.$4,
          pumpWidget: fail,
          pumpFrame: noop,
        ),
        throwsArgumentError,
      );
    }
    expect(mounted, isFalse);
  });
}
