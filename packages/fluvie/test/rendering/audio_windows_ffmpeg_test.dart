@Tags(['ffmpeg'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluvie/fluvie.dart';
import 'package:fluvie/rendering.dart';
import 'package:fluvie/src/rendering/platform/process_ffmpeg_runner.dart';

const _edge = 16;
const _sampleRate = 8000;

Future<void> _writeSource(File source, {required bool video, required bool surround}) async {
  final result = await Process.run('ffmpeg', [
    '-v',
    'error',
    if (video) ...['-f', 'lavfi', '-i', 'color=red:s=16x16:r=30:d=1'],
    '-f',
    'lavfi',
    '-i',
    'sine=frequency=880:sample_rate=48000:duration=${video ? 1 : 0.2}',
    if (surround) ...['-af', 'pan=5.1|FC=c0'],
    if (video) ...['-c:v', 'libx264', '-c:a', 'aac', '-shortest'],
    source.path,
  ]);
  expect(result.exitCode, 0, reason: result.stderr as String);
}

Future<ByteData> _decodeAudio(
  WidgetTester tester, {
  required Duration duration,
  required bool video,
  required bool surround,
  required Video Function(String path) composition,
}) async {
  tester.view
    ..physicalSize = const Size(_edge * 1.0, _edge * 1.0)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final pcm = await tester.runAsync(() async {
    final sandbox = await Directory.systemTemp.createTemp('fluvie_audio_windows_');
    try {
      final source = File('${sandbox.path}/source.${video ? 'mp4' : 'wav'}');
      await _writeSource(source, video: video, surround: surround);
      final output =
          await DesktopVideoRenderer(
            runner: ProcessFfmpegRunner(),
            pumpWidget: tester.pumpWidget,
            pumpFrame: tester.pump,
            sandboxFactory: () async => sandbox,
          ).render(
            composition: composition(source.path),
            aspect: Aspect.square,
            duration: duration,
            longEdge: _edge,
          );
      final decoded = await Process.run('ffmpeg', [
        '-v',
        'error',
        '-i',
        output.path,
        '-map',
        '0:a:0',
        '-f',
        's16le',
        '-ac',
        '1',
        '-ar',
        '$_sampleRate',
        'pipe:1',
      ], stdoutEncoding: null);
      expect(decoded.exitCode, 0, reason: decoded.stderr as String);
      return ByteData.sublistView(Uint8List.fromList(decoded.stdout as List<int>));
    } finally {
      await sandbox.delete(recursive: true);
    }
  });
  return pcm!;
}

int _peak(ByteData pcm, double start, double end) {
  final first = (start * _sampleRate).round();
  final last = (end * _sampleRate).round();
  expect(pcm.lengthInBytes, greaterThanOrEqualTo(last * 2));
  var peak = 0;
  for (var index = first; index < last; index++) {
    final sample = pcm.getInt16(index * 2, Endian.little).abs();
    if (sample > peak) peak = sample;
  }
  return peak;
}

void main() {
  for (final surround in [false, true]) {
    final layout = surround ? '5.1, center-only tone' : 'mono';
    testWidgets('scene music loops inside its scene and leaves adjacent scenes silent ($layout)', (
      tester,
    ) async {
      final pcm = await _decodeAudio(
        tester,
        duration: const Duration(seconds: 3),
        video: false,
        surround: surround,
        composition: (path) => Video(
          scenes: [
            const Scene(duration: Time.seconds(1)),
            Scene(duration: const Time.seconds(1), audio: [Audio.music(path, loop: true)]),
            const Scene(duration: Time.seconds(1)),
          ],
        ),
      );
      expect(_peak(pcm, 0.2, 0.35), lessThan(100));
      expect(_peak(pcm, 1.25, 1.4), greaterThan(1000));
      expect(_peak(pcm, 2.25, 2.4), lessThan(100));
    });

    testWidgets('embedded audio follows the clip animate window ($layout)', (tester) async {
      final pcm = await _decodeAudio(
        tester,
        duration: const Duration(seconds: 1),
        video: true,
        surround: surround,
        composition: (path) => Video(
          scenes: [
            Scene(
              duration: const Time.frames(30),
              children: [
                Clip.file(path).animate(const [], window: 15.frames.to(24.frames)),
              ],
            ),
          ],
        ),
      );
      expect(_peak(pcm, 0.15, 0.3), lessThan(100));
      expect(_peak(pcm, 0.55, 0.7), greaterThan(1000));
      expect(_peak(pcm, 0.87, 0.96), lessThan(100));
    });
  }
}
