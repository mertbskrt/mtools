import 'package:flutter/material.dart';
import 'app_theme.dart';

/// MTools marka işareti — "sparkline M + durum noktası". Sabit 1024x1024
/// koordinat sisteminde tanımlı vektör geometriyi verilen boyuta ölçekleyip
/// Canvas'a çizer. PNG/SVG asset'i yüklemez — renkleri her zaman temadan
/// alır, bu yüzden koyu/açık her varyantta otomatik doğru kontrastı sağlar
/// ve gradyan/gölge/glow içermez.
class MtoolsMark extends StatelessWidget {
  final double size;
  final Color? lineColor;
  final Color? dotColor;

  const MtoolsMark({super.key, this.size = 28, this.lineColor, this.dotColor});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return CustomPaint(
      size: Size.square(size),
      painter: _MtoolsMarkPainter(
        lineColor: lineColor ?? colors.textPrimary,
        dotColor: dotColor ?? colors.success,
      ),
    );
  }
}

class _MtoolsMarkPainter extends CustomPainter {
  final Color lineColor;
  final Color dotColor;

  const _MtoolsMarkPainter({required this.lineColor, required this.dotColor});

  // Kaynak koordinat sistemi 1024x1024.
  static const List<Offset> _points = [
    Offset(205, 740),
    Offset(205, 362),
    Offset(402, 622),
    Offset(512, 284),
    Offset(622, 622),
    Offset(740, 386),
  ];
  static const double _strokeWidth = 66;
  static const Offset _dotCenter = Offset(811, 291);
  static const double _dotRadius = 51;
  static const double _viewBox = 1024;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _viewBox;
    canvas.scale(scale);

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()..moveTo(_points.first.dx, _points.first.dy);
    for (final p in _points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, linePaint);

    canvas.drawCircle(_dotCenter, _dotRadius, Paint()..color = dotColor);
  }

  @override
  bool shouldRepaint(_MtoolsMarkPainter oldDelegate) =>
      oldDelegate.lineColor != lineColor || oldDelegate.dotColor != dotColor;
}
