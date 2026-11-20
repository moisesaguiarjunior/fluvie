// #docregion on-device
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:fluvie/fluvie.dart';
import 'package:fluvie/rendering.dart';
import 'package:fluvie_mobile_encoder/fluvie_mobile_encoder.dart';

Video coverScene() => Video(
  width: 96,
  height: 96,
  scenes: const [
    Scene(
      duration: Time.seconds(1),
      children: [
        Center(
          child: SizedBox(
            width: 64,
            height: 64,
            child: ColoredBox(color: Color(0xFF2A9D8F)),
          ),
        ),
      ],
    ),
  ],
);

Future<Uint8List> captureCover() => OnDeviceVideoRenderer().capturePng(
  composition: coverScene(),
  aspect: Aspect.square,
  at: const Duration(milliseconds: 500),
  longEdge: 96,
);
// #enddocregion on-device

// #docregion custom-host
Future<Uint8List> captureCoverWithHost({
  required ShellMount mount,
  required ShellFramePump pump,
}) async {
  final raw = await captureFrame(
    composition: Directionality(textDirection: TextDirection.ltr, child: coverScene()),
    aspect: Aspect.square,
    frame: 15,
    longEdge: 96,
    pumpWidget: mount,
    pumpFrame: pump,
  );
  return encodeRawFramePng(raw);
}
// #enddocregion custom-host
