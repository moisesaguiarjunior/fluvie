part of 'on_device_video_renderer.dart';

/// Captures one deterministic frame on-device without invoking the video
/// encoder or allocating a temporary video sandbox.
Future<RawFrame> _captureSingleFrameOnDevice({
  required Widget composition,
  required Aspect aspect,
  required int? frame,
  required Duration? at,
  required int? fps,
  required int longEdge,
  required bool stepThrough,
  required CaptureHostFactory hostFactory,
  required FrameCaptureService capture,
  required MediaResolver? mediaResolver,
  required NetworkAllowlist? networkAllowlist,
  required void Function(String message) onWarning,
}) async {
  final request = resolveFrameCapture(
    composition: composition,
    aspect: aspect,
    frame: frame,
    at: at,
    fps: fps,
    longEdge: longEdge,
  );
  final size = request.size;
  final host = hostFactory(Size(size.width.toDouble(), size.height.toDouble()));
  ProviderContainer? ownedContainer;
  MediaResolver? ownedResolver;
  try {
    if (mediaResolver == null) {
      ownedContainer = _createNativeMediaContainer(networkAllowlist);
      ownedResolver = ownedContainer.read<MediaResolver>(mediaResolverProvider);
    }
    return await runStage(
      RenderPhase.capturing,
      () => captureFrame(
        composition: Directionality(textDirection: TextDirection.ltr, child: composition),
        aspect: aspect,
        frame: frame,
        at: at,
        fps: fps,
        longEdge: longEdge,
        stepThrough: stepThrough,
        capture: capture,
        pumpWidget: host.mount,
        pumpFrame: host.pumpFrame,
        resolver: mediaResolver ?? ownedResolver,
      ),
    );
  } finally {
    await runGuarded([
      host.dispose,
      () async {
        final resolver = ownedResolver;
        if (resolver != null && resolver is DisposableResolver) {
          (resolver as DisposableResolver).dispose();
        }
      },
      () async => ownedContainer?.dispose(),
    ], (error, _) => onWarning('Cleanup after frame capture failed: $error'));
  }
}

ProviderContainer _createNativeMediaContainer(NetworkAllowlist? networkAllowlist) =>
    ProviderContainer(
      overrides: [
        frameExtractionServiceProvider.overrideWithValue(const NativeFrameExtractionService()),
        videoProbeServiceProvider.overrideWithValue(const NativeVideoProbeService()),
        if (networkAllowlist != null) networkAllowlistProvider.overrideWithValue(networkAllowlist),
      ],
    );
