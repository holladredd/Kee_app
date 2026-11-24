import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../voice/assistant_state.dart';

/// The Kee Voice Orb: A modern, fluid visual identity for Kee's voice assistant.
/// Uses the Novaré palette (Obsidian, Warm Champagne Ivory, and Champagne Gold).
/// Reactively transitions between Idle, Listening, Processing, Speaking, Interrupted, and Error states.
class KeeVoiceOrb extends StatefulWidget {
  final AssistantState state;
  final double soundLevel; // 0.0 to 1.0 normalized
  final double size;
  final VoidCallback? onTap;

  const KeeVoiceOrb({
    super.key,
    required this.state,
    this.soundLevel = 0.0,
    this.size = 120.0,
    this.onTap,
  });

  @override
  State<KeeVoiceOrb> createState() => _KeeVoiceOrbState();
}

class _KeeVoiceOrbState extends State<KeeVoiceOrb> with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _rotationController;
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    )..repeat();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void didUpdateWidget(KeeVoiceOrb oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.state != widget.state) {
      // Adjust animation speeds based on state
      switch (widget.state) {
        case AssistantState.idle:
          _pulseController.duration = const Duration(milliseconds: 2800);
          _rotationController.duration = const Duration(milliseconds: 9000);
          if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
          break;
        case AssistantState.listening:
          _pulseController.duration = const Duration(milliseconds: 1200);
          _rotationController.duration = const Duration(milliseconds: 4000);
          break;
        case AssistantState.processing:
          _pulseController.duration = const Duration(milliseconds: 800);
          _rotationController.duration = const Duration(milliseconds: 1500);
          break;
        case AssistantState.speaking:
          _pulseController.duration = const Duration(milliseconds: 1000);
          _rotationController.duration = const Duration(milliseconds: 3000);
          break;
        case AssistantState.interrupted:
          _pulseController.duration = const Duration(milliseconds: 400);
          break;
        case AssistantState.error:
          _pulseController.duration = const Duration(milliseconds: 1600);
          break;
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Palette: Novaré Obsidian & Warm Champagne
    final primaryGold = isDark ? const Color(0xFFE8D0B2) : const Color(0xFFA6855B);
    final secondaryGlow = isDark ? const Color(0xFFC8A878) : const Color(0xFFD4B996);
    final coreObsidian = isDark ? const Color(0xFF0F0E0C) : const Color(0xFF231E18);

    Color activeColor;
    switch (widget.state) {
      case AssistantState.error:
        activeColor = const Color(0xFFE57373); // Muted coral red
        break;
      case AssistantState.processing:
        activeColor = const Color(0xFF90CAF9); // Thoughtful luminous blue-gold
        break;
      case AssistantState.interrupted:
        activeColor = const Color(0xFFFFB74D); // Crisp amber transition
        break;
      case AssistantState.listening:
      case AssistantState.speaking:
      case AssistantState.idle:
        activeColor = primaryGold;
        break;
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: widget.size * 1.5,
        height: widget.size * 1.5,
        child: AnimatedBuilder(
          animation: Listenable.merge([_pulseController, _rotationController, _waveController]),
          builder: (context, child) {
            return CustomPaint(
              painter: _KeeOrbPainter(
                state: widget.state,
                soundLevel: widget.soundLevel,
                pulseValue: _pulseController.value,
                rotationAngle: _rotationController.value * 2 * math.pi,
                waveValue: _waveController.value,
                primaryColor: activeColor,
                secondaryColor: secondaryGlow,
                coreColor: coreObsidian,
              ),
              size: Size(widget.size * 1.5, widget.size * 1.5),
            );
          },
        ),
      ),
    );
  }
}

class _KeeOrbPainter extends CustomPainter {
  final AssistantState state;
  final double soundLevel;
  final double pulseValue;
  final double rotationAngle;
  final double waveValue;
  final Color primaryColor;
  final Color secondaryColor;
  final Color coreColor;

  _KeeOrbPainter({
    required this.state,
    required this.soundLevel,
    required this.pulseValue,
    required this.rotationAngle,
    required this.waveValue,
    required this.primaryColor,
    required this.secondaryColor,
    required this.coreColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width * 0.28;

    // Outer ripples / sound reactive waves
    if (state == AssistantState.listening || state == AssistantState.speaking) {
      final audioMultiplier = state == AssistantState.listening
          ? (0.2 + soundLevel * 0.8)
          : (0.3 + 0.4 * math.sin(waveValue * 2 * math.pi).abs());

      // Outer ripple 2
      final rippleRadius2 = baseRadius * (1.25 + 0.35 * audioMultiplier);
      final ripplePaint2 = Paint()
        ..color = primaryColor.withValues(alpha: 0.12 * audioMultiplier)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(center, rippleRadius2, ripplePaint2);

      // Outer ripple 1
      final rippleRadius1 = baseRadius * (1.1 + 0.25 * audioMultiplier);
      final ripplePaint1 = Paint()
        ..color = secondaryColor.withValues(alpha: 0.25 * audioMultiplier)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      canvas.drawCircle(center, rippleRadius1, ripplePaint1);
    }

    // Outer aura glow
    final glowRadius = baseRadius * (1.0 + 0.12 * pulseValue);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          primaryColor.withValues(alpha: state == AssistantState.idle ? 0.2 : 0.4),
          secondaryColor.withValues(alpha: 0.08),
          Colors.transparent,
        ],
        stops: const [0.3, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: glowRadius * 1.5));
    canvas.drawCircle(center, glowRadius * 1.5, glowPaint);

    // Dynamic orbital particles for processing state
    if (state == AssistantState.processing) {
      final particlePaint = Paint()
        ..color = primaryColor.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill;

      const particleCount = 4;
      for (int i = 0; i < particleCount; i++) {
        final angle = rotationAngle + (i * 2 * math.pi / particleCount);
        final distance = baseRadius * 1.25;
        final px = center.dx + distance * math.cos(angle);
        final py = center.dy + distance * math.sin(angle);
        canvas.drawCircle(Offset(px, py), 3.5, particlePaint);
      }
    }

    // Main Orb Sphere Body
    final sphereRadius = baseRadius * (0.95 + 0.05 * pulseValue);
    final sphereGradient = RadialGradient(
      center: Alignment(
        -0.35 * math.cos(rotationAngle * 0.5),
        -0.35 * math.sin(rotationAngle * 0.5),
      ),
      colors: [
        primaryColor.withValues(alpha: 0.95),
        secondaryColor.withValues(alpha: 0.65),
        coreColor,
      ],
      stops: const [0.0, 0.45, 1.0],
    ).createShader(Rect.fromCircle(center: center, radius: sphereRadius));

    final spherePaint = Paint()
      ..shader = sphereGradient
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, sphereRadius, spherePaint);

    // Inner Specular Light Core
    final innerHighlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.28 + 0.1 * pulseValue)
      ..style = PaintingStyle.fill;
    final highlightOffset = Offset(
      center.dx - sphereRadius * 0.28,
      center.dy - sphereRadius * 0.28,
    );
    canvas.drawCircle(highlightOffset, sphereRadius * 0.22, innerHighlight);

    // Interrupted state visual flash
    if (state == AssistantState.interrupted) {
      final flashPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0;
      canvas.drawCircle(center, sphereRadius * 1.05, flashPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _KeeOrbPainter oldDelegate) {
    return oldDelegate.state != state ||
        oldDelegate.soundLevel != soundLevel ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.rotationAngle != rotationAngle ||
        oldDelegate.waveValue != waveValue ||
        oldDelegate.primaryColor != primaryColor;
  }
}
