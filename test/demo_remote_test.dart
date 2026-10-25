import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/data/demo_remote_repositories.dart';
import 'package:homespace/domain/models.dart';
import 'package:homespace/domain/repositories.dart';
import 'package:homespace/domain/server_address.dart';

void main() {
  test(
    'Server addresses support LAN ports and reject malformed or secret URLs',
    () {
      expect(
        parseServerAddress(' http://192.168.1.20:8080/photos ').port,
        8080,
      );
      expect(parseServerAddress('https://server.test/home').path, '/home');
      expect(parseServerAddress('http://[::1]:8080').port, 8080);
      for (final value in [
        '',
        'server.test',
        'ftp://server.test',
        'http://',
        'http://bad host',
        'https://user:secret@server.test',
        'https://server.test?token=secret',
        'https://server.test#key',
        'http://server.test:70000',
        'http://server.test:0',
        'http://server.test:abc',
      ]) {
        expect(
          () => parseServerAddress(value),
          throwsA(isA<LocalActionException>()),
          reason: value,
        );
      }
    },
  );

  test(
    'Disposal and superseding attempts never publish a stale result',
    () async {
      final disposed = DemoConnectionRepository(
        delay: const Duration(milliseconds: 10),
      );
      var updates = 0;
      disposed.addListener(() => updates++);
      final pending = disposed.connect(Uri.parse('http://server.test'));
      disposed.dispose();
      await pending;
      expect(updates, 1);
      final connection = DemoConnectionRepository(
        delay: const Duration(milliseconds: 10),
      );
      addTearDown(connection.dispose);
      final first = connection.connect(Uri.parse('http://old.test'));
      final second = connection.connect(Uri.parse('http://new.test'));
      await Future.wait([first, second]);
      expect(connection.status.address!.host, 'new.test');
      expect(connection.status.phase, ConnectionPhase.connected);
    },
  );
  test(
    'Connection fixtures always identify themselves as simulations',
    () async {
      final connection = DemoConnectionRepository();
      addTearDown(connection.dispose);
      final result = await connection.connect(
        Uri.parse('http://192.168.1.20:8000'),
      );
      expect(result.phase, ConnectionPhase.connected);
      expect(result.isDemo, isTrue);
      expect(result.message, contains('No files are sent'));
      connection.scenario = DemoScenario.offline;
      expect(
        (await connection.connect(Uri.parse('http://192.168.1.20:8000'))).phase,
        ConnectionPhase.offline,
      );
      connection.scenario = DemoScenario.failed;
      expect(
        (await connection.connect(Uri.parse('http://192.168.1.20:8000'))).phase,
        ConnectionPhase.failed,
      );
      await expectLater(
        connection.connect(Uri.parse('file:///server')),
        throwsA(isA<LocalActionException>()),
      );
      await expectLater(
        connection.connect(Uri.parse('https://name:password@server.test')),
        throwsA(isA<LocalActionException>()),
      );
    },
  );

  test('Disconnect cancels a pending simulated connection', () async {
    final connection = DemoConnectionRepository(
      delay: const Duration(milliseconds: 10),
    );
    addTearDown(connection.dispose);
    final pending = connection.connect(Uri.parse('http://server.test'));
    connection.disconnect();
    expect((await pending).phase, ConnectionPhase.disconnected);
    expect(connection.status.phase, ConnectionPhase.disconnected);
  });

  test(
    'Queue pause, resume, retry and completion preserve consistent totals',
    () {
      final queue = DemoUploadRepository();
      addTearDown(queue.dispose);
      expect(queue.isDemo, isTrue);
      expect(queue.items.length, 5);
      expect(queue.count(UploadPhase.completed), 2);
      queue.pause('upload-3');
      expect(queue.count(UploadPhase.uploading), 0);
      expect(queue.count(UploadPhase.paused), 1);
      queue.resume('upload-3');
      queue.retry('upload-5');
      expect(queue.count(UploadPhase.queued), 3);
      expect(queue.items.last.bytesSent, 0);
      queue.simulateProgress('upload-3', 3000);
      expect(queue.count(UploadPhase.completed), 3);
      expect(queue.items[2].progress, 1);
      queue.cancel('upload-4');
      expect(queue.count(UploadPhase.canceled), 1);
      expect(
        UploadPhase.values.fold<int>(
          0,
          (sum, phase) => sum + queue.count(phase),
        ),
        5,
      );
    },
  );

  test(
    'Invalid demo progress is rejected and completed items remain completed',
    () {
      final queue = DemoUploadRepository();
      addTearDown(queue.dispose);
      expect(
        () => queue.simulateProgress('upload-3', 4000),
        throwsA(isA<LocalActionException>()),
      );
      expect(
        () => queue.simulateProgress('upload-3', 10),
        throwsA(isA<LocalActionException>()),
      );
      expect(
        () => queue.simulateProgress('upload-5', 900),
        throwsA(isA<LocalActionException>()),
      );
      queue.cancel('upload-1');
      expect(queue.items.first.phase, UploadPhase.completed);
      queue.reset(DemoScenario.empty);
      expect(queue.items, isEmpty);
    },
  );
}
