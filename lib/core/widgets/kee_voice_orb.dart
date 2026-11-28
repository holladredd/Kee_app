import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../voice/assistant_state.dart';

/// The Kee Voice Orb — holographic orb using the official Kee brand identity.
/// Palette: Obsidian core (#080808), warm ivory (#F3F0E8), soft grey (#77736B),
/// light accent (#D8D2C5). Zero blue, cyan or neon.
/// Animated mesh-lines inspired by the flowing beige grid in the Kee logo.
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

// ─────────────────────────────────────────────────────────────
// Official Kee brand colours — single source of truth for the orb
// Black:        #080808   Warm ivory:   #F3F0E8
// Soft grey:    #77736B   Light accent: #D8D2C5
// ─────────────────────────────────────────────────────────────
class _KeeBrand {
  static const Color obsidian      = Color(0xFF080808);
  static const Color coreDeep      = Color(0xFF100F0D);
  static const Color warmIvory     = Color(0xFFF3F0E8);
  static const Color champagne     = Color(0xFFD8D2C5);
  static const Color softGrey      = Color(0xFF77736B);
  static const Color ivoryGlow     = Color(0xFFFBF7F0);
  static const Color meshLine      = Color(0xFFBFB8AE);
  static const Color errorRose     = Color(0xFFD97070);
  static const Color amberWarm     = Color(0xFFD4A060);
}

