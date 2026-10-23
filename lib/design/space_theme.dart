import 'package:flutter/material.dart';

enum SpacePage {
  photos('Photos'),
  collections('Collections'),
  profile('Profile');

  final String label;
  const SpacePage(this.label);

  Color get color => switch (this) {
    photos => const Color(0xFF58CC02),
    collections => const Color(0xFFA560F5),
    profile => const Color(0xFFFF9600),
  };

  Color get darkColor => switch (this) {
    photos => const Color(0xFF8BE84E),
    collections => const Color(0xFFC39AFF),
    profile => const Color(0xFFFFB557),
  };
}

Duration spaceMotion(BuildContext context, [int milliseconds = 220]) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

@immutable
class SpaceStyle extends ThemeExtension<SpaceStyle> {
  final Color accent;
  final Color accentInk;
  final Color accentSoft;
  final Color edge;
  final Color border;
  final Color muted;
  final Color navigationBlue;

  const SpaceStyle({
    required this.accent,
    required this.accentInk,
    required this.accentSoft,
    required this.edge,
    required this.border,
    required this.muted,
    required this.navigationBlue,
  });

  static SpaceStyle of(BuildContext context) =>
      Theme.of(context).extension<SpaceStyle>()!;

  @override
  SpaceStyle copyWith({
    Color? accent,
    Color? accentInk,
    Color? accentSoft,
    Color? edge,
    Color? border,
    Color? muted,
    Color? navigationBlue,
  }) => SpaceStyle(
    accent: accent ?? this.accent,
    accentInk: accentInk ?? this.accentInk,
    accentSoft: accentSoft ?? this.accentSoft,
    edge: edge ?? this.edge,
    border: border ?? this.border,
    muted: muted ?? this.muted,
    navigationBlue: navigationBlue ?? this.navigationBlue,
  );

  @override
  SpaceStyle lerp(covariant SpaceStyle? other, double t) {
    if (other == null) return this;
    return SpaceStyle(
      accent: Color.lerp(accent, other.accent, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      edge: Color.lerp(edge, other.edge, t)!,
      border: Color.lerp(border, other.border, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      navigationBlue: Color.lerp(navigationBlue, other.navigationBlue, t)!,
    );
  }
}

ThemeData spaceTheme(Brightness brightness, SpacePage page) {
  final dark = brightness == Brightness.dark;
  final accent = dark ? page.darkColor : page.color;
  final ink = dark ? const Color(0xFFF2F3F5) : const Color(0xFF171B32);
  final surface = dark ? const Color(0xFF13191F) : const Color(0xFFFFFEFC);
  final card = dark ? const Color(0xFF1D252D) : Colors.white;
  final accentInk = switch (page) {
    SpacePage.photos =>
      dark ? const Color(0xFFB8F393) : const Color(0xFF347000),
    SpacePage.collections =>
      dark ? const Color(0xFFDBC4FF) : const Color(0xFF7035B4),
    SpacePage.profile =>
      dark ? const Color(0xFFFFD196) : const Color(0xFF965000),
  };
  final style = SpaceStyle(
    accent: accent,
    accentInk: accentInk,
    accentSoft: Color.alphaBlend(
      accent.withValues(alpha: dark ? .13 : .10),
      card,
    ),
    edge: switch (page) {
      SpacePage.photos => const Color(0xFF43A000),
      SpacePage.collections => const Color(0xFF8044C7),
      SpacePage.profile => const Color(0xFFD37A00),
    },
    border: dark ? const Color(0xFF39434D) : const Color(0xFFE6E5E1),
    muted: dark ? const Color(0xFFAFB8C4) : const Color(0xFF6A6D76),
    navigationBlue: dark ? const Color(0xFF244E70) : const Color(0xFFCEEAFE),
  );
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
      .copyWith(
        primary: accentInk,
        onPrimary: dark ? const Color(0xFF192125) : Colors.white,
        primaryContainer: style.accentSoft,
        onPrimaryContainer: accentInk,
        secondary: accentInk,
        surface: surface,
        onSurface: ink,
        surfaceContainer: card,
        surfaceContainerLow: dark
            ? const Color(0xFF192129)
            : const Color(0xFFF7F6F3),
        outline: style.border,
        error: dark ? const Color(0xFFFFA6A0) : const Color(0xFFB42318),
      );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'Nunito',
  );
  return base.copyWith(
    extensions: [style],
    scaffoldBackgroundColor: surface,
    textTheme: base.textTheme
        .copyWith(
          headlineLarge: TextStyle(
            fontSize: 32,
            height: 1.1,
            fontWeight: FontWeight.w900,
            color: ink,
          ),
          headlineMedium: TextStyle(
            fontSize: 28,
            height: 1.15,
            fontWeight: FontWeight.w900,
            color: ink,
          ),
          titleLarge: TextStyle(
            fontSize: 22,
            height: 1.2,
            fontWeight: FontWeight.w900,
            color: ink,
          ),
          titleMedium: TextStyle(
            fontSize: 17,
            height: 1.3,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: style.muted,
          ),
          labelLarge: TextStyle(
            fontSize: 15,
            height: 1.2,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
          labelMedium: TextStyle(
            fontSize: 12,
            height: 1.3,
            fontWeight: FontWeight.w800,
            color: style.muted,
          ),
        )
        .apply(fontFamily: 'Nunito'),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: surface,
      foregroundColor: ink,
      centerTitle: false,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: card,
      modalBackgroundColor: card,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dividerTheme: DividerThemeData(color: style.border, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      hintStyle: TextStyle(color: style.muted, fontWeight: FontWeight.w600),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: style.border, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: style.border, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: accentInk, width: 2),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accentInk,
      selectionColor: accent.withValues(alpha: .25),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: ink,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink,
      contentTextStyle: TextStyle(fontFamily: 'Nunito', color: surface),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
    ),
  );
}
