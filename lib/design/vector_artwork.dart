import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Bundled path-based illustrations. No embedded raster images or network I/O.
class SpaceArtwork extends StatelessWidget {
  final String name;
  final double? width;
  final double? height;
  final BoxFit fit;

  const SpaceArtwork(
    this.name, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/illustrations/vector/$name.svg',
    width: width,
    height: height,
    fit: fit,
    excludeFromSemantics: true,
  );
}
