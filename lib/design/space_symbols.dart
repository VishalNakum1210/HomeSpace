import 'package:flutter/material.dart';

import 'space_theme.dart';

/// Small, softly shaded symbols for the floating clay navigation dock.
class ClayNavigationSymbol extends StatelessWidget {
  final SpacePage page;
  const ClayNavigationSymbol(this.page, {super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: const Size.square(31),
      painter: _ClayNavigationPainter(page),
    ),
  );
}

class _ClayNavigationPainter extends CustomPainter {
  final SpacePage page;
  const _ClayNavigationPainter(this.page);

  void _surface(Canvas canvas, Path path, Color light, Color shade) {
    canvas.drawShadow(path, shade.withValues(alpha: .35), 2, false);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, shade],
        ).createShader(path.getBounds()),
    );
    canvas.save();
    canvas.clipPath(path);
    canvas.drawOval(
      path.getBounds().translate(-4, -path.getBounds().height * .65),
      Paint()
        ..color = Colors.white.withValues(alpha: .18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.restore();
  }

  Path _tile(Rect rect, double radius) =>
      Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 32, size.height / 32);
    switch (page) {
      case SpacePage.photos:
        _surface(
          canvas,
          _tile(const Rect.fromLTWH(3, 3, 26, 26), 7),
          const Color(0xFF8FF2A4),
          const Color(0xFF31C65A),
        );
        final hills = Path()
          ..moveTo(6, 23)
          ..lineTo(12, 14)
          ..quadraticBezierTo(13, 12.5, 14, 14)
          ..lineTo(18, 19)
          ..lineTo(21, 16)
          ..quadraticBezierTo(22, 15, 23, 17)
          ..lineTo(26, 23)
          ..quadraticBezierTo(27, 26, 24, 26)
          ..lineTo(8, 26)
          ..quadraticBezierTo(5, 26, 6, 23)
          ..close();
        _surface(
          canvas,
          hills,
          const Color(0xFF28BC4D),
          const Color(0xFF119A39),
        );
        _surface(
          canvas,
          Path()..addOval(const Rect.fromLTWH(19, 7, 7, 7)),
          const Color(0xFF35CD52),
          const Color(0xFF139C36),
        );
      case SpacePage.collections:
        _surface(
          canvas,
          _tile(const Rect.fromLTWH(2, 3, 23, 24), 6),
          const Color(0xFFD7A1FF),
          const Color(0xFF9951E8),
        );
        _surface(
          canvas,
          _tile(const Rect.fromLTWH(8, 8, 23, 23), 6),
          const Color(0xFFBE83FF),
          const Color(0xFF803CE1),
        );
      case SpacePage.profile:
        _surface(
          canvas,
          Path()..addOval(const Rect.fromLTWH(9, 2, 14, 14)),
          const Color(0xFFFFC36A),
          const Color(0xFFFF8B19),
        );
        final body = Path()
          ..moveTo(3, 27)
          ..cubicTo(3, 14, 29, 14, 29, 27)
          ..quadraticBezierTo(29, 30, 25, 30)
          ..lineTo(7, 30)
          ..quadraticBezierTo(3, 30, 3, 27)
          ..close();
        _surface(
          canvas,
          body,
          const Color(0xFFFFBD61),
          const Color(0xFFFF8616),
        );
    }
  }

  @override
  bool shouldRepaint(_ClayNavigationPainter oldDelegate) =>
      oldDelegate.page != page;
}

class SpaceSymbol extends StatelessWidget {
  final SpacePage page;
  final double size;
  const SpaceSymbol(this.page, {super.key, this.size = 30});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _PagePainter(
        page,
        Theme.of(context).brightness == Brightness.dark
            ? page.darkColor
            : page.color,
      ),
    ),
  );
}

