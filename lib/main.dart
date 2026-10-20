import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:myspace/data/repositories/media_repository.dart';
import 'package:myspace/ui/core/theme/photos_theme.dart';
import 'package:myspace/ui/features/home_scaffold.dart';
import 'package:myspace/ui/features/auth/login_screen.dart';
import 'package:myspace/ui/features/auth/register_screen.dart';
import 'package:myspace/ui/view_models/photos_view_model.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const HomeSpaceApp(initialLoggedIn: false));
}

class HomeSpaceApp extends StatelessWidget {
  final MediaRepository? repository;
  final bool initialLoggedIn;

  const HomeSpaceApp({
    super.key,
    this.repository,
    this.initialLoggedIn = false,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PhotosViewModel(
        repository: repository ?? MediaRepository(),
        isLoggedIn: initialLoggedIn,
      ),
      child: MaterialApp(
        title: 'Home Space',
        debugShowCheckedModeBanner: false,
        theme: PhotosTheme.light(),
        darkTheme: PhotosTheme.dark(),
        themeMode: ThemeMode.system,
        home: const AuthGate(),
        routes: {
          '/login': (_) => const LoginScreen(),
          '/register': (_) => const RegisterScreen(),
          '/home': (_) => const HomeScaffold(),
        },
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = context.select<PhotosViewModel, bool>((vm) => vm.isLoggedIn);
    if (isLoggedIn) {
      return const HomeScaffold();
    }
    return const LoginScreen();
  }
}

typedef MySpacePhotosApp = HomeSpaceApp;
