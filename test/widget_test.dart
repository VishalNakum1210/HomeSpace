import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:myspace/data/repositories/media_repository.dart';
import 'package:myspace/ui/core/widgets/google_photos_logo.dart';
import 'package:myspace/ui/view_models/photos_view_model.dart';
import 'package:myspace/main.dart';

final Uint8List _kTransparentImage = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49,
  0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06,
  0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44,
  0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D,
  0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
  0x60, 0x82,
]);

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

class _MockHttpClient extends Fake implements HttpClient {
  @override
  bool autoUncompress = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();
}

class _MockHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();
}

class _MockHttpHeaders extends Fake implements HttpHeaders {}

class _MockHttpClientResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  int get contentLength => _kTransparentImage.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_kTransparentImage).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

void main() {
  setUpAll(() {
    HttpOverrides.global = _TestHttpOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = null;
  });

  group('MySpace Google Photos Replica Tests', () {
    testWidgets('App smoke test loads HomeScaffold and navigation destinations', (WidgetTester tester) async {
      await tester.pumpWidget(const MySpacePhotosApp(initialLoggedIn: true));
      await tester.pump();

      // Verify Google Photos navigation destinations
      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('Memories'), findsOneWidget);
      expect(find.text('Collections'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);

      // Verify Google Photos logo
      expect(find.byType(GooglePhotosLogo), findsOneWidget);
    });

    testWidgets('App initial launch shows LoginScreen and transitions to RegisterScreen', (WidgetTester tester) async {
      await tester.pumpWidget(const MySpacePhotosApp(initialLoggedIn: false));
      await tester.pump();

      // Verify Login screen elements
      expect(find.text('Home Space'), findsOneWidget);
      expect(find.text('Sign in to your account'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.text('Use without an account (Guest)'), findsOneWidget);

      // Tap Create account to navigate to RegisterScreen
      await tester.ensureVisible(find.text('Create account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      // Verify RegisterScreen elements
      expect(find.text('Create Account'), findsOneWidget);
      expect(find.text('Join Home Space'), findsOneWidget);
      expect(find.text('Automatic Cloud Backup'), findsOneWidget);
      expect(find.text('Sign up with Google'), findsOneWidget);
    });

    testWidgets('Login screen guest mode transitions into HomeScaffold', (WidgetTester tester) async {
      await tester.pumpWidget(const MySpacePhotosApp(initialLoggedIn: false));
      await tester.pump();

      // Tap Guest mode
      await tester.ensureVisible(find.text('Use without an account (Guest)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use without an account (Guest)'));
      await tester.pumpAndSettle();

      // Should land in HomeScaffold
      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('Collections'), findsOneWidget);
    });

    test('PhotosViewModel auth workflows: login, guest, and logout', () async {
      final repository = MediaRepository();
      final vm = PhotosViewModel(repository: repository, isLoggedIn: false);

      expect(vm.isLoggedIn, false);

      // Login
      await vm.login(email: 'test@example.com', password: 'password123');
      expect(vm.isLoggedIn, true);
      expect(vm.userAccount.email, 'test@example.com');
      expect(vm.userAccount.isGuest, false);

      // Logout
      vm.logout();
      expect(vm.isLoggedIn, false);

      // Guest mode
      vm.continueAsGuest();
      expect(vm.isLoggedIn, true);
      expect(vm.userAccount.isGuest, true);
    });

    test('PhotosViewModel selection and favorite management', () {
      final repository = MediaRepository();
      final vm = PhotosViewModel(repository: repository);

      final initialActive = vm.activeItems;
      expect(initialActive.isNotEmpty, true);

      final firstId = initialActive.first.id;

      // Toggle selection
      expect(vm.isSelectionMode, false);
      vm.toggleSelection(firstId);
      expect(vm.isSelectionMode, true);
      expect(vm.selectedIds.contains(firstId), true);

      vm.clearSelection();
      expect(vm.isSelectionMode, false);

      // Toggle favorite
      final initialFav = initialActive.first.isFavorite;
      vm.toggleFavorite(firstId);
      expect(vm.getItem(firstId)?.isFavorite, !initialFav);
    });

    test('PhotosViewModel trash and restore workflow', () {
      final repository = MediaRepository();
      final vm = PhotosViewModel(repository: repository);

      final activeCount = vm.activeItems.length;
      final trashCount = vm.trashItems.length;
      final firstId = vm.activeItems.first.id;

      // Move to trash
      vm.moveToTrash(firstId);
      expect(vm.activeItems.length, activeCount - 1);
      expect(vm.trashItems.length, trashCount + 1);

      // Restore from trash
      vm.restoreFromTrash(firstId);
      expect(vm.activeItems.length, activeCount);
      expect(vm.trashItems.length, trashCount);
    });

    test('PhotosViewModel locked folder protection', () {
      final repository = MediaRepository();
      final vm = PhotosViewModel(repository: repository);

      expect(vm.unlockLockedFolder('0000'), false);
      expect(vm.unlockLockedFolder('1234'), true);
      expect(vm.isLockedFolderUnlocked, true);

      vm.lockLockedFolder();
      expect(vm.isLockedFolderUnlocked, false);
    });

    test('PhotosViewModel search and category filters', () {
      final repository = MediaRepository();
      final vm = PhotosViewModel(repository: repository);

      // Search by keyword
      vm.setSearchQuery('Tokyo');
      expect(vm.filteredItems.any((i) => i.location.contains('Tokyo')), true);

      // Search by tag
      vm.clearAllFilters();
      vm.setSelectedTag('Mountains');
      expect(vm.filteredItems.every((i) => i.tags.contains('Mountains')), true);

      // Category filter: Videos
      vm.clearAllFilters();
      vm.setSelectedCategory('Videos');
      expect(vm.filteredItems.every((i) => i.isVideo), true);

      vm.clearAllFilters();
      expect(vm.filteredItems.length, vm.activeItems.length);
    });

    test('PhotosViewModel albums and backup workflows', () {
      final repository = MediaRepository();
      final vm = PhotosViewModel(repository: repository);

      final initialAlbumCount = vm.albums.length;
      vm.createAlbum('Test Holiday 2026', ['photo_1', 'photo_2']);
      expect(vm.albums.length, initialAlbumCount + 1);
      expect(vm.albums.first.title, 'Test Holiday 2026');

      // Backup toggle
      final initialBackup = vm.userAccount.isBackupEnabled;
      vm.toggleBackup();
      expect(vm.userAccount.isBackupEnabled, !initialBackup);

      // Free up space
      final usedBefore = vm.userAccount.storageUsedGB;
      vm.freeUpSpace(1.0);
      expect(vm.userAccount.storageUsedGB, usedBefore - 1.0);
    });
  });
}
