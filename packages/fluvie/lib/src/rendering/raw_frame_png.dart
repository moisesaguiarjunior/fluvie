import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fluvie/src/core/errors/fluvie_render_exception.dart';
import 'package:fluvie/src/rendering/capture/raw_frame.dart';

/// Encodes one captured [RawFrame] (RGBA8888, alpha preserved) into PNG bytes
/// via the Flutter engine codec, without touching the file system.
///
/// Throws an [ArgumentError] when [frame] has invalid dimensions, or a
/// [FluvieRenderException] if the engine returns no PNG bytes. Codec errors
/// propagate through the returned future.
Future<Uint8List> encodeRawFramePng(RawFrame frame) async {
  if (frame.width <= 0) {
    throw ArgumentError.value(frame.width, 'frame.width', 'must be positive');
  }
  if (frame.height <= 0) {
    throw ArgumentError.value(frame.height, 'frame.height', 'must be positive');
  }
  // Divide the buffer length to validate dimensions without integer overflow.
  if (frame.rgba.length ~/ 4 ~/ frame.width != frame.height) {
    throw ArgumentError('RGBA bytes do not fit dimensions ${frame.width}x${frame.height}.');
  }
  final image = await _decodeFrame(frame);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      // coverage:ignore-start defensive engine guard; toByteData(png) returns bytes for a valid image
      throw FluvieRenderException(
        'PNG encoding returned no data for frame ${frame.frameIndex} '
        '(${frame.width}x${frame.height}).',
      );
      // coverage:ignore-end
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

Future<ui.Image> _decodeFrame(RawFrame frame) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(frame.rgba);
  try {
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: frame.width,
      height: frame.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    try {
      final codec = await descriptor.instantiateCodec();
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}
