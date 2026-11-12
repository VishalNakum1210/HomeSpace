import 'dart:async';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Nunito',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });

  final session = FrontendSession();
  final serverUri = Uri.tryParse(defaultServerUrl);
  final connectionRepo = HttpConnectionRepository(initialAddress: serverUri);

  final uploadRepo = HttpUploadRepository(
    getServerAddress: () => connectionRepo.status.address ?? serverUri,
    getAuthToken: () => session.authToken,
  );

  final repository = LocalHomeRepository(
    store: FileSnapshotStore.android(),
    customConnection: connectionRepo,
    customUploads: uploadRepo,
    scenario: DemoScenario.parse(
      const String.fromEnvironment(
        'HOMESPACE_SCENARIO',
        defaultValue: 'populated',
      ),
    ),
  );

  if (serverUri != null) {
    unawaited(connectionRepo.connect(serverUri));
  }

  runApp(
    HomeSpaceApp(
      session: session,
      repository: repository,
    ),
  );
}
