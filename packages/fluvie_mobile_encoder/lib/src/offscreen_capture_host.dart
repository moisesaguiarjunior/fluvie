// coverage:ignore-file drives the real Flutter engine a live RenderView manual
// pipeline flushes, and toImage read-back) which runs only in a hosted app or an
// on-device integration test, never under the unit-test binding; the orchestrator
// logic is covered with a tester-backed CaptureHost instead.
// fluvie:large-file-ok: one offscreen host; dispose, preparation, and rejection stay together
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:fluvie/rendering.dart' show CompositionPreparationScope;
import 'package:fluvie_mobile_encoder/src/capture_host.dart';

/// The production [CaptureHost]: renders the capture shell into its own
/// off-screen pipeline sized to the target resolution.
///
/// It owns a standalone [RenderView] + [PipelineOwner] + [BuildOwner] that the
/// engine never composites to the screen, so an app can render a video while its
/// real UI stays put. The view is configured to [size] logical pixels at device
/// pixel ratio 1.0, so the capture boundary's `toImage(pixelRatio: 1.0)` reads
/// back exactly `size.width` by `size.height` pixels — the dimension contract
/// Fluvie's capture asserts.
///
/// [mount] and [pumpFrame] must not run from an application animation
/// callback ([SchedulerPhase.transientCallbacks] or
/// [SchedulerPhase.midFrameMicrotasks]) or from widget build. Those calls are
/// rejected. A caller that continues capture from a future resolved by an
/// application animation fails on the frames where that callback is still
/// running and succeeds on the frames where it is not. Start capture from
/// idle code, such as a platform message or a timer.
///
/// [dispose] may be called from [State.dispose]. Flutter invokes that during
/// the frame. Disposal then waits for the current frame's post-frame
/// callbacks and releases the view afterwards. It does not schedule another
/// frame. Do not await [dispose] from inside that same frame; [State.dispose]
/// starts it and returns. Every call returns the same future, including a
/// second call made before the first returns and a call made after that
/// future has completed.
final class OffscreenCaptureHost implements CaptureHost {
  /// Creates a host that renders at [size] logical pixels, using [view] for the
  /// engine handle (defaults to the application's implicit view).
  OffscreenCaptureHost(this.size, {ui.FlutterView? view})
    : _view = view ?? WidgetsBinding.instance.platformDispatcher.implicitView!;

  /// The off-screen surface size in logical pixels.
  final Size size;

