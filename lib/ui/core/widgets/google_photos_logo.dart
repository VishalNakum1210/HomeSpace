import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/photos_theme.dart';

class GooglePhotosLogo extends StatelessWidget {
  final double size;

  const GooglePhotosLogo({super.key, this.size = 32.0});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GooglePhotosLogoPainter(),
      ),
    );
  }
}

class _GooglePhotosLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.width / 2;
    final center = Offset(radius, radius);
    final bladeRadius = radius * 0.48;

    // Google Photos pinwheel has 4 semicircles / pill petals centered at quadrant boundaries
    final colors = [
      PhotosColors.googleRed,    // Top
      PhotosColors.googleYellow, // Right
      PhotosColors.googleGreen,  // Bottom
      PhotosColors.googleBlue,   // Left
    ];

    final angles = [
      0.0,
      math.pi / 2,
      math.pi,
      3 * math.pi / 2,
    ];

    for (int i = 0; i < 4; i++) {
      final paint = Paint()
        ..color = colors[i]
        ..isAntiAlias = true
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angles[i]);

      final path = Path();
      // Draw smooth petal starting at center extending outwards
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(0, -bladeRadius, bladeRadius * 1.6, bladeRadius),
        topLeft: Radius.circular(bladeRadius / 2),
        topRight: Radius.circular(bladeRadius / 2),
        bottomRight: Radius.circular(bladeRadius / 2),
        bottomLeft: Radius.zero,
      );
      path.addRRect(rect);
      canvas.drawPath(path, paint);

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
