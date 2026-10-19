import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:myspace/data/repositories/media_repository.dart';
import 'package:myspace/ui/core/theme/photos_theme.dart';
import 'package:myspace/ui/features/home_scaffold.dart';
import 'package:myspace/ui/view_models/photos_view_model.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const MySpacePhotosApp());
}

class MySpacePhotosApp extends StatelessWidget {
  final MediaRepository? repository;

  const MySpacePhotosApp({super.key, this.repository});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PhotosViewModel(repository: repository ?? MediaRepository()),
      child: MaterialApp(
        title: 'MySpace Photos',
        debugShowCheckedModeBanner: false,
        theme: PhotosTheme.light(),
        darkTheme: PhotosTheme.dark(),
        themeMode: ThemeMode.system,
        home: const HomeScaffold(),
      ),
    );
  }
}
