import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluvie/rendering.dart';
import 'package:fluvie_mobile_encoder/fluvie_mobile_encoder.dart';

import 'capture_support.dart';

void main() {
  final binding = CaptureOnlyBinding();

  test('offscreen motion resolves without application frames', () async {
    expect(binding, isNot(isA<TestWidgetsFlutterBinding>()));
    var applicationCallbacks = 0;
    binding.addPostFrameCallback((_) => applicationCallbacks++);
    final first = await captureFrames(motion: true);
    final second = await captureFrames(motion: true);
    expect(first, second);
    expect(applicationCallbacks, 0);
    const frameBytes = 96 * 96 * 4;
    final beginning = first.sublist(0, frameBytes);
    final ending = first.sublist(29 * frameBytes, 30 * frameBytes);
    expect(
      goldPixelCount(beginning),
      greaterThan(100),
      reason: 'The animated child must be visible in captured frame zero.',
    );
    expect(beginning, isNot(ending), reason: 'The captured child must move.');
  });

  test('application frames do not alter capture or lose app state', () async {
    final appKey = GlobalKey<_ApplicationCounterState>();
    runApp(_ApplicationCounter(key: appKey));
    await Future<void>.delayed(Duration.zero);
    var appFrames = 0;
    void drawApplication() {
      binding
        ..handleBeginFrame(Duration(milliseconds: appFrames * 16))
        ..handleDrawFrame();
      appFrames++;
    }

    drawApplication();
    try {
      final state = appKey.currentState;
      if (state == null) throw StateError('Application did not mount.');
      var callbacks = 0;
      Future<void> advanceApplication() async {
        state.increment();
        binding.addPostFrameCallback((_) => callbacks++);
        drawApplication();
      }

      final first = await captureFrames(motion: true, beforeFrame: advanceApplication);
      final second = await captureFrames(motion: true, beforeFrame: advanceApplication);
      expect(first, second);
      expect(callbacks, 60);
      expect(state.value, 60);
      expect(state.lastBuiltValue, 60);
      expect(appKey.currentState, same(state));
      expect(state.mounted, isTrue);
      expect(goldPixelCount(first), greaterThan(100));
    } finally {
      runApp(const SizedBox.shrink());
      await Future<void>.delayed(Duration.zero);
      drawApplication();
    }
  });

  test('capture failure unmounts the boundary and allows another job', () async {
    final failure = _FailingCapture();
    await expectLater(
      captureFrames(motion: true, capture: failure),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'synthetic capture failure',
        ),
      ),
    );
    expect(failure.boundary, isNotNull);
    expect(failure.boundary?.currentContext, isNull);
    expect(goldPixelCount(await captureFrames(motion: true)), greaterThan(100));
  });

  test('capture failure disposes the view and allows another job', () async {
    final hosts = <OffscreenCaptureHost>[];
    await expectLater(
      captureFrames(
        motion: true,
        capture: _FailingCapture(),
        frameCount: 2,
        retainHost: hosts,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'synthetic capture failure',
        ),
      ),
    );
    expect(hosts, hasLength(1));
    expect(
      _viewDisposed(hosts.single),
      isTrue,
      reason: 'A failed capture must dispose its RenderView.',
    );
    expect(
      _pipelineDisposeReturned(hosts.single),
      isTrue,
      reason: 'A failed capture must finish PipelineOwner disposal.',
    );
    await hosts.single.dispose();
    await expectLater(
      hosts.single.mount(const SizedBox.shrink()),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'This offscreen host is disposed.',
        ),
      ),
    );
    expect(goldPixelCount(await captureFrames(motion: true, frameCount: 2)), greaterThan(100));
  });

  test('repeated dispose outside a frame returns the same future', () async {
    final host = OffscreenCaptureHost(const Size(96, 96));
    await host.mount(const SizedBox.shrink());
    final first = host.dispose();
    final second = host.dispose();
    expect(
      second,
      same(first),
      reason: 'Dispose outside a frame must return the same future.',
    );
    await first;
    expect(
      host.dispose(),
      same(first),
      reason: 'Dispose after completion must return the same future.',
    );
    expect(_viewDisposed(host), isTrue);
    expect(_pipelineDisposeReturned(host), isTrue);
  });

  test('disposing the offscreen host unmounts its tree', () async {
    final key = GlobalKey();
    final host = OffscreenCaptureHost(const Size(96, 96));
    await host.mount(SizedBox(key: key));
    expect(key.currentContext, isNotNull);
    await host.dispose();
    expect(key.currentContext, isNull);
    await host.dispose();
  });

  test('disposing the offscreen host releases the view and pipeline', () async {
    final key = GlobalKey();
    final host = OffscreenCaptureHost(const Size(96, 96));
    await host.mount(SizedBox(key: key));
    await host.dispose();
    expect(key.currentContext, isNull);
    expect(
      _viewDisposed(host),
      isTrue,
      reason: 'Dispose must mark the RenderView disposed.',
    );
    expect(
      _pipelineDisposeReturned(host),
      isTrue,
      reason: 'Dispose must return from PipelineOwner.dispose.',
    );
    await host.dispose();
    await expectLater(
      host.mount(const SizedBox.shrink()),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'This offscreen host is disposed.',
        ),
      ),
    );
    final next = OffscreenCaptureHost(const Size(96, 96));
    await next.mount(const SizedBox.shrink());
    await next.dispose();
    expect(_viewDisposed(next), isTrue);
  });

  test('repeated captures dispose each host and keep producing pixels', () async {
    final hosts = <OffscreenCaptureHost>[];
    final first = await captureFrames(motion: true, frameCount: 2, retainHost: hosts);
    final second = await captureFrames(motion: true, frameCount: 2, retainHost: hosts);
    expect(goldPixelCount(first), greaterThan(100));
    expect(first, second);
    expect(hosts, hasLength(2));
    for (final host in hosts) {
      expect(
        _viewDisposed(host),
        isTrue,
        reason: 'Each repeated capture must dispose its RenderView.',
      );
      expect(_pipelineDisposeReturned(host), isTrue);
      await host.dispose();
    }
  });

  test('capture requested during an application build is rejected', () async {
    final host = OffscreenCaptureHost(const Size(96, 96));
    final captured = GlobalKey();
    await host.mount(SizedBox(key: captured));
    expect(captured.currentContext, isNotNull);
    // buildScope returns immediately when that scope has no dirty elements,
    // which would hide a re-entrant build. Dirty the mounted capture tree
    // while the binding is idle, before the application frame starts.
    (captured.currentContext! as Element).markNeedsBuild();
    final key = GlobalKey();
    final slot = _BuildSlot();
    var posts = 0;
    binding.addPostFrameCallback((_) => posts++);
    runApp(
      _BuildTimeRequest(key: key, host: host, binding: binding, slot: slot),
    );
    await Future<void>.delayed(Duration.zero);
    binding
      ..handleBeginFrame(Duration.zero)
      ..handleDrawFrame();
    await Future<void>.delayed(Duration.zero);
    expect(posts, 1, reason: 'The application frame runs its own post-frame callback once.');
    expect(slot.frameDelta, 0, reason: 'Capture must not schedule an application frame.');
    expect(slot.warmDelta, 0, reason: 'Capture must not schedule a warm-up frame.');
    expect(
      slot.error,
      isA<StateError>().having(
        (error) => error.message,
        'message',
        'Offscreen capture cannot run during an application build.',
      ),
      reason: 'Capture during an application build must reject explicitly.',
    );
    expect(key.currentContext, isNotNull);
    await host.dispose();
    runApp(const SizedBox.shrink());
    await Future<void>.delayed(Duration.zero);
    binding
      ..handleBeginFrame(const Duration(milliseconds: 16))
      ..handleDrawFrame();
  });

  test('dispose from application State.dispose waits out the frame', () async {
    final host = OffscreenCaptureHost(const Size(96, 96));
    final captured = GlobalKey();
    await host.mount(SizedBox(key: captured));
    final pending = <Future<void>>[];
    final errors = <Object>[];
    final screen = GlobalKey<_ClosingScreenState>();
    runApp(_ClosingScreen(key: screen, host: host, pending: pending, errors: errors));
    await Future<void>.delayed(Duration.zero);
    binding
      ..handleBeginFrame(Duration.zero)
      ..handleDrawFrame();
    await Future<void>.delayed(Duration.zero);
    expect(screen.currentState, isNotNull, reason: 'The screen must mount before it closes.');
    expect(pending, isEmpty);
    expect(_viewDisposed(host), isNot(true));

    runApp(const SizedBox.shrink());
    await Future<void>.delayed(Duration.zero);
    final framesAfterRemove = binding.scheduleFrameCalls;
    final warmAfterRemove = binding.warmUpCalls;
    binding
      ..handleBeginFrame(const Duration(milliseconds: 16))
      ..handleDrawFrame();
    expect(pending, hasLength(1));
    final outcome = await pending.single.then<Object?>(
      (_) => null,
      onError: (Object error, StackTrace _) => error,
    );
    expect(
      outcome,
      isNull,
      reason: 'Dispose during State.dispose must finish after the frame.',
    );
    expect(errors, isEmpty);
    expect(
      _viewDisposed(host),
      isTrue,
      reason: 'Dispose during State.dispose must release the RenderView.',
    );
    expect(
      _pipelineDisposeReturned(host),
      isTrue,
      reason: 'Dispose during State.dispose must finish PipelineOwner disposal.',
    );
    expect(captured.currentContext, isNull);
    // Releasing the offscreen element outside the frame marks it dirty, so the
    // shared build owner may request one frame. Dispose does not wait for it.
    expect(
      binding.scheduleFrameCalls,
      lessThanOrEqualTo(framesAfterRemove + 1),
      reason: 'Dispose must not wait on a new frame.',
    );
    expect(
      binding.warmUpCalls,
      warmAfterRemove,
      reason: 'Dispose must not schedule a warm-up frame.',
    );
    await host.dispose();
    await expectLater(
      host.mount(const SizedBox.shrink()),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'This offscreen host is disposed.',
        ),
      ),
    );
  });

  test('capture requested from an animation callback is rejected', () async {
    final host = OffscreenCaptureHost(const Size(96, 96));
    await host.mount(const SizedBox.shrink());
    final slot = _FrameProbe();
    binding.scheduleFrameCallback((_) {
      slot
        ..phase = binding.schedulerPhase
        ..building = binding.buildOwner!.debugBuilding;
      final frames = binding.scheduleFrameCalls;
      final warm = binding.warmUpCalls;
      final future = host.pumpFrame();
      slot
        ..frameDelta = binding.scheduleFrameCalls - frames
        ..warmDelta = binding.warmUpCalls - warm;
      unawaited(
        future.then<void>((_) {}, onError: (Object error, StackTrace _) => slot.error = error),
      );
    }, scheduleNewFrame: false);
    binding
      ..handleBeginFrame(Duration.zero)
      ..handleDrawFrame();
    await Future<void>.delayed(Duration.zero);
    expect(slot.phase, SchedulerPhase.transientCallbacks);
    expect(
      slot.building,
      isFalse,
      reason: 'An animation callback runs outside widget build.',
    );
    expect(slot.frameDelta, 0, reason: 'Capture must not schedule an application frame.');
    expect(slot.warmDelta, 0, reason: 'Capture must not schedule a warm-up frame.');
    expect(
      slot.error,
      isA<StateError>().having(
        (error) => error.message,
        'message',
        'Offscreen capture cannot run during an application build.',
      ),
      reason: 'Capture during an animation callback must reject explicitly.',
    );
    await host.dispose();
  });

  test('capture requested from build while the scheduler is idle is rejected', () async {
    final host = OffscreenCaptureHost(const Size(96, 96));
    final slot = _FrameProbe();
    await host.mount(
      _IdleBuildCapture(host: host, binding: binding, slot: slot),
    );
    await Future<void>.delayed(Duration.zero);
    expect(slot.phase, SchedulerPhase.idle);
    expect(slot.building, isTrue, reason: 'The scheduler is idle while the capture tree builds.');
    expect(slot.frameDelta, 0, reason: 'Capture must not schedule an application frame.');
    expect(slot.warmDelta, 0, reason: 'Capture must not schedule a warm-up frame.');
    expect(
      slot.error,
      isA<StateError>().having(
        (error) => error.message,
        'message',
        'Offscreen capture cannot run during an application build.',
      ),
      reason: 'Capture during build must reject even when no frame is scheduled.',
    );
    await host.dispose();
  });

  test('a preparation callback may schedule another', () async {
    final log = <String>[];
    final host = OffscreenCaptureHost(const Size(96, 96));
    await host.mount(_ChainedPreparation(log));
    expect(log, ['build', 'first', 'second']);
    await host.dispose();
    expect(_viewDisposed(host), isTrue);
  });

  test(
    'a preparation that reschedules itself stops',
    () async {
      final host = OffscreenCaptureHost(const Size(96, 96));
      await expectLater(
        host.mount(const _LoopingPreparation()),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Offscreen capture preparation did not finish.',
          ),
        ),
      );
      await host.dispose();
      expect(
        _viewDisposed(host),
        isTrue,
        reason: 'A preparation failure must still leave the host disposable.',
      );
    },
    // The production cap throws. This timeout is the backstop the contract
    // asks for. A package:test Timeout uses a timer, so it does not interrupt
    // a synchronous tight loop that never yields.
    timeout: const Timeout(Duration(seconds: 2)),
  );
}