  final ui.FlutterView _view;
  final _HostPipelineOwner _pipelineOwner = _HostPipelineOwner();
  // The app's build owner, not a private one: `GlobalKey.currentContext` (how the
  // capture service finds the boundary) resolves only against
  // `WidgetsBinding.instance.buildOwner`, so the capture boundary's key must
  // register there. A private `BuildOwner` would keep the boundary invisible to
  // the lookup. Off-screen isolation still holds: the standalone `_pipelineOwner`
  // and `_renderView` below are never attached to the binding's render tree.
  BuildOwner get _buildOwner => WidgetsBinding.instance.buildOwner!;
  late final RenderView _renderView = RenderView(
    view: _view,
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(size),
      physicalConstraints: BoxConstraints.tight(size),
    ),
  );
  RenderObjectToWidgetElement<RenderBox>? _element;
  final List<VoidCallback> _preparations = [];
  bool _closed = false;
  bool _closing = false;
  Future<void>? _disposeTask;

  /// One video resolves in a single pass. A callback may schedule another.
  /// The cap stops a callback that keeps scheduling itself.
  static const int _maxPreparationPasses = 8;

  /// Whether [RenderView.dispose] has run. Null when asserts are disabled.
  /// This is disposal of the view object, not a measurement of native memory.
  @visibleForTesting
  bool? get debugRenderViewDisposed => _renderView.debugDisposed;

  /// Whether [PipelineOwner.dispose] returned. PipelineOwner exposes no
  /// disposed bit; this records that its dispose call completed.
  @visibleForTesting
  bool get debugPipelineDisposeReturned => _pipelineOwner.disposeReturned;

  @override
  Future<void> mount(Widget tree) async {
    if (_closed || _closing) {
      throw StateError('This offscreen host is disposed.');
    }
    _rejectIfApplicationIsBuilding();
    _pipelineOwner.rootNode = _renderView;
    _renderView.prepareInitialFrame();
    _element = RenderObjectToWidgetAdapter<RenderBox>(
      container: _renderView,
      child: CompositionPreparationScope(schedule: _preparations.add, child: tree),
    ).attachToRenderTree(_buildOwner);
    await _flush();
  }

  @override
  Future<void> pumpFrame() => _flush();

  @override
  Future<void> dispose() {
    // Check the stored future first. Idle disposal finishes inside this call,
    // so _closed is already true before dispose returns; a later call must
    // still observe the same future.
    final pending = _disposeTask;
    if (pending != null) return pending;
    if (_closed) return Future<void>.value();
    _closing = true;
    // Mount and capture are rejected during a frame. Dispose is the opposite:
    // State.dispose runs inside the frame, and rejecting it would leave the
    // view allocated. Wait for this frame's post-frame callbacks. endOfFrame
    // is not used: when the phase is idle it schedules a new frame.
    final task = _applicationFrameInProgress() ? _disposeAfterFrame() : _release();
    _disposeTask = task;
    return task;
  }

  Future<void> _disposeAfterFrame() async {
    final done = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    if (_closed) return;
    await _release();
  }

  Future<void> _release() async {
    final element = _element;
    if (element != null) {
      _element = RenderObjectToWidgetAdapter<RenderBox>(
        container: _renderView,
      ).attachToRenderTree(_buildOwner, element);
      _buildOwner.buildScope(_element!);
      _buildOwner.finalizeTree();
    }
    _preparations.clear();
    _pipelineOwner.rootNode = null;
    _element = null;
    _renderView.dispose();
    _pipelineOwner.dispose();
    _closed = true;
  }

  Future<void> _flush() async {
    _rejectIfApplicationIsBuilding();
    _buildOwner.buildScope(_element!);
    var passes = 0;
    while (_preparations.isNotEmpty) {
      if (passes == _maxPreparationPasses) {
        _preparations.clear();
        throw StateError('Offscreen capture preparation did not finish.');
      }
      passes++;
      final callbacks = List<VoidCallback>.of(_preparations);
      _preparations.clear();
      for (final callback in callbacks) {
        callback();
      }
      _buildOwner.buildScope(_element!);
    }
    _pipelineOwner
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();
    _buildOwner.finalizeTree();
    // Yield so the just-painted layers settle before the boundary is read back.
    await Future<void>.delayed(Duration.zero);
  }

  /// Rejects [mount] and [pumpFrame] while an application frame is building.
  ///
  /// [BuildOwner.debugBuilding] is set only when asserts run. Release and
  /// profile builds leave it false, including during `build`, and they also
  /// strip Flutter's re-entrant `buildScope` assert. A frame that is already
  /// inside [SchedulerPhase.transientCallbacks],
  /// [SchedulerPhase.midFrameMicrotasks], or
  /// [SchedulerPhase.persistentCallbacks] is therefore rejected too. Idle and
  /// post-frame calls proceed. This does not schedule a frame, drain
  /// application callbacks, or wait for vsync. [dispose] does not call this.
  void _rejectIfApplicationIsBuilding() {
    if (_closing) {
      throw StateError('This offscreen host is disposed.');
    }
    final building = _buildOwner.debugBuilding;
    final phase = WidgetsBinding.instance.schedulerPhase;
    if (building || _applicationFrameInProgressFor(phase)) {
      throw StateError('Offscreen capture cannot run during an application build.');
    }
  }

  bool _applicationFrameInProgress() =>
      _applicationFrameInProgressFor(WidgetsBinding.instance.schedulerPhase);

  bool _applicationFrameInProgressFor(SchedulerPhase phase) =>
      phase == SchedulerPhase.transientCallbacks ||
      phase == SchedulerPhase.midFrameMicrotasks ||
      phase == SchedulerPhase.persistentCallbacks;
}

/// Records that [PipelineOwner.dispose] returned. The framework type has no
/// public disposed flag, so completion of that call is the observable event.
final class _HostPipelineOwner extends PipelineOwner {
  /// Whether [dispose] has returned.
  bool disposeReturned = false;

  @override
  void dispose() {
    super.dispose();
    disposeReturned = true;
  }
}
