import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps Android status/navigation bars consistent with the visible page.
SystemUiOverlayStyle spaceSystemUiStyle(
  BuildContext context, {
  Color? backgroundColor,
}) {
  final theme = Theme.of(context);
  final dark = theme.brightness == Brightness.dark;
  return (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
      .copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor:
            backgroundColor ?? theme.scaffoldBackgroundColor,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      );
}
