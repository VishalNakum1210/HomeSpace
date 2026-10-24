import 'package:flutter/material.dart';

import 'space_symbols.dart';

/// Reuses the original logo with a small photo frame for empty/recovery states.
class HouseStateArt extends StatelessWidget {
  final IconData icon;
  const HouseStateArt({super.key, this.icon = Icons.photo_outlined});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 238,
      height: 126,
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _GardenPainter())),
          const Positioned(left: 42, top: 29, child: SpaceHouse(size: 88)),
          Positioned(
            left: 133,
            top: 21,
            child: Transform.rotate(
              angle: .13,
              child: Container(
                width: 74,
                height: 80,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFD6E4ED), width: 3),
                ),
                child: Icon(icon, color: const Color(0xFF72BDE8), size: 38),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _GardenPainter extends CustomPainter {
  const _GardenPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFD9F3B6);
    canvas.drawOval(const Rect.fromLTWH(8, 100, 224, 22), paint);
    paint.color = const Color(0xFF8BD547);
    canvas.drawOval(const Rect.fromLTWH(17, 78, 12, 30), paint);
    canvas.drawOval(const Rect.fromLTWH(29, 88, 12, 24), paint);
    canvas.drawOval(const Rect.fromLTWH(210, 85, 10, 28), paint);
    paint.color = const Color(0xFFB5E4F9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(13, 29, 34, 10),
        const Radius.circular(6),
      ),
      paint,
    );
    canvas.drawCircle(const Offset(27, 27), 9, paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(198, 10, 24, 8),
        const Radius.circular(5),
      ),
      paint,
    );
    paint
      ..color = const Color(0xFFFFC857)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(64, 15), const Offset(69, 22), paint);
    canvas.drawLine(const Offset(83, 6), const Offset(84, 14), paint);
  }

  @override
  bool shouldRepaint(_GardenPainter oldDelegate) => false;
}

class MemoryStatusBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const MemoryStatusBanner({super.key, required this.message, this.onRetry});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF243844) : const Color(0xFFEAF5FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: dark ? const Color(0xFFA5D8FF) : const Color(0xFF245C86),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: dark ? const Color(0xFFDCEBFF) : const Color(0xFF245C86),
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
