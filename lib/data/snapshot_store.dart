import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/models.dart';
import 'snapshot_codec.dart';

class StoredLibrary {
  final LibrarySnapshot snapshot;
  final String? recoveryNotice;
  const StoredLibrary(this.snapshot, {this.recoveryNotice});
}

abstract interface class SnapshotStore {
  Future<StoredLibrary?> load();
  Future<void> save(LibrarySnapshot snapshot);
}

class MemorySnapshotStore implements SnapshotStore {
  String? contents;
  MemorySnapshotStore({this.contents});
  @override
  Future<StoredLibrary?> load() async =>
      contents == null ? null : StoredLibrary(SnapshotCodec.decode(contents!));
  @override
  Future<void> save(LibrarySnapshot snapshot) async {
    contents = SnapshotCodec.encode(snapshot);
  }
}

class SnapshotReadException implements Exception {
  const SnapshotReadException();
}

class FileSnapshotStore implements SnapshotStore {
  final Future<Directory> Function() directoryProvider;
  Future<Directory>? _directory;
  FileSnapshotStore(this.directoryProvider);

  factory FileSnapshotStore.android() => FileSnapshotStore(() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory('${documents.path}/homespace');
  });

  Future<Directory> get directory => _directory ??= directoryProvider();

  @override
  Future<StoredLibrary?> load() async {
    final folder = await directory;
    var invalidFileFound = false;
    for (final name in [
      'library.json',
      'library.pending.json',
      'library.backup.json',
    ]) {
      final candidate = File('${folder.path}/$name');
      if (!await candidate.exists()) continue;
      try {
        final snapshot = SnapshotCodec.decode(await candidate.readAsString());
        return StoredLibrary(
          snapshot,
          recoveryNotice: name == 'library.json'
              ? null
              : 'Recovered your saved library from a local backup.',
        );
      } on UnsupportedSnapshotVersion {
        rethrow;
      } on FormatException {
        invalidFileFound = true;
      }
    }
    if (invalidFileFound) throw const SnapshotReadException();
    return null;
  }

  @override
  Future<void> save(LibrarySnapshot snapshot) async {
    SnapshotCodec.validate(snapshot);
    final folder = await directory;
    await folder.create(recursive: true);
    final primary = File('${folder.path}/library.json');
    final pending = File('${folder.path}/library.pending.json');
    if (await primary.exists()) {
      try {
        SnapshotCodec.decode(await primary.readAsString());
      } on UnsupportedSnapshotVersion {
        rethrow;
      } on FormatException {
        // Preserve damaged bytes; do not replace the known-good backup with them.
        await primary.copy(
          '${folder.path}/library.corrupt-${DateTime.now().microsecondsSinceEpoch}.json',
        );
      }
    }
    await pending.writeAsString(SnapshotCodec.encode(snapshot), flush: true);
    if (await primary.exists()) {
      var validPrimary = true;
      try {
        SnapshotCodec.decode(await primary.readAsString());
      } on FormatException {
        validPrimary = false;
      }
      if (validPrimary) {
        final backupPending = await primary.copy(
          '${folder.path}/library.backup.pending.json',
        );
        await backupPending.rename('${folder.path}/library.backup.json');
      }
    }
    // Android rename replaces the primary atomically. A valid pending/backup
    // also permits recovery if the process stops between filesystem steps.
    await pending.rename(primary.path);
  }
}
