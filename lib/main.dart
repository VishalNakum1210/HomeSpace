import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'application/auto_backup_service.dart';
import 'application/frontend_session.dart';
import 'data/http_remote_repositories.dart';
import 'data/local_home_repository.dart';
import 'data/snapshot_store.dart';
import 'data/tls_trust.dart';
import 'domain/models.dart';
import 'services/cache_service.dart';

const String defaultServerUrl = String.fromEnvironment(
  'HOMESPACE_SERVER_URL',
  defaultValue: '',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('HomeSpace FlutterError: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('HomeSpace AsyncError: $error');
    return true;
  };
  try {
    final docs = await getApplicationDocumentsDirectory();
    await HomeSpaceTlsTrust.initFromDirectory(Directory('${docs.path}/homespace'));
  } catch (_) {}
  PaintingBinding.instance.imageCache.maximumSize = 2500;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 256 * 1024 * 1024;
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Nunito',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });

  final trimmedDefault = defaultServerUrl.trim();
  final serverUri = trimmedDefault.isNotEmpty ? Uri.tryParse(trimmedDefault) : null;
  final session = FrontendSession(
    serverUri: serverUri != null && serverUri.hasAuthority ? serverUri : null,
    store: FileSessionStore.android(),
  );
  final hasSession = await session.restoreSession();
  final activeServerUri = session.serverUri ??
      (serverUri != null && serverUri.hasAuthority ? serverUri : null);
  final connectionRepo = HttpConnectionRepository(initialAddress: activeServerUri);

  if (session.isAuthenticated || activeServerUri != null) {
    unawaited(
      AutoBackupService.syncConfigToNative(
        serverUri: (activeServerUri ?? session.serverUri)?.toString(),
        token: session.authToken,
        trustedCertPins: HomeSpaceTlsTrust.allPins(),
      ).catchError((_) {}),
    );
  }

  late final LocalHomeRepository repository;
  final uploadRepo = HttpUploadRepository(
    getServerAddress: () =>
        connectionRepo.status.address ?? session.serverUri ?? activeServerUri,
    getAuthToken: () => session.authToken,
    getExistingMedia: () => repository.media,
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

  session.onRemoteLogout = () async {
    await repository.clearUserData();
    await CacheService.clearCache();
  };

  if (activeServerUri != null) {
    unawaited(connectionRepo.connect(activeServerUri));
  }

  if (hasSession && session.isAuthenticated && activeServerUri != null) {
    try {
      if (repository.profile.userId != session.userId ||
          (session.userName != null && repository.profile.name != session.userName) ||
          repository.profile.isAdmin != session.isAdmin) {
        await repository.initForAuthenticatedUser(
          userId: session.userId!,
          name: session.userName ?? 'HomeSpace User',
          avatarTone: session.avatarTone ?? AvatarTone.orange,
          isAdmin: session.isAdmin,
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
    } catch (e, st) {
      debugPrint('Startup sync/init error: $e\n$st');
    }
  }

  runApp(
    HomeSpaceApp(
      session: session,
      repository: repository,
    ),
  );
}
