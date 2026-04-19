import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Simple data model for a watchlist movie
class WatchlistMovie {
  final String title;
  final String? posterUrl;
  final String? id;
  const WatchlistMovie({required this.title, this.posterUrl,this.id,});
}

/// A fortune-style wheel for picking a movie from a watchlist.
///
/// Usage:
/// ```dart
/// WatchlistWheel(
///   items: movies, // List<WatchlistMovie>
///   onChosen: (m) => print('Seçilen: ${m.title}')
/// )
/// ```
class WatchlistWheel extends StatefulWidget {
  final List<WatchlistMovie> items;
  final void Function(WatchlistMovie chosen)? onChosen;
  final double size;
  final int? randomSeed;
  final bool showCenterPreview;

  const WatchlistWheel({
    super.key,
    required this.items,
    this.onChosen,
    this.size = 320,
    this.randomSeed,
    this.showCenterPreview = true,
  });

  @override
  State<WatchlistWheel> createState() => _WatchlistWheelState();
}

class _WatchlistWheelState extends State<WatchlistWheel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  double _angle = 0.0; // current rotation angle (radians)
  bool _spinning = false;
  late math.Random _rng;

  @override
  void initState() {
    super.initState();
    _rng = math.Random(widget.randomSeed);
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutQuart);
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _spinning = false);
        _emitResult();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _emitResult() {
    if (widget.items.isEmpty) return;
    final idx = _indexForCurrentAngle(widget.items.length, _angle);
    widget.onChosen?.call(widget.items[idx]);
  }

  /// Spin the wheel with a bit of randomness.
  void spin() {
    if (widget.items.length <= 1 || _spinning) return;
    setState(() => _spinning = true);

    // Current normalized angle
    final start = _angle;

    // Target: 5–8 full turns plus an offset to land on a random slice
    final fullTurns = 5 + _rng.nextInt(4); // 5..8
    final slice = (2 * math.pi) / widget.items.length;
    final offsetWithinSlice =
        _rng.nextDouble() * (slice * 0.9) + slice * 0.05; // avoid edges

    // Choose a random target slice index different from current selection
    final currentIdx = _indexForCurrentAngle(widget.items.length, start);
    int targetIdx = _rng.nextInt(widget.items.length);
    if (widget.items.length > 1 && targetIdx == currentIdx) {
      targetIdx = (targetIdx + 1) % widget.items.length;
    }

    // We want the pointer at 12 o'clock to land in the center of target slice.
    // Angle increases clockwise in Transform.rotate (positive is clockwise),
    // so to move the wheel under a fixed pointer we rotate by +(turns*2π + delta).
    final pointerAngle = -math.pi / 2; // top
    final targetAngleCenter =
        targetIdx * slice + slice / 2.0; // in wheel coordinates
    final delta = _normalizeAngle(
      targetAngleCenter - pointerAngle,
    ); // how much to rotate from 0

    final end = start + fullTurns * 2 * math.pi + delta + offsetWithinSlice;

    final tween = Tween<double>(begin: start, end: end);
    _ctrl.reset();
    _ctrl.addListener(() {
      setState(() {
        _angle = tween.evaluate(_anim);
      });
    });
    _ctrl.forward();
  }

  static double _normalizeAngle(double a) {
    final twoPi = 2 * math.pi;
    a = a % twoPi;
    if (a < 0) a += twoPi;
    return a;
  }

  static int _indexForCurrentAngle(int itemCount, double angle) {
    if (itemCount == 0) return 0;
    // Pointer is at 12 o'clock. Convert current wheel angle to a slice index under the pointer.
    final twoPi = 2 * math.pi;
    final slice = twoPi / itemCount;
    final normalized = _normalize(angle);
    // Which angle sits under the pointer? We invert rotation because wheel rotates under fixed pointer
    final pointer = _normalize(-normalized - math.pi / 2);
    int idx = (pointer / slice).floor();
    if (idx < 0) idx = 0;
    if (idx >= itemCount) idx = itemCount - 1;
    return idx;
  }

  static double _normalize(double a) {
    final twoPi = 2 * math.pi;
    a = a % twoPi;
    if (a < 0) a += twoPi;
    return a;
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final size = widget.size;
    final selectedIdx = items.isNotEmpty
        ? _indexForCurrentAngle(items.length, _angle)
        : -1;
    final selected = (selectedIdx >= 0) ? items[selectedIdx] : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // The wheel
            SizedBox(
              width: size,
              height: size,
              child: Transform.rotate(
                angle: _angle,
                child: CustomPaint(painter: _WheelPainter(items: items)),
              ),
            ),

            // Center preview of selected item
            if (widget.showCenterPreview && selected != null)
              _CenterBadge(movie: selected),

            // Pointer at top (12 o'clock)
            Positioned(top: 0, child: _Pointer()),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: (items.length > 1 && !_spinning) ? spin : null,
              icon: const Icon(Icons.casino),
              label: const Text('Çevir'),
            ),
            const SizedBox(width: 12),
            if (selected != null)
              Text(
                selected.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
          ],
        ),
      ],
    );
  }
}

class _WheelPainter extends CustomPainter {
  final List<WatchlistMovie> items;
  _WheelPainter({required this.items});

  @override
  void paint(Canvas canvas, Size size) {
    final n = items.isNotEmpty ? items.length : 1;
    final sliceAngle = (2 * math.pi) / n;
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2.0;

    final bg = Paint()..color = Colors.grey.withOpacity(0.08);
    canvas.drawCircle(center, radius, bg);

    final paint = Paint()..style = PaintingStyle.fill;
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );

    for (int i = 0; i < n; i++) {
      final start = i * sliceAngle;
      // Alternate slice colors
      final c = i.isEven
          ? const Color(0xFF4CAF50).withOpacity(0.85) // green-ish
          : const Color(0xFF2E7D32).withOpacity(0.85); // darker green
      paint.color = c;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sliceAngle,
        true,
        paint,
      );

      // Label (movie title)
      final label = items.isNotEmpty ? items[i].title : '—';
      final tpStyle = const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      );
      textPainter.text = TextSpan(text: label, style: tpStyle);
      textPainter.layout(maxWidth: radius * 0.9);

      // Place along the middle radius of the slice
      final theta = start + sliceAngle / 2;
      final r = radius * 0.65;
      final offset = center + Offset(math.cos(theta), math.sin(theta)) * r;

      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.rotate(theta + math.pi / 2);
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );
      canvas.restore();
    }

    // Draw inner circle to make a donut style
    final inner = Paint()..color = Colors.black.withOpacity(0.08);
    canvas.drawCircle(center, radius * 0.35, inner);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) =>
      oldDelegate.items != items;
}

class _Pointer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(blurRadius: 6, color: Colors.black26, offset: Offset(0, 2)),
        ],
      ),
    );
  }
}

class _CenterBadge extends StatelessWidget {
  final WatchlistMovie movie;
  const _CenterBadge({required this.movie});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 12,
            color: Colors.black26,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if ((movie.posterUrl ?? '').isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                movie.posterUrl!,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(
                  width: 80,
                  height: 80,
                  child: ColoredBox(color: Colors.black12),
                ),
              ),
            )
          else
            const SizedBox(
              width: 80,
              height: 80,
              child: ColoredBox(color: Colors.black12),
            ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              movie.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}