bool? _viewDisposed(OffscreenCaptureHost host) => host.debugRenderViewDisposed;

bool _pipelineDisposeReturned(OffscreenCaptureHost host) => host.debugPipelineDisposeReturned;

final class _FailingCapture implements FrameCaptureService {
  GlobalKey? boundary;

  @override
  Future<RawFrame> capture({
    required GlobalKey boundaryKey,
    required int frameIndex,
    required int width,
    required int height,
  }) async {
    boundary = boundaryKey;
    if (frameIndex == 1) throw StateError('synthetic capture failure');
    return const RepaintBoundaryCaptureService().capture(
      boundaryKey: boundaryKey,
      frameIndex: frameIndex,
      width: width,
      height: height,
    );
  }
}

class _ApplicationCounter extends StatefulWidget {
  const _ApplicationCounter({super.key});

  @override
  State<_ApplicationCounter> createState() => _ApplicationCounterState();
}

class _ApplicationCounterState extends State<_ApplicationCounter> {
  int value = 0;
  int lastBuiltValue = -1;

  void increment() => setState(() => value++);

  @override
  Widget build(BuildContext context) {
    lastBuiltValue = value;
    return ColoredBox(color: value.isEven ? const Color(0xFF00FF00) : const Color(0xFF0000FF));
  }
}

