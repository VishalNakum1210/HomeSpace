import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'application/frontend_session.dart';
import 'data/http_remote_repositories.dart';
import 'data/local_home_repository.dart';
import 'data/snapshot_store.dart';
import 'domain/models.dart';

const String defaultServerUrl = String.fromEnvironment(
  'HOMESPACE_SERVER_URL',
  defaultValue: 'https://vishal-hp-laptop-15s-fr5xxx.tailda4c64.ts.net:8443',
);

class HomeSpaceHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = HomeSpaceHttpOverrides();
  PaintingBinding.instance.imageCache.maximumSize = 2500;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 256 * 1024 * 1024;
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Nunito',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });

  final serverUri = Uri.tryParse(defaultServerUrl);
  final session = FrontendSession(
    serverUri: serverUri,
    store: FileSessionStore.android(),
  );
  final hasSession = await session.restoreSession();
  final activeServerUri = session.serverUri ?? serverUri;
  final connectionRepo = HttpConnectionRepository(initialAddress: activeServerUri);

  late final LocalHomeRepository repository;
  final uploadRepo = HttpUploadRepository(
    getServerAddress: () =>
        connectionRepo.status.address ?? session.serverUri ?? activeServerUri,
    getAuthToken: () => session.authToken,
    onMediaUploaded: (item, targetAlbumId) async {
      await repository.addMedia(item);
      if (targetAlbumId != null) {
        await repository.addToAlbum(targetAlbumId, item.id);
      }
    },
  );

  repository = LocalHomeRepository(
    store: FileSnapshotStore.android(),
    customConnection: connectionRepo,
    customUploads: uploadRepo,
    getServerAddress: () =>
        connectionRepo.status.address ?? session.serverUri ?? activeServerUri,
    getAuthToken: () => session.authToken,
    scenario: DemoScenario.parse(
      const String.fromEnvironment(
        'HOMESPACE_SCENARIO',
        defaultValue: 'populated',
      ),
    ),
  );

  await repository.initialize();

  if (activeServerUri != null) {
    unawaited(connectionRepo.connect(activeServerUri));
  }

  if (hasSession && session.isAuthenticated && activeServerUri != null) {
    if (repository.profile.userId != session.userId ||
        (session.userName != null && repository.profile.name != session.userName)) {
      await repository.initForAuthenticatedUser(
        userId: session.userId!,
        name: session.userName ?? 'HomeSpace User',
        avatarTone: session.avatarTone ?? AvatarTone.orange,
        serverUri: activeServerUri,
        token: session.authToken!,
      );
    } else {
      unawaited(
        repository.syncWithServer(
          serverUri: activeServerUri,
          token: session.authToken!,
          clearLocalFirst: false,
        ).catchError((_) {}),
      );
    }
  }

  runApp(
    HomeSpaceApp(
      session: session,
      repository: repository,
    ),
  );
}
