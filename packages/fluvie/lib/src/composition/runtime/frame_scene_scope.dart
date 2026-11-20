import 'package:flutter/widgets.dart';

/// Carries the authored scene values and the render target through the tree.
final class FrameSceneScope extends InheritedWidget {
  /// Supplies scene values to descendants of [child].
  const FrameSceneScope({
    required super.child,
    this.captureSize,
    this.compositionSize,
    this.seed = 0,
    super.key,
  });

  /// The chosen output dimensions when an export host is mounted.
  final Size? captureSize;

  /// The dimensions declared on the enclosing video.
  final Size? compositionSize;

  /// The video's deterministic seed for frame builders.
  final int seed;

  /// The nearest scope above [context], when present.
  static FrameSceneScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FrameSceneScope>();

  @override
  bool updateShouldNotify(FrameSceneScope oldWidget) =>
      captureSize != oldWidget.captureSize ||
      compositionSize != oldWidget.compositionSize ||
      seed != oldWidget.seed;
}
