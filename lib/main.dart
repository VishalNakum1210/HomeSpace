import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/local_home_repository.dart';
import 'data/snapshot_store.dart';
import 'domain/models.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Nunito',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  runApp(
    HomeSpaceApp(
      repository: LocalHomeRepository(
        store: FileSnapshotStore.android(),
        scenario: DemoScenario.parse(
          const String.fromEnvironment(
            'HOMESPACE_SCENARIO',
            defaultValue: 'populated',
          ),
        ),
      ),
    ),
  );
}