class _BuildSlot {
  int frameDelta = -1;
  int warmDelta = -1;
  Object? error;
}

class _BuildTimeRequest extends StatelessWidget {
  const _BuildTimeRequest({
    required this.host,
    required this.binding,
    required this.slot,
    super.key,
  });

  final OffscreenCaptureHost host;
  final CaptureOnlyBinding binding;
  final _BuildSlot slot;

  @override
  Widget build(BuildContext context) {
    final frames = binding.scheduleFrameCalls;
    final warm = binding.warmUpCalls;
    final future = host.pumpFrame();
    slot
      ..frameDelta = binding.scheduleFrameCalls - frames
      ..warmDelta = binding.warmUpCalls - warm;
    unawaited(
      future.then<void>((_) {}, onError: (Object error, StackTrace _) => slot.error = error),
    );
    return const SizedBox.shrink();
  }
}

class _FrameProbe {
  Object? error;
  SchedulerPhase? phase;
  bool? building;
  int frameDelta = -1;
  int warmDelta = -1;
}

class _ClosingScreen extends StatefulWidget {
  const _ClosingScreen({
    required this.host,
    required this.pending,
    required this.errors,
    super.key,
  });

  final OffscreenCaptureHost host;
  final List<Future<void>> pending;
  final List<Object> errors;

