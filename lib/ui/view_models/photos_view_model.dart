import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:myspace/data/repositories/media_repository.dart';
import 'package:myspace/domain/models/media_item.dart';
import 'package:myspace/domain/models/memory_story.dart';
import 'package:myspace/domain/models/album.dart';
import 'package:myspace/domain/models/user_account.dart';

enum GridDensity { compact, comfortable, large }

class PhotosViewModel extends ChangeNotifier {
  final MediaRepository _repository;

  int _currentTabIndex = 0;
  int get currentTabIndex => _currentTabIndex;

  GridDensity _gridDensity = GridDensity.comfortable;
  GridDensity get gridDensity => _gridDensity;

  final Set<String> _selectedIds = {};
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  bool get isSelectionMode => _selectedIds.isNotEmpty;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  String? _selectedTag;
  String? get selectedTag => _selectedTag;

  String? _selectedPerson;
  String? get selectedPerson => _selectedPerson;

  String? _selectedCategory;
  String? get selectedCategory => _selectedCategory;

  String _currentScrollDate = 'October 2026';
  String get currentScrollDate => _currentScrollDate;

  void updateScrollDate(String date) {
    if (_currentScrollDate != date) {
      _currentScrollDate = date;
      notifyListeners();
    }
  }

  final Set<String> _lockedFolderIds = {};
  Set<String> get lockedFolderIds => Set.unmodifiable(_lockedFolderIds);
  bool _isLockedFolderUnlocked = false;
  bool get isLockedFolderUnlocked => _isLockedFolderUnlocked;
  final String _correctPin = '1234';

  // Auth state
  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;

  // ignore: prefer_initializing_formals
  PhotosViewModel({required MediaRepository repository, bool isLoggedIn = false})
      // ignore: prefer_initializing_formals
      : _repository = repository,
        // ignore: prefer_initializing_formals
        _isLoggedIn = isLoggedIn;

  void setTabIndex(int index) {
    if (_currentTabIndex != index) {
      _currentTabIndex = index;
      _selectedIds.clear();
      notifyListeners();
    }
  }

  void cycleGridDensity() {
    switch (_gridDensity) {
      case GridDensity.comfortable:
        _gridDensity = GridDensity.compact;
        break;
      case GridDensity.compact:
        _gridDensity = GridDensity.large;
        break;
      case GridDensity.large:
        _gridDensity = GridDensity.comfortable;
        break;
    }
    notifyListeners();
  }

  void setGridDensity(GridDensity density) {
    _gridDensity = density;
    notifyListeners();
  }

  int get crossAxisCount {
    switch (_gridDensity) {
      case GridDensity.compact:
        return 5;
      case GridDensity.comfortable:
        return 3;
      case GridDensity.large:
        return 2;
    }
  }

