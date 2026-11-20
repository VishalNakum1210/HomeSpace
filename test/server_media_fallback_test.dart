import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/application/device_media_service.dart';
import 'package:homespace/data/homespace_api_client.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/seed_library.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/domain/models.dart';
import 'package:homespace/pages/library_widgets.dart';
import 'package:homespace/pages/media_viewer.dart';

void main() {
  group('resolveMediaUri helper tests', () {
    test('resolves and swaps endpoints on network URLs', () {
      const assetUrl = 'http://192.168.1.50:8080/api/media/item-123/thumb';
      final thumbUri = resolveMediaUri(
        asset: assetUrl,
        id: 'item-123',
        endpoint: 'thumb',
      );
      expect(thumbUri.toString(), 'http://192.168.1.50:8080/api/media/item-123/thumb');

      final previewUri = resolveMediaUri(
        asset: assetUrl,
        id: 'item-123',
        endpoint: 'preview',
      );
      expect(previewUri.toString(), 'http://192.168.1.50:8080/api/media/item-123/preview');

      final fileUri = resolveMediaUri(
        asset: assetUrl,
        id: 'item-123',
        endpoint: 'file',
      );
      expect(fileUri.toString(), 'http://192.168.1.50:8080/api/media/item-123/file');
    });

    test('resolves local path or filename against serverUri when uploaded', () {
      final serverUri = Uri.parse('http://homespace.local:3000');
      const localPath = '/storage/emulated/0/DCIM/Camera/IMG_20261119_120000.jpg';

      final thumbUri = resolveMediaUri(
        asset: localPath,
        id: 'server-id-999',
        serverUri: serverUri,
        endpoint: 'thumb',
      );
      expect(thumbUri.toString(), 'http://homespace.local:3000/api/media/server-id-999/thumb');

      final fileUri = resolveMediaUri(
        asset: localPath,
        id: 'server-id-999',
        serverUri: serverUri,
        endpoint: 'file',
      );
      expect(fileUri.toString(), 'http://homespace.local:3000/api/media/server-id-999/file');
    });

    test('returns null when local asset has no serverUri', () {
      const localPath = '/storage/emulated/0/DCIM/Camera/photo.jpg';
      final resolved = resolveMediaUri(
        asset: localPath,
        id: 'id-1',
        serverUri: null,
      );
      expect(resolved, isNull);
    });
  });

  group('LocalHomeRepository server upload & sync fallback', () {
    test('syncWithServer updates local item with remote ID and asset URL when matched by title', () async {
      final seed = seedLibrary(DateTime(2026, 1, 1));
      final store = MemorySnapshotStore();
      await store.save(seed.copyWith(media: [], albums: [], favorites: {}, trash: []));
      final repo = LocalHomeRepository(store: store);
      await repo.initialize();

      // User has local photo on phone
      final localItem = MediaItem(
        id: 'local-phone-id-1',
        asset: '/storage/emulated/0/DCIM/Camera/sunset.jpg',
        title: 'sunset.jpg',
        category: 'Camera',
        takenAt: DateTime(2026, 11, 19, 10, 0),
        kind: MediaKind.photo,
      );
      await repo.addMedia(localItem);
      await repo.toggleFavorite('local-phone-id-1');
      await repo.createAlbum(
        'Vacation',
        description: 'Local Vacation',
        mediaIds: ['local-phone-id-1'],
      );

      expect(repo.media.length, 1);
      expect(repo.media.first.id, 'local-phone-id-1');
      expect(repo.media.first.asset, '/storage/emulated/0/DCIM/Camera/sunset.jpg');
      expect(repo.favorites, contains('local-phone-id-1'));
      final albumBefore = repo.albums.firstWhere((a) => a.title == 'Vacation');
      expect(albumBefore.mediaIds, contains('local-phone-id-1'));
      expect(albumBefore.coverId, 'local-phone-id-1');

      // Now photo is uploaded to server and given server ID 'server-remote-id-42' and asset URL
      final remoteItem = MediaItem(
        id: 'server-remote-id-42',
        asset: 'http://192.168.1.100:8080/api/media/server-remote-id-42/thumb',
        title: 'sunset.jpg',
        category: 'Uploads',
        takenAt: DateTime(2026, 11, 19, 10, 0),
        kind: MediaKind.photo,
      );

      // Re-adding via onMediaUploaded or sync
      await repo.addMedia(remoteItem);

      // The media item should now have remote server ID and remote asset URL
      expect(repo.media.length, 1);
      final syncedItem = repo.media.first;
      expect(syncedItem.id, 'server-remote-id-42');
      expect(syncedItem.asset, 'http://192.168.1.100:8080/api/media/server-remote-id-42/thumb');

      // Favorites and Albums should have updated their references from old local ID to remote ID
      expect(repo.favorites, contains('server-remote-id-42'));
      expect(repo.favorites, isNot(contains('local-phone-id-1')));

      final albumAfter = repo.albums.firstWhere((a) => a.title == 'Vacation');
      expect(albumAfter.mediaIds, contains('server-remote-id-42'));
      expect(albumAfter.mediaIds, isNot(contains('local-phone-id-1')));
      expect(albumAfter.coverId, 'server-remote-id-42');
    });
  });

  group('Cache eviction methods', () {
    test('clearLocalCaches runs safely without exceptions', () {
      DeviceMediaService.clearLocalMediaCache();
      MediaThumbnail.clearLocalCaches();
      MediaViewer.clearLocalCaches();
    });
  });
}
