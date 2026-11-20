import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluvie/fluvie.dart';
import 'package:fluvie/rendering.dart';

typedef _SceneSample = ({Duration time, Size size, Aspect aspect, int seed});

Video _scene(void Function(_SceneSample) read, {int seed = 42}) => Video(
  width: 120,
  height: 150,
  seed: seed,
  scenes: [
    const Scene(duration: Time.frames(1), children: [SizedBox()]),
    Scene(
      duration: const Time.frames(29),
      children: [
        Center(
          child: SizedBox.square(
            dimension: 32,
            child: FrameBuilder((ctx) {
              read((time: ctx.time, size: ctx.size, aspect: ctx.aspect, seed: ctx.seed));
              return const ColoredBox(color: Color(0xFF2A9D8F));
            }),
          ),
        ),
      ],
    ),
  ],
);

void main() {
  testWidgets('still and sequential capture expose the same output canvas and clock', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size.square(96)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });
    late _SceneSample sample;
    final composition = Directionality(
      textDirection: TextDirection.ltr,
      child: _scene((value) => sample = value),
    );

    await tester.runAsync(
      () => captureFrame(
        composition: composition,
        aspect: Aspect.square,
        frame: 1,
        longEdge: 96,
        pumpWidget: tester.pumpWidget,
        pumpFrame: tester.pump,
      ),
    );
    final still = sample;
    expect(still.size, const Size.square(96));
    expect(still.aspect, Aspect.square);
    expect(still.seed, 42);
    expect(still.time, const Duration(microseconds: 33334));
    expect(frameIndexFor(still.time), 1);

    await tester.runAsync(
      () => captureFrame(
        composition: composition,
        aspect: Aspect.square,
        at: still.time,
        longEdge: 96,
        pumpWidget: tester.pumpWidget,
        pumpFrame: tester.pump,
      ),
    );
    expect(sample.time, still.time);
    expect(sample.size, still.size);

    await tester.runAsync(
      () => renderToSandbox(
        composition: composition,
        aspect: Aspect.square,
        frameCount: 2,
        longEdge: 96,
        sandbox: MemoryRenderSandbox(),
        capture: const RepaintBoundaryCaptureService(),
        pumpWidget: tester.pumpWidget,
        pumpFrame: tester.pump,
      ),
    );
    expect(sample, still);
  });

  testWidgets('plain preview uses the authored canvas and inherited aspect', (tester) async {
    late _SceneSample sample;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: AspectScope(
          aspect: Aspect.portrait45,
          child: FrameProvider(frame: 1, child: _scene((value) => sample = value, seed: -9)),
        ),
      ),
    );
    expect(sample.size, const Size(120, 150));
    expect(sample.aspect, Aspect.portrait45);
    expect(sample.seed, -9);
  });

  testWidgets('a video that omits the seed exposes zero', (tester) async {
    late int seed;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FrameProvider(
          frame: 0,
          child: Video(
            width: 80,
            height: 40,
            scenes: [
              Scene(
                duration: const Time.frames(2),
                children: [
                  FrameBuilder((ctx) {
                    seed = ctx.seed;
                    return const SizedBox();
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    expect(seed, 0);
  });
}
