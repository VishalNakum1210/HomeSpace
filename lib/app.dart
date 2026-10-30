import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'application/home_scope.dart';
import 'design/space_navigation.dart';
import 'design/space_theme.dart';
import 'domain/repositories.dart';
import 'pages/collections_page.dart';
import 'pages/photos_page.dart';
import 'pages/profile_page.dart';

class HomeSpaceApp extends StatefulWidget {
  final HomeRepository repository;
  const HomeSpaceApp({super.key, required this.repository});
  @override
  State<HomeSpaceApp> createState() => _HomeSpaceAppState();
}

class _HomeSpaceAppState extends State<HomeSpaceApp> {
  SpacePage page = SpacePage.photos;
  bool photoFocused = false;
  @override
  void initState() {
    super.initState();
    unawaited(widget.repository.initialize());
  }

  @override
  void didUpdateWidget(HomeSpaceApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      unawaited(widget.repository.initialize());
    }
  }

  void selectPage(SpacePage next) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => page = next);
  }

  @override
  Widget build(BuildContext context) => HomeScope(
    repository: widget.repository,
    child: ListenableBuilder(
      listenable: widget.repository,
      builder: (context, _) => MaterialApp(
        title: 'HomeSpace',
        debugShowCheckedModeBanner: false,
        theme: spaceTheme(Brightness.light, page),
        darkTheme: spaceTheme(Brightness.dark, page),
        themeMode: ThemeMode.values.byName(
          widget.repository.profile.appearance.name,
        ),
        themeAnimationDuration:
            WidgetsBinding
                .instance
                .platformDispatcher
                .accessibilityFeatures
                .disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 200),
        themeAnimationCurve: Curves.easeOut,
        home: !widget.repository.ready
            ? RepositoryBootPage(repository: widget.repository)
            : Builder(
                builder: (context) {
                  final dark = Theme.of(context).brightness == Brightness.dark;
                  final keyboardOpen =
                      MediaQuery.viewInsetsOf(context).bottom > 0;
                  return AnnotatedRegion<SystemUiOverlayStyle>(
                    value:
                        (dark
                                ? SystemUiOverlayStyle.light
                                : SystemUiOverlayStyle.dark)
                            .copyWith(
                              statusBarColor: Colors.transparent,
                              systemNavigationBarColor: Theme.of(context)
                                  .scaffoldBackgroundColor,
                              systemNavigationBarContrastEnforced: false,
                              systemNavigationBarIconBrightness: dark
                                  ? Brightness.light
                                  : Brightness.dark,
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
                                    active: page == SpacePage.photos,
                                    onFocusChanged: (value) {
                                      if (photoFocused != value) {
                                        setState(() => photoFocused = value);
                                      }
                                    },
                                    onProfile: () =>
                                        selectPage(SpacePage.profile),
                                  ),
                                  CollectionsPage(
                                    onProfile: () =>
                                        selectPage(SpacePage.profile),
                                  ),
                                  const ProfilePage(),
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
                                        child: Offstage(
                                          offstage:
                                              page == SpacePage.photos &&
                                              photoFocused,
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
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    ),
  );
}
