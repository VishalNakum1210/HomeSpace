import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design/space_navigation.dart';
import 'design/space_theme.dart';
import 'pages/collections_page.dart';
import 'pages/photos_page.dart';
import 'pages/profile_page.dart';

class HomeSpaceApp extends StatefulWidget {
  final ThemeMode initialThemeMode;
  const HomeSpaceApp({super.key, this.initialThemeMode = ThemeMode.system});
  @override
  State<HomeSpaceApp> createState() => _HomeSpaceAppState();
}

class _HomeSpaceAppState extends State<HomeSpaceApp> {
  SpacePage page = SpacePage.photos;
  late ThemeMode mode = widget.initialThemeMode;

  void selectPage(SpacePage next) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => page = next);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'HomeSpace',
    debugShowCheckedModeBanner: false,
    theme: spaceTheme(Brightness.light, page),
    darkTheme: spaceTheme(Brightness.dark, page),
    themeMode: mode,
    themeAnimationDuration:
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 200),
    themeAnimationCurve: Curves.easeOut,
    home: Builder(
      builder: (context) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Theme.of(context)
                    .scaffoldBackgroundColor,
                systemNavigationBarContrastEnforced: false,
              ),
          child: PopScope(
            canPop: page == SpacePage.photos,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) selectPage(SpacePage.photos);
            },
            child: Scaffold(
              body: Stack(
                children: [
                  Positioned.fill(
                    child: IndexedStack(
                      index: page.index,
                      children: [
                        PhotosPage(
                          onProfile: () => selectPage(SpacePage.profile),
                        ),
                        const CollectionsPage(),
                        ProfilePage(
                          mode: mode,
                          onThemeChanged: (next) => setState(() => mode = next),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 16,
                    child: SafeArea(
                      top: false,
                      child: Center(
                        child: IgnorePointer(
                          ignoring: keyboardOpen,
                          child: AnimatedSlide(
                            offset: keyboardOpen
                                ? const Offset(0, 2)
                                : Offset.zero,
                            duration: spaceMotion(context, 180),
                            child: AnimatedOpacity(
                              opacity: keyboardOpen ? 0 : 1,
                              duration: spaceMotion(context, 120),
                              child: SpaceNavigation(
                                selected: page,
                                onSelected: selectPage,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