class SpaceHouse extends StatelessWidget {
  final double size;
  const SpaceHouse({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(size: Size.square(size), painter: const _HousePainter()),
  );
}

class _PagePainter extends CustomPainter {
  final SpacePage page;
  final Color color;
  const _PagePainter(this.page, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 32, size.height / 32);
    final paint = Paint()..color = color;
    final edge = Color.lerp(color, Colors.black, .15)!;
    switch (page) {
      case SpacePage.photos:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(2, 5, 28, 25),
            const Radius.circular(6),
          ),
          paint..color = edge,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(2, 3, 28, 25),
            const Radius.circular(6),
          ),
          paint..color = color,
        );
        canvas.drawCircle(const Offset(10, 10), 3, paint..color = Colors.white);
        final mountains = Path()
          ..moveTo(6, 23)
          ..lineTo(12, 16)
          ..lineTo(16, 20)
          ..lineTo(22, 12)
          ..lineTo(27, 23)
          ..close();
        canvas.drawPath(mountains, paint);
      case SpacePage.collections:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(8, 2, 19, 22),
            const Radius.circular(4),
          ),
          paint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(4, 6, 22, 23),
            const Radius.circular(5),
          ),
          paint..color = edge,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(2, 10, 24, 21),
            const Radius.circular(5),
          ),
          paint..color = color,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(6, 14, 16, 12),
            const Radius.circular(2),
          ),
          paint..color = Colors.white,
        );
        final mountain = Path()
          ..moveTo(7, 24)
          ..lineTo(12, 18)
          ..lineTo(16, 22)
          ..lineTo(19, 19)
          ..lineTo(22, 24)
          ..close();
        canvas.drawPath(mountain, paint..color = color);
        canvas.drawCircle(const Offset(18, 17), 1.5, paint);
      case SpacePage.profile:
        canvas.drawCircle(const Offset(16, 9), 7, paint);
        final shoulders = Path()
          ..moveTo(3, 28)
          ..cubicTo(3, 13, 29, 13, 29, 28)
          ..quadraticBezierTo(29, 31, 26, 31)
          ..lineTo(6, 31)
          ..quadraticBezierTo(3, 31, 3, 28);
        canvas.drawPath(shoulders, paint..color = edge);
        canvas.save();
        canvas.translate(0, -2);
        canvas.drawPath(shoulders, paint..color = color);
        canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PagePainter old) =>
      old.page != page || old.color != color;
}

class _HousePainter extends CustomPainter {
  const _HousePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64, size.height / 64);
    final paint = Paint()..color = const Color(0xFF49AB00);
    final house = Path()
      ..moveTo(10, 29)
      ..lineTo(32, 10)
      ..lineTo(54, 29)
      ..lineTo(54, 55)
      ..quadraticBezierTo(54, 60, 49, 60)
      ..lineTo(15, 60)
      ..quadraticBezierTo(10, 60, 10, 55)
      ..close();
    canvas.drawPath(house, paint);
    canvas.save();
    canvas.translate(0, -3);
    canvas.drawPath(house, paint..color = const Color(0xFF78D919));
    canvas.restore();
    final roof = Path()
      ..moveTo(7, 28)
      ..lineTo(32, 6)
      ..lineTo(57, 28);
    canvas.drawPath(
      roof,
      paint
        ..color = const Color(0xFFD97A00)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 10,
    );
    canvas.save();
    canvas.translate(0, -2);
    canvas.drawPath(roof, paint..color = const Color(0xFFFF9600));
    canvas.restore();
    paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF244500);
    canvas.drawOval(const Rect.fromLTWH(21, 32, 5, 7), paint);
    canvas.drawOval(const Rect.fromLTWH(38, 32, 5, 7), paint);
    final smile = Path()
      ..moveTo(26, 44)
      ..quadraticBezierTo(32, 52, 38, 44)
      ..close();
    canvas.drawPath(smile, paint);
    paint.color = const Color(0xFFFFC857);
    canvas.drawCircle(const Offset(18, 43), 3.5, paint);
    canvas.drawCircle(const Offset(46, 43), 3.5, paint);
  }

  @override
  bool shouldRepaint(_HousePainter old) => false;
}