class _KeeVoiceOrbState extends State<KeeVoiceOrb> with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _rotationController;
  late final AnimationController _meshController;
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    )..repeat();

    // Slower counter-rotation for inner mesh layer
    _meshController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 14000),
    )..repeat();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _applySpeedForState(widget.state);
  }

  @override
  void didUpdateWidget(KeeVoiceOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _applySpeedForState(widget.state);
    }
  }

  void _applySpeedForState(AssistantState s) {
    switch (s) {
      case AssistantState.idle:
        _pulseController.duration = const Duration(milliseconds: 3000);
        _rotationController.duration = const Duration(milliseconds: 11000);
        _meshController.duration = const Duration(milliseconds: 18000);
        if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
      case AssistantState.listening:
        _pulseController.duration = const Duration(milliseconds: 1100);
        _rotationController.duration = const Duration(milliseconds: 4500);
        _meshController.duration = const Duration(milliseconds: 8000);
      case AssistantState.processing:
        _pulseController.duration = const Duration(milliseconds: 700);
        _rotationController.duration = const Duration(milliseconds: 1800);
        _meshController.duration = const Duration(milliseconds: 3200);
      case AssistantState.speaking:
        _pulseController.duration = const Duration(milliseconds: 900);
        _rotationController.duration = const Duration(milliseconds: 3200);
        _meshController.duration = const Duration(milliseconds: 6000);
      case AssistantState.interrupted:
        _pulseController.duration = const Duration(milliseconds: 380);
        _rotationController.duration = const Duration(milliseconds: 1200);
        _meshController.duration = const Duration(milliseconds: 2400);
      case AssistantState.error:
        _pulseController.duration = const Duration(milliseconds: 1800);
        _rotationController.duration = const Duration(milliseconds: 7000);
        _meshController.duration = const Duration(milliseconds: 14000);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    _meshController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Resolve active colour without any blue/cyan/neon
    final Color activeColor;
    switch (widget.state) {
      case AssistantState.error:
        activeColor = _KeeBrand.errorRose;
      case AssistantState.interrupted:
        activeColor = _KeeBrand.amberWarm;
      case AssistantState.listening:
        activeColor = _KeeBrand.ivoryGlow;
      case AssistantState.processing:
        activeColor = _KeeBrand.champagne;
      case AssistantState.speaking:
      case AssistantState.idle:
        activeColor = _KeeBrand.warmIvory;
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: widget.size * 1.5,
        height: widget.size * 1.5,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _pulseController,
            _rotationController,
            _meshController,
            _waveController,
          ]),
          builder: (_, child) {
            return CustomPaint(
              painter: _KeeOrbPainter(
                state: widget.state,
                soundLevel: widget.soundLevel,
                pulseValue: _pulseController.value,
                rotationAngle: _rotationController.value * 2 * math.pi,
                meshAngle: _meshController.value * 2 * math.pi,
                waveValue: _waveController.value,
                activeColor: activeColor,
              ),
              size: Size(widget.size * 1.5, widget.size * 1.5),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painter — all brand-correct colours, mesh-lines inspired by the Kee logo grid
// ─────────────────────────────────────────────────────────────────────────────
class _KeeOrbPainter extends CustomPainter {
  final AssistantState state;
  final double soundLevel;
  final double pulseValue;
  final double rotationAngle;
  final double meshAngle;
  final double waveValue;
  final Color activeColor;

  const _KeeOrbPainter({
    required this.state,
    required this.soundLevel,
    required this.pulseValue,
    required this.rotationAngle,
    required this.meshAngle,
    required this.waveValue,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width * 0.28;

    // ── 1. Outer ambient glow halo ────────────────────────────────────────────
    final glowRadius = baseRadius * (1.05 + 0.14 * pulseValue);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          activeColor.withValues(alpha: state == AssistantState.idle ? 0.18 : 0.38),
          _KeeBrand.champagne.withValues(alpha: 0.07),
          Colors.transparent,
        ],
        stops: const [0.25, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: glowRadius * 1.6));
    canvas.drawCircle(center, glowRadius * 1.6, glowPaint);

    // ── 2. Sound-reactive ripple rings (listening / speaking) ─────────────────
    if (state == AssistantState.listening || state == AssistantState.speaking) {
      final amp = state == AssistantState.listening
          ? (0.18 + soundLevel * 0.82)
          : (0.28 + 0.42 * math.sin(waveValue * 2 * math.pi).abs());

      for (final factor in [1.12 + 0.22 * amp, 1.28 + 0.32 * amp]) {
        canvas.drawCircle(
          center,
          baseRadius * factor,
          Paint()
            ..color = activeColor.withValues(alpha: 0.14 * amp)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    // ── 3. Rotating mesh-line grid (Kee logo inspiration) ────────────────────
    _drawMeshGrid(canvas, center, baseRadius);

    // ── 4. Orbital ring ───────────────────────────────────────────────────────
    _drawOrbitalRing(canvas, center, baseRadius);

    // ── 5. Processing orbit particles — warm grey dots, no blue ──────────────
    if (state == AssistantState.processing) {
      final pPaint = Paint()
        ..color = _KeeBrand.champagne.withValues(alpha: 0.9)
        ..style = PaintingStyle.fill;
      for (int i = 0; i < 4; i++) {
        final a = rotationAngle + i * math.pi / 2;
        final d = baseRadius * 1.26;
        canvas.drawCircle(
          Offset(center.dx + d * math.cos(a), center.dy + d * math.sin(a)),
          3.2,
          pPaint,
        );
      }
      // Smaller counter-orbit
      final pPaint2 = Paint()
        ..color = _KeeBrand.softGrey.withValues(alpha: 0.6)
        ..style = PaintingStyle.fill;
      for (int i = 0; i < 6; i++) {
        final a = -meshAngle + i * math.pi / 3;
        final d = baseRadius * 1.08;
        canvas.drawCircle(
          Offset(center.dx + d * math.cos(a), center.dy + d * math.sin(a)),
          2.0,
          pPaint2,
        );
      }
    }

    // ── 6. Main orb sphere body ───────────────────────────────────────────────
    final sphereRadius = baseRadius * (0.94 + 0.06 * pulseValue);
    final sphereGradient = RadialGradient(
      center: Alignment(
        -0.3 * math.cos(rotationAngle * 0.4),
        -0.3 * math.sin(rotationAngle * 0.4),
      ),
      colors: [
        activeColor.withValues(alpha: 0.92),
        _KeeBrand.champagne.withValues(alpha: 0.55),
        _KeeBrand.coreDeep,
        _KeeBrand.obsidian,
      ],
      stops: const [0.0, 0.35, 0.72, 1.0],
    ).createShader(Rect.fromCircle(center: center, radius: sphereRadius));

    canvas.drawCircle(
      center,
      sphereRadius,
      Paint()
        ..shader = sphereGradient
        ..style = PaintingStyle.fill,
    );

    // ── 7. Specular warm-ivory highlight ──────────────────────────────────────
    final hlOffset = Offset(
      center.dx - sphereRadius * 0.26,
      center.dy - sphereRadius * 0.26,
    );
    canvas.drawCircle(
      hlOffset,
      sphereRadius * 0.21,
      Paint()
        ..color = _KeeBrand.ivoryGlow.withValues(alpha: 0.26 + 0.10 * pulseValue)
        ..style = PaintingStyle.fill,
    );

    // ── 8. Listening: bright ivory core pulse ─────────────────────────────────
    if (state == AssistantState.listening) {
      canvas.drawCircle(
        center,
        sphereRadius * (0.28 + 0.12 * pulseValue),
        Paint()
          ..color = _KeeBrand.ivoryGlow.withValues(alpha: 0.55 + 0.3 * pulseValue)
          ..style = PaintingStyle.fill,
      );
    }

    // ── 9. Interrupted edge flash ─────────────────────────────────────────────
    if (state == AssistantState.interrupted) {
      canvas.drawCircle(
        center,
        sphereRadius * 1.06,
        Paint()
          ..color = _KeeBrand.ivoryGlow.withValues(alpha: 0.40)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5,
      );
    }
  }

  // ── Mesh grid: two overlapping rotated grids clipped to the orb ─────────────
  void _drawMeshGrid(Canvas canvas, Offset center, double baseRadius) {
    final meshRadius = baseRadius * 1.0;
    final clipPath = Path()..addOval(Rect.fromCircle(center: center, radius: meshRadius));

    // Outer mesh halo extends slightly beyond the sphere
    final haloRadius = baseRadius * 1.22;
    final haloPath = Path()..addOval(Rect.fromCircle(center: center, radius: haloRadius));

    final meshPaint = Paint()
      ..color = _KeeBrand.meshLine.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;

    // ---- Inner mesh (clipped inside sphere) ----
    canvas.save();
    canvas.clipPath(clipPath);
    _drawRotatedGrid(canvas, center, meshRadius, rotationAngle, meshPaint);
    _drawRotatedGrid(canvas, center, meshRadius, -meshAngle * 0.6, meshPaint);
    canvas.restore();

    // ---- Outer halo mesh (outside sphere, faded) ----
    final haloPaint = Paint()
      ..color = _KeeBrand.meshLine.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    canvas.save();
    canvas.clipPath(haloPath);
    // Exclude inner sphere from halo
    final haloOnly = Path.combine(
      PathOperation.difference,
      haloPath,
      clipPath,
    );
    canvas.clipPath(haloOnly);
    _drawRotatedGrid(canvas, center, haloRadius, meshAngle * 0.3, haloPaint);
    canvas.restore();
  }

  void _drawRotatedGrid(Canvas canvas, Offset center, double radius, double angle, Paint paint) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    const spacing = 14.0;
    final extent = radius * 1.1;
    final lines = (extent / spacing).ceil() + 1;

    for (int i = -lines; i <= lines; i++) {
      final d = i * spacing;
      canvas.drawLine(Offset(d, -extent), Offset(d, extent), paint);
      canvas.drawLine(Offset(-extent, d), Offset(extent, d), paint);
    }

    canvas.restore();
  }

  // ── Single thin orbital ring ─────────────────────────────────────────────────
  void _drawOrbitalRing(Canvas canvas, Offset center, double baseRadius) {
    final ringRadius = baseRadius * 1.16;
    final ringPaint = Paint()
      ..color = _KeeBrand.champagne.withValues(alpha: 0.28 + 0.12 * pulseValue)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotationAngle * 0.35);
    // Slight ellipse tilt for depth
    canvas.scale(1.0, 0.36);
    canvas.drawCircle(Offset.zero, ringRadius, ringPaint);
    canvas.restore();

    // Second ring, counter-rotating
    final ring2Paint = Paint()
      ..color = _KeeBrand.softGrey.withValues(alpha: 0.16 + 0.08 * pulseValue)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-meshAngle * 0.25 + math.pi / 4);
    canvas.scale(0.36, 1.0);
    canvas.drawCircle(Offset.zero, ringRadius * 0.95, ring2Paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _KeeOrbPainter old) {
    return old.state != state ||
        old.soundLevel != soundLevel ||
        old.pulseValue != pulseValue ||
        old.rotationAngle != rotationAngle ||
        old.meshAngle != meshAngle ||
        old.waveValue != waveValue ||
        old.activeColor != activeColor;
  }
}
