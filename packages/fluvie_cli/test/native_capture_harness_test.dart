@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:fluvie_cli/src/templates/file_harness_template.dart';
import 'package:test/test.dart';

import 'support/file_project.dart';
import 'support/native_animation_composition.dart';

void main() {
  test(
    'generated harness advances native tickers without interval drift',
    () async {
      final project = Directory.systemTemp.createTempSync('native-harness-');
      addTearDown(() => project.deleteSync(recursive: true));
      await prepareFileProject(project, nativeAnimationComposition);
      final harness = File('${project.path}/test/capture_test.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          fileHarnessSource(
            targetImport: 'package:e2e_clip/example_video.dart',
          ),
        );
      final output = Directory('${project.path}/frames');
      final result = await Process.run('flutter', [
        'test',
        '--no-pub',
        harness.path,
        '--dart-define=FLUVIE_RENDER_OUT_DIR=${output.path}',
        '--dart-define=FLUVIE_RENDER_NO_CACHE=true',
      ], workingDirectory: project.path);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final pixels = File('${output.path}/frames.rgba').readAsBytesSync();
      const width = 96;
      const height = 64;
      const frameBytes = width * height * 4;
      expect(pixels, hasLength(30 * frameBytes));
      for (var frame = 0; frame < 30; frame++) {
        var elapsed = 0;
        for (var bit = 0; bit < 24; bit++) {
          final offset = frame * frameBytes + (48 * width + bit * 4 + 2) * 4;
          if (pixels[offset] > 128) elapsed |= 1 << bit;
        }
        expect(
          elapsed,
          (frame * 1000000 + 14) ~/ 29,
          reason: 'native ticker elapsed microseconds in frame $frame',
        );
      }
    },
  );
}