  // --- SELECTION ACTIONS ---
  void toggleSelection(String id) {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
    } else {
      _selectedIds.add(id);
    }
    notifyListeners();
  }

  void selectDayGroup(List<String> ids) {
    final allSelected = ids.every((id) => _selectedIds.contains(id));
    if (allSelected) {
      _selectedIds.removeAll(ids);
    } else {
      _selectedIds.addAll(ids);
    }
    notifyListeners();
  }

  void selectAll() {
    final allActive = activeItems;
    _selectedIds.addAll(allActive.map((i) => i.id));
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    notifyListeners();
  }

  void deleteSelected() {
    for (final id in _selectedIds) {
      _repository.moveToTrash(id);
    }
    _selectedIds.clear();
    notifyListeners();
  }

  void favoriteSelected() {
    for (final id in _selectedIds) {
      final item = _repository.getItemById(id);
      if (item != null && !item.isFavorite) {
        _repository.toggleFavorite(id);
      }
    }
    _selectedIds.clear();
    notifyListeners();
  }

  void archiveSelected() {
    for (final id in _selectedIds) {
      _repository.toggleArchive(id);
    }
    _selectedIds.clear();
    notifyListeners();
  }

  // --- SINGLE ITEM ACTIONS ---
  void toggleFavorite(String id) {
    _repository.toggleFavorite(id);
    notifyListeners();
  }

  void moveToTrash(String id) {
    _repository.moveToTrash(id);
    _selectedIds.remove(id);
    notifyListeners();
  }

  void restoreFromTrash(String id) {
    _repository.restoreFromTrash(id);
    notifyListeners();
  }

  void deletePermanently(String id) {
    _repository.deletePermanently(id);
    notifyListeners();
  }

  void emptyTrash() {
    _repository.emptyTrash();
    notifyListeners();
  }

  void toggleArchive(String id) {
    _repository.toggleArchive(id);
    _selectedIds.remove(id);
    notifyListeners();
  }

  void updatePhotoAdjustments({
    required String id,
    double? brightness,
    double? contrast,
    double? saturation,
    String? filterName,
  }) {
    _repository.updatePhotoAdjustments(
      id: id,
      brightness: brightness,
      contrast: contrast,
      saturation: saturation,
      filterName: filterName,
    );
    notifyListeners();
  }

  // --- SEARCH & FILTER ---
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setSelectedTag(String? tag) {
    _selectedTag = tag;
    notifyListeners();
  }

  void setSelectedPerson(String? person) {
    _selectedPerson = person;
    notifyListeners();
  }

  void setSelectedCategory(String? category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void clearAllFilters() {
    _searchQuery = '';
    _selectedTag = null;
    _selectedPerson = null;
    _selectedCategory = null;
    notifyListeners();
  }

  // --- DATA ACCESSORS ---
  List<MediaItem> get activeItems {
    final all = _repository.getActiveMediaItems();
    return all.where((item) => !_lockedFolderIds.contains(item.id)).toList();
  }

  List<MediaItem> get favoriteItems {
    return _repository.getFavoriteItems().where((item) => !_lockedFolderIds.contains(item.id)).toList();
  }

  List<MediaItem> get archivedItems {
    return _repository.getArchivedItems().where((item) => !_lockedFolderIds.contains(item.id)).toList();
  }

  List<MediaItem> get trashItems => _repository.getTrashItems();
  List<MemoryStory> get memories => _repository.getMemories();
  List<Album> get albums => _repository.getAlbums();
  List<DeviceFolder> get deviceFolders => _repository.getDeviceFolders();
  UserAccount get userAccount => _repository.getUserAccount();

  List<MediaItem> get filteredItems {
    var items = activeItems;

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase().trim();
      items = items.where((i) {
        final matchesTitle = i.title.toLowerCase().contains(q);
        final matchesLoc = i.location.toLowerCase().contains(q);
        final matchesTags = i.tags.any((t) => t.toLowerCase().contains(q));
        final matchesPeople = i.people.any((p) => p.toLowerCase().contains(q));
        return matchesTitle || matchesLoc || matchesTags || matchesPeople;
      }).toList();
    }

    if (_selectedTag != null) {
      items = items.where((i) => i.tags.contains(_selectedTag)).toList();
    }

    if (_selectedPerson != null) {
      items = items.where((i) => i.people.contains(_selectedPerson)).toList();
    }

    if (_selectedCategory != null) {
      if (_selectedCategory == 'Videos') {
        items = items.where((i) => i.isVideo).toList();
      } else if (_selectedCategory == 'Favorites') {
        items = items.where((i) => i.isFavorite).toList();
      } else if (_selectedCategory == 'Motion') {
        items = items.where((i) => i.isMotionPhoto).toList();
      } else {
        items = items.where((i) => i.tags.contains(_selectedCategory)).toList();
      }
    }

    return items;
  }

  Map<String, List<MediaItem>> get groupedTimelineItems {
    final items = filteredItems;
    final Map<String, List<MediaItem>> groups = {};

    for (final item in items) {
      final label = _formatDateGroup(item.dateTime);
      groups.putIfAbsent(label, () => []).add(item);
    }

    return groups;
  }

  String _formatDateGroup(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(itemDate).inDays;

    if (diffDays == 0) return 'Today';
    if (diffDays == 1) return 'Yesterday';
    if (diffDays < 7) {
      return DateFormat('EEEE, MMM d').format(dt);
    }
    if (dt.year == now.year) {
      return DateFormat('EEEE, MMM d').format(dt);
    }
    return DateFormat('MMMM yyyy').format(dt);
  }

  MediaItem? getItem(String id) => _repository.getItemById(id);

  void markMemoryViewed(String memoryId) {
    _repository.markMemoryAsViewed(memoryId);
    notifyListeners();
  }

  void createAlbum(String title, List<String> mediaIds) {
    _repository.createAlbum(title, mediaIds);
    _selectedIds.clear();
    notifyListeners();
  }

  void addSelectedToAlbum(String albumId) {
    _repository.addItemsToAlbum(albumId, _selectedIds.toList());
    _selectedIds.clear();
    notifyListeners();
  }

  void addItemsToAlbum(String albumId, List<String> itemIds) {
    _repository.addItemsToAlbum(albumId, itemIds);
    _selectedIds.clear();
    notifyListeners();
  }

  void toggleBackup() {
    _repository.toggleBackup();
    notifyListeners();
  }

  void freeUpSpace(double gb) {
    _repository.freeUpSpace(gb);
    notifyListeners();
  }

  // --- LOCKED FOLDER LOGIC ---
  bool unlockLockedFolder(String pin) {
    if (pin == _correctPin) {
      _isLockedFolderUnlocked = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  void lockLockedFolder() {
    _isLockedFolderUnlocked = false;
    notifyListeners();
  }

  void moveToLockedFolder(String id) {
    _lockedFolderIds.add(id);
    _selectedIds.remove(id);
    notifyListeners();
  }

  void removeFromLockedFolder(String id) {
    _lockedFolderIds.remove(id);
    notifyListeners();
  }

  List<MediaItem> get lockedItems {
    final all = _repository.getActiveMediaItems();
    return all.where((item) => _lockedFolderIds.contains(item.id)).toList();
  }

  // --- AUTHENTICATION ACTIONS ---
  void setLoggedIn(bool val) {
    _isLoggedIn = val;
    notifyListeners();
  }

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 650));
    final cleanEmail = email.trim();
    final localPart = cleanEmail.split('@').first;
    final name = localPart.isNotEmpty
        ? localPart[0].toUpperCase() + localPart.substring(1)
        : 'User';

    _repository.updateUserAccount(
      _repository.getUserAccount().copyWith(
        displayName: name,
        email: cleanEmail,
        isGuest: false,
        avatarUrl: 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=200&q=80',
        backupStatusText: 'Backup complete',
      ),
    );
    _isLoggedIn = true;
    notifyListeners();
    return true;
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
    bool enableBackup = true,
  }) async {
    await Future.delayed(const Duration(milliseconds: 700));
    _repository.updateUserAccount(
      UserAccount(
        displayName: name.trim(),
        email: email.trim(),
        avatarUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=200&q=80',
        storageUsedGB: 0.2,
        storageTotalGB: 15.0,
        isBackupEnabled: enableBackup,
        backupStatusText: enableBackup ? 'Backup active' : 'Backup paused',
        isBackingUp: false,
        isGuest: false,
      ),
    );
    _isLoggedIn = true;
    notifyListeners();
    return true;
  }

  Future<bool> loginWithGoogle({String? name, String? email}) async {
    await Future.delayed(const Duration(milliseconds: 600));
    _repository.updateUserAccount(
      UserAccount(
        displayName: name ?? 'Vishal Nakum',
        email: email ?? 'vishal7228918826@gmail.com',
        avatarUrl: 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=200&q=80',
        storageUsedGB: 11.4,
        storageTotalGB: 15.0,
        isBackupEnabled: true,
        backupStatusText: 'Backup complete',
        isBackingUp: false,
        isGuest: false,
      ),
    );
    _isLoggedIn = true;
    notifyListeners();
    return true;
  }

  void continueAsGuest() {
    _repository.updateUserAccount(
      const UserAccount(
        displayName: 'Guest User',
        email: 'guest@homespace.local',
        avatarUrl: '',
        storageUsedGB: 0.0,
        storageTotalGB: 15.0,
        isBackupEnabled: false,
        backupStatusText: 'Cloud backup paused (Guest)',
        isBackingUp: false,
        isGuest: true,
      ),
    );
    _isLoggedIn = true;
    notifyListeners();
  }

  void logout() {
    _isLoggedIn = false;
    _repository.resetUserAccount();
    _selectedIds.clear();
    _currentTabIndex = 0;
    notifyListeners();
  }
}
