import 'dart:math';

import 'package:flutter/material.dart';

// يرسم وردة الجلسة: تكبر مع الوقت من نبتة صغيرة إلى وردة متفتحة
class FocusRosePainter extends CustomPainter {
  FocusRosePainter({
    required this.growth,
    required this.color,
    this.sway = 0,
    this.wilted = false,
  });

  final double growth; // من 0 (بداية الجلسة) إلى 1 (خلصت)
  final Color color; // لون المشروع
  final double sway; // التمايل مع الهواء
  final bool wilted; // 🥀 ذبلت؟

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 300;
    final g = growth.clamp(0.0, 1.0);

    // المراحل: الساق يطلع، بعدين الأوراق، بعدين الزهرة تتفتح
    final stemGrow =
        0.06 + 0.94 * Curves.easeOut.transform((g / 0.35).clamp(0.0, 1.0));
    final leafGrow = ((g - 0.15) / 0.3).clamp(0.0, 1.0);
    final bloom = Curves.easeOutBack.transform(
      ((g - 0.3) / 0.7).clamp(0.0, 1.0),
    );

    final ground = Offset(size.width / 2, size.height * 0.94);
    final stemLength = size.height * 0.6;

    // التربة
    canvas.drawOval(
      Rect.fromCenter(center: ground, width: 130 * s, height: 22 * s),
      Paint()..color = const Color(0xFF8D6E63).withValues(alpha: 0.3),
    );

    canvas.save();
    canvas.translate(ground.dx, ground.dy);
    canvas.rotate(sway + (wilted ? 0.22 : 0));

    // الساق
    final top = Offset(0, -stemLength * stemGrow);
    final stemColor = wilted
        ? const Color(0xFF9A9B6E)
        : const Color(0xFF4E8A3E);
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(16 * s, top.dy / 2, top.dx, top.dy),
      Paint()
        ..color = stemColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * s
        ..strokeCap = StrokeCap.round,
    );

    // ورقتين على جنبين الساق
    if (leafGrow > 0) {
      final leafColor = wilted
          ? const Color(0xFFA5A878)
          : const Color(0xFF66A84F);
      _leaf(
        canvas,
        Offset(6 * s, -stemLength * 0.32),
        -0.7,
        leafGrow * s,
        leafColor,
      );
      _leaf(
        canvas,
        Offset(9 * s, -stemLength * 0.55),
        pi + 0.6,
        leafGrow * 0.85 * s,
        leafColor,
      );
    }

    // الزهرة
    if (bloom > 0) {
      canvas.save();
      canvas.translate(top.dx, top.dy);
      if (wilted) canvas.rotate(1.0); // راسها مايل
      _flower(canvas, 46 * s, bloom, wilted ? _faded(color) : color);
      canvas.restore();
    }

    canvas.restore();
  }

  void _leaf(
    Canvas canvas,
    Offset at,
    double angle,
    double scale,
    Color color,
  ) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    canvas.scale(scale);
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(22, -16, 44, 0)
        ..quadraticBezierTo(22, 16, 0, 0),
      Paint()..color = color,
    );
    canvas.restore();
  }

  // كل ما زاد "open" تظهر حلقة بتلات أكبر
  void _flower(Canvas canvas, double r, double open, Color color) {
    final hsl = HSLColor.fromColor(color);
    Color shade(double amount) =>
        hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
    double show(double from) => ((open - from) / 0.35).clamp(0.0, 1.0);

    final size = r * (0.45 + 0.55 * open.clamp(0.0, 1.2));

    // كأس أخضر تحت البرعم
    _ring(
      canvas,
      5,
      size * 0.3,
      size * 0.35,
      size * 0.6,
      0.3,
      const Color(0xFF5E9A48),
      1 - show(0.5),
    );

    _ring(
      canvas,
      5,
      size * 0.45,
      size * 1.0,
      size * 1.1,
      0,
      shade(-0.12),
      show(0.55),
    );
    _ring(
      canvas,
      5,
      size * 0.28,
      size * 0.75,
      size * 0.8,
      pi / 5,
      shade(-0.04),
      show(0.25),
    );
    _ring(canvas, 3, size * 0.12, size * 0.5, size * 0.6, 0.4, shade(0.06), 1);

    canvas.drawCircle(Offset.zero, size * 0.18, Paint()..color = shade(-0.1));
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: size * 0.12),
      0,
      pi * 1.4,
      false,
      Paint()
        ..color = shade(-0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _ring(
    Canvas canvas,
    int count,
    double distance,
    double width,
    double height,
    double rotation,
    Color color,
    double opacity,
  ) {
    if (opacity <= 0) return;
    final fill = Paint()..color = color.withValues(alpha: opacity);
    final stroke = Paint()
      ..color = HSLColor.fromColor(color)
          .withLightness(
            (HSLColor.fromColor(color).lightness - 0.15).clamp(0.0, 1.0),
          )
          .toColor()
          .withValues(alpha: 0.5 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < count; i++) {
      canvas.save();
      canvas.rotate(rotation + i * 2 * pi / count);
      final petal = Rect.fromCenter(
        center: Offset(0, -distance),
        width: width,
        height: height,
      );
      canvas.drawOval(petal, fill);
      canvas.drawOval(petal, stroke);
      canvas.restore();
    }
  }

  Color _faded(Color c) =>
      HSLColor.fromColor(c).withSaturation(0.18).withLightness(0.58).toColor();

  @override
  bool shouldRepaint(covariant FocusRosePainter old) =>
      old.growth != growth ||
      old.color != color ||
      old.sway != sway ||
      old.wilted != wilted;
}
