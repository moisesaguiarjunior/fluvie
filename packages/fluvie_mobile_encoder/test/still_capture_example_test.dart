import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../example/still_capture.dart';

void main() {
  testWidgets('the still capture examples produce the same PNG', (tester) async {
    tester.view
      ..physicalSize = const Size.square(96)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });
    final results = (await tester.runAsync(() async {
      final device = await captureCover();
      final custom = await captureCoverWithHost(mount: tester.pumpWidget, pump: tester.pump);
      return (device, custom);
    }))!;
    expect(results.$1.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(results.$1, results.$2);
  });
}
