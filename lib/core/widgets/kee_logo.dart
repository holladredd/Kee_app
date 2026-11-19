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

    final primaryColor = isDark
        ? const Color(0xFF7CB8A3) // Glow sage in dark
        : const Color(0xFF265345); // Deep slate in light

    final bgColor = isDark
        ? const Color(0xFF14191C)
        : const Color(0xFFF4F7F5);

    final borderColor = isDark
        ? const Color(0xFF253036)
        : const Color(0xFFD8E1DD);

    return Container(
      width: size,
      height: size,
      decoration: showBackground
          ? BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(size * 0.24),
              border: Border.all(color: borderColor, width: size * 0.015),
            )
          : null,
      padding: EdgeInsets.all(size * 0.16),
      child: CustomPaint(
        painter: _KeeLogoPainter(color: primaryColor, isDark: isDark),
      ),
    );
  }
}

class _KeeLogoPainter extends CustomPainter {
  final Color color;
  final bool isDark;

  _KeeLogoPainter({required this.color, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final strokeW = size.width * 0.11;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = isDark ? Colors.white : color
      ..style = PaintingStyle.fill;

    // 1. Vertical stem of 'K'
    final stemX = size.width * 0.22;
    canvas.drawLine(
      Offset(stemX, size.height * 0.15),
      Offset(stemX, size.height * 0.85),
      paint,
    );

    // 2. Upper arm of 'K'
    final branchY = size.height * 0.52;
    canvas.drawLine(
      Offset(stemX + strokeW * 0.5, branchY),
      Offset(size.width * 0.78, size.height * 0.18),
      paint,
    );

    // 3. Lower arm of 'K' transitioning smoothly into lowercase 'e'
    final path = Path();
    path.moveTo(stemX + strokeW * 0.5, branchY + strokeW * 0.2);

    // Curve down towards the 'e' body
    path.cubicTo(
      size.width * 0.45, size.height * 0.65,
      size.width * 0.55, size.height * 0.70,
      size.width * 0.74, size.height * 0.70,
    );

    // Loop around the head of 'e'
    path.cubicTo(
      size.width * 0.90, size.height * 0.70,
      size.width * 0.95, size.height * 0.58,
      size.width * 0.86, size.height * 0.48,
    );

    path.cubicTo(
      size.width * 0.78, size.height * 0.38,
      size.width * 0.55, size.height * 0.42,
      size.width * 0.52, size.height * 0.58,
    );

    // Outer tail of 'e'
    path.cubicTo(
      size.width * 0.50, size.height * 0.75,
      size.width * 0.60, size.height * 0.88,
      size.width * 0.82, size.height * 0.85,
    );

    canvas.drawPath(path, paint);

    // 4. Memory Spark dot inside 'e'
    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.54),
      strokeW * 0.38,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _KeeLogoPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.isDark != isDark;
  }
}
