import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/data/demo_remote_repositories.dart';
import 'package:homespace/domain/models.dart';
import 'package:homespace/domain/repositories.dart';

void main() {
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
