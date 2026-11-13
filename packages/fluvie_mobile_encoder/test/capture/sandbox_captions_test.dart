import 'package:flutter_test/flutter_test.dart';

import 'capture_support.dart';

void main() {
  CaptureOnlyBinding();

  test('sandbox capture prepares inline captions without caller pre-resolution', () async {
    final bytes = await captureFrames(
      motion: false,
      captions: true,
      entry: CaptureEntry.sandbox,
      frameCount: 2,
    );
    expect(
      whitePixelCount(bytes),
      greaterThan(10),
      reason: 'Caption ink must reach renderToSandbox frames.',
    );
  });

  test('sandbox capture prepares a local SRT file without caller pre-resolution', () async {
    final bytes = await captureFrames(
      motion: false,
      captionKind: CaptureCaptionKind.srt,
      entry: CaptureEntry.sandbox,
      frameCount: 2,
    );
    expect(
      whitePixelCount(bytes),
      greaterThan(10),
      reason: 'SRT caption ink must reach renderToSandbox frames.',
    );
  });

  test('sandbox capture prepares a local VTT file without caller pre-resolution', () async {
    final bytes = await captureFrames(
      motion: false,
      captionKind: CaptureCaptionKind.vtt,
      entry: CaptureEntry.sandbox,
      frameCount: 2,
    );
    expect(
      whitePixelCount(bytes),
      greaterThan(10),
      reason: 'VTT caption ink must reach renderToSandbox frames.',
    );
  });
}
