import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/photos_theme.dart';

class GoogleGIcon extends StatelessWidget {
  final double size;

  const GoogleGIcon({super.key, this.size = 20.0});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GoogleGLogoPainter(),
      ),
    );
  }
}

class _GoogleGLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double center = size.width / 2;
    final double strokeWidth = size.width * 0.21;
    final double radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: Offset(center, center), radius: radius);

    Paint createPaint(Color color) {
      return Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..isAntiAlias = true
        ..strokeCap = StrokeCap.butt;
    }

    // Yellow arc: ~125 deg to 225 deg
    canvas.drawArc(
      rect,
      (125 * math.pi) / 180,
      (100 * math.pi) / 180,
      false,
      createPaint(PhotosColors.googleYellow),
    );

    // Green arc: ~45 deg to 135 deg
    canvas.drawArc(
      rect,
      (45 * math.pi) / 180,
      (90 * math.pi) / 180,
      false,
      createPaint(PhotosColors.googleGreen),
    );

    // Red arc: ~220 deg to 320 deg
    canvas.drawArc(
      rect,
      (220 * math.pi) / 180,
      (100 * math.pi) / 180,
      false,
      createPaint(PhotosColors.googleRed),
    );

    // Blue arc: ~-45 deg to +50 deg
    canvas.drawArc(
      rect,
      (-45 * math.pi) / 180,
      (92 * math.pi) / 180,
      false,
      createPaint(PhotosColors.googleBlue),
    );

    // Blue horizontal crossbar
    final barPaint = Paint()
      ..color = PhotosColors.googleBlue
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final barRect = Rect.fromLTWH(
      center - strokeWidth * 0.2,
      center - strokeWidth / 2,
      radius + strokeWidth / 2,
      strokeWidth,
    );
    canvas.drawRect(barRect, barPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
