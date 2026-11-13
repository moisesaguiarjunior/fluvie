/// A native Flutter ticker, with its elapsed microseconds painted as a binary
/// strip so raw and encoded frames expose timing errors smaller than one pixel.
const String nativeAnimationComposition = '''
import 'package:flutter/material.dart' hide Animation, Clip, Image, Tween;
import 'package:fluvie/fluvie.dart';

Video build() => Video(
  width: 96,
  height: 64,
  fps: 29,
  scenes: [
    Scene(
      duration: Time.frames(30),
      children: const [NativeClock()],
    ),
  ],
);

class NativeClock extends StatefulWidget {
  const NativeClock({super.key});

  @override
  State<NativeClock> createState() => _NativeClockState();
}

class _NativeClockState extends State<NativeClock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) => SizedBox(
      width: 96,
      height: 64,
      child: CustomPaint(
        painter: _ClockPainter(
          _controller.value,
          _controller.lastElapsedDuration?.inMicroseconds ?? 0,
        ),
      ),
    ),
  );
}

class _ClockPainter extends CustomPainter {
  const _ClockPainter(this.value, this.elapsed);

  final double value;
  final int elapsed;

  @override
  void paint(Canvas canvas, Size size) {
    final level = (value * 255).round();
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Color.fromARGB(255, level, level, level),
    );
    for (var bit = 0; bit < 24; bit++) {
      canvas.drawRect(
        Rect.fromLTWH(bit * 4.0, 32, 4, 32),
        Paint()..color = (elapsed & (1 << bit)) == 0
            ? Colors.black
            : Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_ClockPainter oldDelegate) => elapsed != oldDelegate.elapsed;
}
''';
