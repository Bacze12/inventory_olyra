import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Pantalla de bienvenida animada que se muestra sobre la app al arrancar.
///
/// Fondo blanco. Una onda verde "pulsa": empieza cubriendo toda la pantalla y
/// confluye hacia el centro hasta desaparecer; entonces aparecen anillos
/// pulsantes y el logo de la app hace un fundido con leve rebote. Al terminar
/// se funde a transparente dejando ver la aplicación ya cargada.
class AnimatedAppSplash extends StatefulWidget {
  const AnimatedAppSplash({
    super.key,
    required this.child,
    required this.logo,
  });

  /// Contenido real de la app (se muestra debajo del splash).
  final Widget child;

  /// Logotipo mostrado al final de la animación.
  final Widget logo;

  @override
  State<AnimatedAppSplash> createState() => _AnimatedAppSplashState();
}

class _AnimatedAppSplashState extends State<AnimatedAppSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// La animación puede empezar apenas fluyen [_startAfterFrames] frames
  /// (dispositivo rápido) o tras [_fallbackDelay] como respaldo garantizado
  /// (arranque lento o pantalla estática sin frames nuevos). Mientras tanto la
  /// onda queda en verde pleno cubriendo la carga de la app.
  int _frames = 0;
  Timer? _fallback;

  static const int _startAfterFrames = 28;
  static const Duration _fallbackDelay = Duration(milliseconds: 1600);

  void _watchFrames() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _frames++;
      if (_frames >= _startAfterFrames) {
        _startAnimation();
      } else {
        _watchFrames();
      }
    });
  }

  void _startAnimation() {
    _fallback?.cancel();
    _fallback = null;
    if (mounted && !_controller.isAnimating) {
      _controller.forward();
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {});
      }
    });
    _fallback = Timer(_fallbackDelay, _startAnimation);
    _watchFrames();
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.isCompleted) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final overall = t < 0.84 ? 1.0 : _clamp01((1.0 - (t - 0.84) / 0.16));
        final logoIn =
            Curves.easeOutBack.transform(_clamp01((t - 0.55) / 0.25));
        final logoOpacity = overall * logoIn;
        final logoScale = 0.5 + 0.5 * logoIn;
        return Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            IgnorePointer(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(
                    opacity: overall,
                    child: CustomPaint(
                      painter: _SplashPainter(progress: t),
                    ),
                  ),
                  Opacity(
                    opacity: logoOpacity,
                    child: Center(
                      child: Transform.scale(
                        scale: logoScale,
                        child: widget.logo,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static double _clamp01(double value) => value.clamp(0.0, 1.0).toDouble();
}

/// Pinta la onda verde que cubre la pantalla y converge al centro, seguida de
/// anillos de "pulsación" que se expanden desde el centro.
class _SplashPainter extends CustomPainter {
  const _SplashPainter({required this.progress});

  /// Progreso global de la animación (0..1).
  final double progress;

  static const Color _green = Color(0xFF16A34A);

  static double _clamp01(double value) => value.clamp(0.0, 1.0).toDouble();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final cover = math.sqrt(size.width * size.width + size.height * size.height);

    final shrink =
        Curves.easeInOutCubic.transform(_clamp01((progress - 0.05) / 0.55));
    if (shrink < 1.0) {
      final greenR = cover * (1 - shrink);
      final alpha = (1 - shrink) * 0.95;
      if (greenR > 0.5 || alpha > 0.01) {
        canvas.drawCircle(
          center,
          math.max(greenR, 0),
          Paint()..color = _green.withValues(alpha: alpha.clamp(0.0, 1.0)),
        );
      }
    }

    for (var i = 0; i < 3; i++) {
      final local = _clamp01((progress - (0.42 + i * 0.09)) / 0.34);
      if (local <= 0 || local >= 1) continue;
      final ringR = 8 + local * cover * 0.85;
      final ringAlpha = (1 - local) * 0.55;
      canvas.drawCircle(
        center,
        ringR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _green.withValues(alpha: ringAlpha.clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SplashPainter oldDelegate) =>
      oldDelegate.progress != progress;
}