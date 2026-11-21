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

    final logoAsset = isDark
        ? 'assets/logo/Kee Logo on Dark Canvas.png'
        : 'assets/logo/kee_logo_mark_light.png';

    if (!showBackground) {
      return Image.asset(
        logoAsset,
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    }

    final bgColor = isDark ? const Color(0xFF050505) : const Color(0xFFFAF8F5);
    final borderColor = isDark ? const Color(0xFF272625) : const Color(0xFFE5DFD5);

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.5)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: size * 0.15,
            offset: Offset(0, size * 0.04),
          ),
        ],
      ),
      child: Image.asset(
        logoAsset,
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}
