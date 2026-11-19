import 'dart:typed_data';

import 'package:flutter/widgets.dart' hide Animation;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluvie/fluvie.dart';
import 'package:fluvie_mobile_encoder/fluvie_mobile_encoder.dart';

import 'capture_support.dart';

double _goldCenterX(Uint8List rgba, int width) {
  var sumX = 0;
  var count = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i] > 180 && rgba[i + 1] > 120 && rgba[i + 2] < 140) {
      sumX += (i ~/ 4) % width;
      count++;
    }
  }
  return count == 0 ? -1 : sumX / count;
}

void main() {
  CaptureOnlyBinding();

  test(
    'offscreen still capture renders mid-timeline motion and captions without encoding',
    () async {
      final encoder = FakeMobileVideoEncoder();
      final hosts = <OffscreenCaptureHost>[];
      final renderer = OnDeviceVideoRenderer(
        encoder: encoder,
        hostFactory: (size) {
          final host = OffscreenCaptureHost(size);
          hosts.add(host);
          return host;
        },
      );
      final video = Video(
        width: 96,
        height: 96,
        captions: Captions.words(
          const [CaptionWord('A', at: Time.zero)],
          style: const CaptionStyle.subtitle(),
          position: const CaptionPosition.custom(Alignment(0, 0.7)),
        ),
        scenes: [
          Scene(
            duration: const Time.seconds(1),
            background: Background.color(const Color(0xFF101010)),
            children: [
              Align(
                alignment: const Alignment(0, -0.4),
                child: Container(width: 20, height: 20, color: const Color(0xFFF2C14E)).animate([
                  Animation.fromTo(
                    const Keyframe(x: -1.5),
                    const Keyframe(x: 1.5),
                    phase: AnimationPhase.during,
                    duration: const Time.seconds(1),
                    ease: Ease.linear,
                  ),
                ]),
              ),
            ],
          ),
        ],
      );

      final start = await renderer.captureFrame(
        composition: video,
        aspect: Aspect.square,
        frame: 0,
        longEdge: 96,
      );
      final mid = await renderer.captureFrame(
        composition: video,
        aspect: Aspect.square,
        at: const Duration(milliseconds: 500),
        longEdge: 96,
      );
      final png = await encodeRawFramePng(mid);

      expect(mid.frameIndex, 15);
      expect(goldPixelCount(start.rgba), greaterThan(100));
      expect(goldPixelCount(mid.rgba), greaterThan(100));
      expect(_goldCenterX(mid.rgba, 96), greaterThan(_goldCenterX(start.rgba, 96) + 20));
      expect(whitePixelCount(mid.rgba), greaterThan(10));
      expect(png.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(encoder.requests, isEmpty);
      expect(hosts.every((h) => h.debugRenderViewDisposed == true), isTrue);
    },
  );
}