  @override
  State<_ClosingScreen> createState() => _ClosingScreenState();
}

class _ClosingScreenState extends State<_ClosingScreen> {
  @override
  void dispose() {
    final future = widget.host.dispose();
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object error, StackTrace _) => widget.errors.add(error),
      ),
    );
    widget.pending.add(future);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _IdleBuildCapture extends StatelessWidget {
  const _IdleBuildCapture({required this.host, required this.binding, required this.slot});

  final OffscreenCaptureHost host;
  final CaptureOnlyBinding binding;
  final _FrameProbe slot;

  @override
  Widget build(BuildContext context) {
    slot.phase = binding.schedulerPhase;
    slot.building = binding.buildOwner!.debugBuilding;
    final frames = binding.scheduleFrameCalls;
    final warm = binding.warmUpCalls;
    final future = host.pumpFrame();
    slot
      ..frameDelta = binding.scheduleFrameCalls - frames
      ..warmDelta = binding.warmUpCalls - warm;
    unawaited(
      future.then<void>((_) {}, onError: (Object error, StackTrace _) => slot.error = error),
    );
    return const SizedBox.shrink();
  }
}

class _ChainedPreparation extends StatelessWidget {
  const _ChainedPreparation(this.log);

  final List<String> log;

  @override
  Widget build(BuildContext context) {
    log.add('build');
    if (log.length == 1) {
      _schedulePreparation(context, () {
        log.add('first');
        _schedulePreparation(context, () => log.add('second'));
      });
    }
    return const SizedBox.shrink();
  }
}

class _LoopingPreparation extends StatelessWidget {
  const _LoopingPreparation();

  @override
  Widget build(BuildContext context) {
    void bounce() => _schedulePreparation(context, bounce);
    _schedulePreparation(context, bounce);
    return const SizedBox.shrink();
  }
}

void _schedulePreparation(BuildContext context, VoidCallback callback) {
  final scope = CompositionPreparationScope.maybeOf(context);
  if (scope == null) {
    throw StateError('CompositionPreparationScope is absent.');
  }
  scope.schedule(callback);
}
