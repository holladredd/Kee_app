import 'package:flutter/material.dart';

class KeeLogo extends StatelessWidget {
  final double size;
  final bool showBackground;

  const KeeLogo({
    super.key,
    this.size = 48.0,
    this.showBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final markColor = isDark ? const Color(0xFFF1F3F5) : const Color(0xFF0D1115);
    final bgColor = isDark ? const Color(0xFF080A0C) : const Color(0xFFF8F9FA);
    final borderColor = isDark ? const Color(0xFF1C2127) : const Color(0xFFE2E6E9);

    return Container(
      width: size,
      height: size,
      decoration: showBackground
          ? BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(size * 0.25),
              border: Border.all(color: borderColor, width: size * 0.015),
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black.withOpacity(0.4) : Colors.black.withOpacity(0.04),
                  blurRadius: size * 0.12,
                  offset: Offset(0, size * 0.04),
                ),
              ],
            )
          : null,
      padding: EdgeInsets.all(size * 0.18),
      child: CustomPaint(
        painter: _KeePremiumLogoPainter(color: markColor),
      ),
    );
  }
}

class _KeePremiumLogoPainter extends CustomPainter {
  final Color color;

  _KeePremiumLogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final strokeW = size.width * 0.095;

    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // 1. Vertical Architectural Pillar of K
    final stemX = size.width * 0.22;
    canvas.drawLine(
      Offset(stemX, size.height * 0.12),
      Offset(stemX, size.height * 0.88),
      strokePaint,
    );

    // 2. Razor Upper Diagonal of K
    final junctionY = size.height * 0.48;
    canvas.drawLine(
      Offset(stemX + strokeW * 0.6, junctionY),
      Offset(size.width * 0.78, size.height * 0.12),
      strokePaint,
    );

    // 3. Integrated Architectural Lowercase 'e'
    // Crossbar
    final crossbarY = size.height * 0.54;
    canvas.drawLine(
      Offset(stemX + strokeW * 0.6, crossbarY),
      Offset(size.width * 0.82, crossbarY),
      strokePaint,
    );

    // Circle Arc of 'e'
    final path = Path();
    path.moveTo(size.width * 0.82, crossbarY);

    // Upper curve over to the left
    path.cubicTo(
      size.width * 0.82, size.height * 0.38,
      size.width * 0.68, size.height * 0.34,
      size.width * 0.54, size.height * 0.34,
    );
    path.cubicTo(
      size.width * 0.38, size.height * 0.34,
      size.width * 0.32, size.height * 0.46,
      size.width * 0.32, size.height * 0.60,
    );
    // Lower curve wrapping under
    path.cubicTo(
      size.width * 0.32, size.height * 0.78,
      size.width * 0.42, size.height * 0.90,
      size.width * 0.62, size.height * 0.90,
    );
    path.cubicTo(
      size.width * 0.76, size.height * 0.90,
      size.width * 0.84, size.height * 0.82,
      size.width * 0.88, size.height * 0.74,
    );

    canvas.drawPath(path, strokePaint);

    // 4. Subtle Precision Platinum Pip
    canvas.drawCircle(
      Offset(size.width * 0.54, size.height * 0.44),
      strokeW * 0.28,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _KeePremiumLogoPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
