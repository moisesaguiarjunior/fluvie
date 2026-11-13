import 'package:flutter_test/flutter_test.dart';

import 'capture_support.dart';

void main() {
  CaptureOnlyBinding();

  test('aspect capture prepares captions without caller pre-resolution', () async {
    final bytes = await captureFrames(motion: false, captions: true);
    expect(
      whitePixelCount(bytes),
      greaterThan(10),
      reason: 'Caption ink must reach the encoded-input frames.',
    );
  });

  test('aspect capture prepares a local SRT file without caller pre-resolution', () async {
    final bytes = await captureFrames(
      motion: false,
      captionKind: CaptureCaptionKind.srt,
      frameCount: 2,
    );
    expect(
      whitePixelCount(bytes),
      greaterThan(10),
      reason: 'SRT caption ink must reach render frames.',
    );
  });

  test('aspect capture prepares a local VTT file without caller pre-resolution', () async {
    final bytes = await captureFrames(
      motion: false,
      captionKind: CaptureCaptionKind.vtt,
      frameCount: 2,
    );
    expect(
      whitePixelCount(bytes),
      greaterThan(10),
      reason: 'VTT caption ink must reach render frames.',
    );
  });
}
