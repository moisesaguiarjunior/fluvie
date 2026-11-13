import 'package:flutter/widgets.dart';

/// Routes composition preparation to an isolated capture host.
///
/// Preview trees without this scope retain Flutter's post-frame lifecycle.
/// The host queues callbacks during build and invokes them after the complete
/// tree has registered its elements, outside build/layout and before capture.
/// This prepares Fluvie's timeline only; it does not drive arbitrary tickers.
class CompositionPreparationScope extends InheritedWidget {
  /// Creates the scope. [schedule] must defer callbacks until build completes.
  const CompositionPreparationScope({
    required this.schedule,
    required super.child,
    super.key,
  });

  /// Enqueues one composition preparation callback for the current host.
  final void Function(VoidCallback) schedule;

  /// The nearest capture preparation scope, or null for a preview tree.
  static CompositionPreparationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CompositionPreparationScope>();

  @override
  bool updateShouldNotify(CompositionPreparationScope oldWidget) => schedule != oldWidget.schedule;
}
