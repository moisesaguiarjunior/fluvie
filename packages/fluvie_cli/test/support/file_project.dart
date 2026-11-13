import 'dart:io';

import 'package:test/test.dart';

/// Creates a disposable file-target project using this checkout's SDK.
Future<void> prepareFileProject(Directory project, String composition) async {
  project.createSync(recursive: true);
  File('${project.path}/pubspec.yaml').writeAsStringSync('''
name: e2e_clip
publish_to: none
version: 1.0.0

environment:
  sdk: ^3.12.0

dependencies:
  flutter:
    sdk: flutter
  fluvie:
    path: ${Directory.current.parent.path}/fluvie

dev_dependencies:
  flutter_test:
    sdk: flutter
  alchemist: ^0.14.0
''');
  File('${project.path}/lib/example_video.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync(composition);

  final got = await Process.run('flutter', const [
    'pub',
    'get',
  ], workingDirectory: project.path);
  expect(got.exitCode, 0, reason: '${got.stdout}\n${got.stderr}');
}
