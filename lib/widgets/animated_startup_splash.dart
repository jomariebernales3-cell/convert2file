import 'package:flutter/material.dart';

class AnimatedStartupSplash extends StatefulWidget {
  final Object? error;
  final Future<void> Function() onRetry;

  const AnimatedStartupSplash({
    super.key,
    this.error,
    required this.onRetry,
  });

  @override
  State<AnimatedStartupSplash> createState() => _AnimatedStartupSplashState();
}

class _AnimatedStartupSplashState extends State<AnimatedStartupSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _arcController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  bool _retrying = false;

  @override
  void dispose() {
    _arcController.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    setState(() => _retrying = true);
    await widget.onRetry();
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final background = isLight ? Colors.white : Colors.black;
    final track = isLight ? const Color(0xFFE0E0E0) : const Color(0xFF3A3A3A);
    final arc = isLight ? Colors.black : Colors.white;
    final logo = isLight
        ? 'assets/images/dbz_logo_badge.png'
        : 'assets/images/dbz_logo_badge_light.png';

    return Scaffold(
      backgroundColor: background,
      body: SizedBox.expand(
        child: Stack(
          alignment: Alignment.center,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final diameter = (constraints.maxWidth * 0.46)
                    .clamp(160.0, 260.0)
                    .toDouble();
                return SizedBox.square(
                  dimension: diameter,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _arcController,
                        builder: (context, _) => CustomPaint(
                          size: Size.square(diameter),
                          painter: _LoadingArcPainter(
                            progress: _arcController.value,
                            trackColor: track,
                            arcColor: arc,
                          ),
                        ),
                      ),
                      SizedBox.square(
                        dimension: diameter * 0.64,
                        child: Image.asset(logo, fit: BoxFit.contain),
                      ),
                    ],
                  ),
                );
              },
            ),
            if (widget.error != null)
              Positioned(
                left: 24,
                right: 24,
                bottom: 36,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Could not finish starting Convert2File.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isLight ? Colors.black87 : Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: _retrying ? null : _retry,
                      child: Text(_retrying ? 'Retrying…' : 'Try again'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LoadingArcPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color arcColor;

  const _LoadingArcPainter({
    required this.progress,
    required this.trackColor,
    required this.arcColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const pi = 3.141592653589793;
    final strokeWidth = size.width * 0.065;
    final circle = (Offset.zero & size).deflate(strokeWidth / 2);
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final arcPaint = Paint()
      ..color = arcColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawOval(circle, trackPaint);
    canvas.drawArc(
      circle,
      (-pi / 2) + progress * 2 * pi,
      1.25,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _LoadingArcPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.arcColor != arcColor;
}
