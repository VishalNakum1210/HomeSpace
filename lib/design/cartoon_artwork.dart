import 'package:flutter/material.dart';

import 'space_symbols.dart';

/// Decorative artwork is excluded from semantics; adjacent text carries meaning.
class MemoryGarden extends StatelessWidget {
  const MemoryGarden({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: 96,
      width: double.infinity,
      child: Image.asset(
        'assets/illustrations/memory-garden.png',
        fit: BoxFit.contain,
        alignment: Alignment.bottomCenter,
        filterQuality: FilterQuality.medium,
      ),
    ),
  );
}

class AlbumSticker extends StatelessWidget {
  const AlbumSticker({super.key});

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: CustomPaint(size: Size(98, 82), painter: _AlbumStickerPainter()),
  );
}

class _AlbumStickerPainter extends CustomPainter {
  const _AlbumStickerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 98, size.height / 82);
    final paint = Paint()..color = const Color(0xFFF0E2FF);
    canvas.drawOval(const Rect.fromLTWH(6, 46, 90, 34), paint);
    paint.color = const Color(0xFF81CE4C);
    canvas.save();
    canvas.translate(14, 59);
    canvas.rotate(-.45);
    canvas.drawOval(const Rect.fromLTWH(-5, -21, 10, 24), paint);
    canvas.restore();
    canvas.save();
    canvas.translate(39, 31);
    canvas.rotate(-.15);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-19, -25, 42, 53),
        const Radius.circular(6),
      ),
      paint..color = Colors.white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-14, -20, 32, 36),
        const Radius.circular(3),
      ),
      paint..color = const Color(0xFFAFE4FF),
    );
    canvas.drawPath(
      Path()
        ..moveTo(-14, 13)
        ..lineTo(-2, -5)
        ..lineTo(8, 5)
        ..lineTo(18, -2)
        ..lineTo(18, 16)
        ..lineTo(-14, 16)
        ..close(),
      paint..color = const Color(0xFF64B7D3),
    );
    canvas.restore();
    canvas.save();
    canvas.translate(66, 46);
    canvas.rotate(.18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-23, -26, 46, 53),
        const Radius.circular(7),
      ),
      paint..color = const Color(0xFF8D44D9),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-25, -29, 44, 52),
        const Radius.circular(7),
      ),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFCB96FF), Color(0xFFA560F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(const Rect.fromLTWH(-25, -29, 44, 52)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-17, -18, 28, 29),
        const Radius.circular(3),
      ),
      paint..color = const Color(0xFFF0DEFF),
    );
    canvas.drawPath(
      Path()
        ..moveTo(-14, 7)
        ..lineTo(-5, -6)
        ..lineTo(1, 0)
        ..lineTo(5, -4)
        ..lineTo(9, 7)
        ..close(),
      paint..color = const Color(0xFFAB68EB),
    );
    canvas.drawCircle(const Offset(5, -11), 3, paint);
    canvas.restore();
    paint
      ..color = const Color(0xFFC69AFF)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(6, 17), const Offset(11, 22), paint);
    canvas.drawLine(const Offset(2, 29), const Offset(8, 30), paint);
  }

  @override
  bool shouldRepaint(_AlbumStickerPainter oldDelegate) => false;
}

class HouseGreeting extends StatelessWidget {
  const HouseGreeting({super.key});

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: SizedBox(
      width: 82,
      height: 82,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _SunraysPainter())),
          Center(child: SpaceHouse(size: 66)),
        ],
      ),
    ),
  );
}

class _SunraysPainter extends CustomPainter {
  const _SunraysPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFC857)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(8, 18), const Offset(13, 23), paint);
    canvas.drawLine(const Offset(22, 4), const Offset(24, 11), paint);
    canvas.drawLine(const Offset(65, 8), const Offset(61, 14), paint);
    canvas.drawLine(const Offset(74, 29), const Offset(79, 27), paint);
  }

  @override
  bool shouldRepaint(_SunraysPainter oldDelegate) => false;
}
