import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Yeşil karakter: parmak/işaretçiyi takip eden gözler
///
/// Kullanım:
/// ```dart
/// const GreenEyesCharacter(size: 180)
/// ```
class GreenEyesCharacter extends StatefulWidget {
  final double size;
  final Color outerColor;
  final Color midColor;
  final Color innerColor;

  const GreenEyesCharacter({
    super.key,
    this.size = 160,
    this.outerColor = const Color.fromARGB(255, 40, 97, 38),
    this.midColor = const Color.fromARGB(255, 41, 110, 43),
    this.innerColor = const Color.fromARGB(255, 51, 119, 57),
  });

  @override
  State<GreenEyesCharacter> createState() => _GreenEyesCharacterState();
}

class _GreenEyesCharacterState extends State<GreenEyesCharacter> {
  /// Son dokunma/hover noktası (widget koordinatlarında). Null ise gözler ortaya bakar.
  Offset? _lastPointer;

  void _updatePointer(Offset localPos) {
    setState(() => _lastPointer = localPos);
  }

  void _resetPointer() {
    setState(() => _lastPointer = null);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;

    return SizedBox(
      width: size,
      height: size,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _updatePointer(e.localPosition),
        onPointerMove: (e) => _updatePointer(e.localPosition),
        onPointerHover: (e) => _updatePointer(e.localPosition), // desktop/web
        onPointerUp: (_) => _resetPointer(),
        onPointerCancel: (_) => _resetPointer(),
        child: RepaintBoundary(
          child: _GreenEyesCanvas(
            outer: widget.outerColor,
            mid: widget.midColor,
            inner: widget.innerColor,
            lookAt: _lastPointer,
          ),
        ),
      ),
    );
  }
}

class _GreenEyesCanvas extends StatelessWidget {
  final Color outer;
  final Color mid;
  final Color inner;
  final Offset? lookAt;
  const _GreenEyesCanvas({
    required this.outer,
    required this.mid,
    required this.inner,
    required this.lookAt,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GreenEyesPainter(
        outer: outer,
        mid: mid,
        inner: inner,
        lookAt: lookAt,
      ),
    );
  }
}

class _GreenEyesPainter extends CustomPainter {
  final Color outer;
  final Color mid;
  final Color inner;
  final Offset? lookAt; // local coordinates of pointer

  _GreenEyesPainter({
    required this.outer,
    required this.mid,
    required this.inner,
    required this.lookAt,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Arka plan katmanları
    final pOuter = Paint()..color = outer;
    final pMid = Paint()..color = mid.withOpacity(0.9);
    final pInner = Paint()..color = inner.withOpacity(0.9);

    canvas.drawCircle(center, radius, pOuter);
    canvas.drawCircle(center, radius * 0.82, pMid);
    canvas.drawCircle(center, radius * 0.64, pInner);

    // Göz parametreleri
    final eyeRadius = radius * 0.18;
    final pupilRadius = eyeRadius * 0.38;

    final leftEyeCenter = Offset(
      center.dx - eyeRadius * 1.1,
      center.dy - eyeRadius * 0.2,
    );
    final rightEyeCenter = Offset(
      center.dx + eyeRadius * 1.1,
      center.dy - eyeRadius * 0.2,
    );

    // Bakış yönü hesabı (yalnızca gözler hareket etsin)
    Offset dir;
    if (lookAt != null) {
      dir = (lookAt! - center);
      if (dir.distance > 1e-3) {
        dir = dir / dir.distance; // normalize
      } else {
        dir = const Offset(0, -1);
      }
    } else {
      dir = const Offset(0, -1); // varsayılan hafif yukarı
    }

    // Pupillerin kayabileceği maksimum mesafe (sabit)
    final maxOffset = eyeRadius * 0.42;
    final pupilOffset = Offset(
      (dir.dx.clamp(-1.0, 1.0)) * maxOffset,
      (dir.dy.clamp(-1.0, 1.0)) * maxOffset,
    );

    final paintWhite = Paint()..color = const Color(0xFFFFFFFF);
    final paintBlack = Paint()..color = const Color(0xFF0F0F0F);

    // Göz beyazları
    canvas.drawCircle(leftEyeCenter, eyeRadius, paintWhite);
    canvas.drawCircle(rightEyeCenter, eyeRadius, paintWhite);

    // Pupiller
    canvas.drawCircle(leftEyeCenter + pupilOffset, pupilRadius, paintBlack);
    canvas.drawCircle(rightEyeCenter + pupilOffset, pupilRadius, paintBlack);
  }

  @override
  bool shouldRepaint(covariant _GreenEyesPainter old) {
    // lookAt değiştikçe repaint
    return old.lookAt != lookAt ||
        old.outer != outer ||
        old.mid != mid ||
        old.inner != inner;
  }
}

/// Public wrapper to expose the interactive empty-following character
class FollowEmptyInteractive extends StatelessWidget {
  const FollowEmptyInteractive({super.key});

  @override
  Widget build(BuildContext context) => const _EmptyMessagesInteractive();
}

class _ForestFace extends StatelessWidget {
  final double offsetX;
  final double offsetY;
  const _ForestFace({this.offsetX = 0, this.offsetY = 0});

  @override
  Widget build(BuildContext context) {
    const base = Color(0xFF1B5E20); // forest green
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _ring(140, base.withOpacity(0.90)),
          _ring(112, base.withOpacity(0.75)),
          _ring(88, base.withOpacity(0.55)),
          _ring(64, base.withOpacity(0.35)),
          _ring(44, base.withOpacity(0.20)),
          Positioned(left: 38, top: 54, child: _eye(offsetX, offsetY)),
          Positioned(right: 38, top: 54, child: _eye(offsetX, offsetY)),
        ],
      ),
    );
  }

  static Widget _ring(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  static Widget _eye(double offsetX, double offsetY) {
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment(offsetX / 10, offsetY / 10),
        child: Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: Colors.black87,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _EmptyMessagesInteractive extends StatefulWidget {
  const _EmptyMessagesInteractive();
  @override
  State<_EmptyMessagesInteractive> createState() =>
      _EmptyMessagesInteractiveState();
}

class _EmptyMessagesInteractiveState extends State<_EmptyMessagesInteractive> {
  double _offsetX = 0;
  double _offsetY = -10; // default: look slightly upward

  void _updateOffsets(Offset p, Size size) {
    // Normalize position to [-1,1] range around the center of the available area
    final cx = size.width / 2;
    final cy = size.height / 2;
    double nx = ((p.dx - cx) / (cx.abs())).clamp(-1.0, 1.0);
    double ny = ((p.dy - cy) / (cy.abs())).clamp(-1.0, 1.0);

    const max = 10.0; // max eye travel in our _ForestFace alignment mapping
    setState(() {
      _offsetX = nx * max;
      _offsetY = ny * max;
    });
  }

  void _resetUp() {
    setState(() {
      _offsetX = 0;
      _offsetY = -10; // back to looking up in empty state
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanDown: (details) => _updateOffsets(details.localPosition, size),
          onPanUpdate: (details) => _updateOffsets(details.localPosition, size),
          onPanEnd: (_) => _resetUp(),
          onTapDown: (details) => _updateOffsets(details.localPosition, size),
          onTapUp: (_) => _resetUp(),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ForestFace(offsetX: _offsetX, offsetY: _offsetY),
                const SizedBox(height: 12),
                const Text(
                  'Birilerini takip etmelisin',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color.fromARGB(255, 124, 131, 116),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
