import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/vpn_status.dart';
import '../../core/providers.dart';

/// Живой график upload/download за последние 60 секунд.
/// Считывает vpnStatusProvider и копит дельту байт между тиками.
class TrafficChart extends ConsumerStatefulWidget {
  const TrafficChart({super.key});

  @override
  ConsumerState<TrafficChart> createState() => _TrafficChartState();
}

class _TrafficChartState extends ConsumerState<TrafficChart> {
  static const _maxPoints = 60;
  final List<double> _up = List.filled(_maxPoints, 0);
  final List<double> _down = List.filled(_maxPoints, 0);

  int _lastUp = 0;
  int _lastDown = 0;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<VpnStatus>>(vpnStatusProvider, (prev, next) {
      final s = next.asData?.value;
      if (s == null) return;

      final dUp = math.max(0, s.uploadBytes - _lastUp).toDouble();
      final dDown = math.max(0, s.downloadBytes - _lastDown).toDouble();
      _lastUp = s.uploadBytes;
      _lastDown = s.downloadBytes;

      setState(() {
        _up.removeAt(0);
        _up.add(dUp);
        _down.removeAt(0);
        _down.add(dDown);
      });
    });

    final maxVal = math.max(
      1.0,
      math.max(
        _up.fold<double>(0, math.max),
        _down.fold<double>(0, math.max),
      ),
    );

    return SizedBox(
      height: 88,
      child: CustomPaint(
        painter: _Painter(_up, _down, maxVal),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _Painter extends CustomPainter {
  _Painter(this.up, this.down, this.maxVal);

  final List<double> up;
  final List<double> down;
  final double maxVal;

  @override
  void paint(Canvas canvas, Size size) {
    _drawSeries(canvas, size, down, const Color(0xFF6EE7B7), fill: true);
    _drawSeries(canvas, size, up, const Color(0xFFFCD34D));

    // Базовая линия снизу.
    final base = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      base,
    );
  }

  void _drawSeries(Canvas canvas, Size size, List<double> data, Color color,
      {bool fill = false}) {
    if (data.length < 2) return;
    final dx = size.width / (data.length - 1);
    final path = Path();
    for (var i = 0; i < data.length; i++) {
      final h = size.height - (data[i] / maxVal) * size.height * 0.95;
      if (i == 0) {
        path.moveTo(0, h);
      } else {
        path.lineTo(dx * i, h);
      }
    }
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, stroke);

    if (fill) {
      final fillPath = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.35), color.withOpacity(0.0)],
        ).createShader(Offset.zero & size);
      canvas.drawPath(fillPath, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _Painter old) =>
      old.up != up || old.down != down || old.maxVal != maxVal;
}
