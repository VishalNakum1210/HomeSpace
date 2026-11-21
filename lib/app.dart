import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'application/frontend_session.dart';
import 'application/home_scope.dart';
import 'design/global_download_banner.dart';
import 'design/space_navigation.dart';
import 'design/space_theme.dart';
import 'design/system_ui.dart';
import 'domain/models.dart';
import 'domain/repositories.dart';
import 'pages/auth_page.dart';
import 'pages/collections_page.dart';
import 'pages/photos_page.dart';
import 'pages/profile_page.dart';
import 'pages/splash_page.dart';

class HomeSpaceApp extends StatefulWidget {
  final HomeRepository repository;

  /// Omit only when embedding the library in isolated previews/tests.
  final FrontendSession? session;
  final bool showSplash;
  const HomeSpaceApp({
    super.key,
    required this.repository,
    this.session,
    this.showSplash = true,
  });
  @override
  State<HomeSpaceApp> createState() => _HomeSpaceAppState();
}

class _HomeSpaceAppState extends State<HomeSpaceApp> {
  final navigatorKey = GlobalKey<NavigatorState>();
  SpacePage page = SpacePage.photos;
  bool photoFocused = false;
  late Appearance _appearance;
  late bool _ready;
  String? _bootError;
  late bool _bootstrapped;

  @override
  void initState() {
    super.initState();
    final isTest = const bool.fromEnvironment('FLUTTER_TEST') ||
        WidgetsBinding.instance.runtimeType.toString().contains('Test');
    _bootstrapped = !widget.showSplash || isTest;
    _appearance = widget.repository.profile.appearance;
    _ready = widget.repository.ready;
    _bootError = widget.repository.bootError;
    unawaited(widget.repository.initialize());
    widget.repository.addListener(_repositoryChanged);
    widget.session?.addListener(sessionChanged);
  }

  void _repositoryChanged() {
    final nextAppearance = widget.repository.profile.appearance;
    final nextReady = widget.repository.ready;
    final nextBootError = widget.repository.bootError;
    if (nextAppearance != _appearance ||
        nextReady != _ready ||
        nextBootError != _bootError) {
      setState(() {
        _appearance = nextAppearance;
        _ready = nextReady;
        _bootError = nextBootError;
      });
    }
  }

  @override
  void didUpdateWidget(HomeSpaceApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session?.removeListener(sessionChanged);
      widget.session?.addListener(sessionChanged);
    }
    if (oldWidget.repository != widget.repository) {
      oldWidget.repository.removeListener(_repositoryChanged);
      _appearance = widget.repository.profile.appearance;
      _ready = widget.repository.ready;
      _bootError = widget.repository.bootError;
      widget.repository.addListener(_repositoryChanged);
      unawaited(widget.repository.initialize());
    }
  }

  void sessionChanged() {
    FocusManager.instance.primaryFocus?.unfocus();
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    setState(() {
      page = SpacePage.photos;
      photoFocused = false;
    });
  }

  @override
  void dispose() {
    widget.repository.removeListener(_repositoryChanged);
    widget.session?.removeListener(sessionChanged);
    super.dispose();
  }

  void selectPage(SpacePage next) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => page = next);
  }

  @override
  Widget build(BuildContext context) => FrontendSessionScope(
    session: widget.session,
    child: HomeScope(
      repository: widget.repository,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'HomeSpace',
        debugShowCheckedModeBanner: false,
        theme: spaceTheme(Brightness.light, page),
        darkTheme: spaceTheme(Brightness.dark, page),
        themeMode: ThemeMode.values.byName(_appearance.name),
        themeAnimationDuration: Duration.zero,
        home: !_bootstrapped
            ? SplashPage(
                session: widget.session,
                repository: widget.repository,
                onInitialized: () {
                  if (mounted) {
                    setState(() => _bootstrapped = true);
                  }
                },
              )
            : widget.session != null && !widget.session!.isOpen
            ? AuthPage(session: widget.session!)
            : !_ready
            ? ListenableBuilder(
                listenable: widget.repository,
                builder: (context, _) =>
                    RepositoryBootPage(repository: widget.repository),
              )
            : Builder(
                  builder: (context) {
                    final keyboardOpen =
                        MediaQuery.viewInsetsOf(context).bottom > 0;
                    return AnnotatedRegion<SystemUiOverlayStyle>(
                      value: spaceSystemUiStyle(context),
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
                                bottom: (photoFocused || keyboardOpen) ? 16 : 84,
                                child: const SafeArea(
                                  top: false,
                                  bottom: false,
                                  child: GlobalDownloadBanner(),
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
