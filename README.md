# MySpace — Google Photos Replica Frontend (Flutter)

A high-fidelity, pixel-perfect **Google Photos** replica frontend built with **Flutter 3.47** & **Material 3**.

---

## ✨ Features Implemented

### 1. 🖼️ Photos Tab (Main Timeline Feed)
- **Authentic Google Photos Header Bar**:
  - Custom canvas-rendered Google 4-color pinwheel logo.
  - Search trigger input leading to Explore/Search.
  - Grid density toggle (cycle between Compact 5-column, Comfortable 3-column, and Day 2-column views).
  - Google Account Avatar with live backup status sync badge.
- **Recent Highlights / Stories Carousel**:
  - Rounded highlight story cards with auto-curated trip titles, locations, and gradient overlays.
  - Tapping opens the full-screen **Story Viewer**.
- **Quick Category Filters**:
  - Instant chips for *Favorites, Videos, Motion Photos, Mountains, Beach, City, Food*.
- **Grouped Timeline Grid**:
  - Sticky date headers (*Today, Yesterday, Oct 16, September 2026*).
  - Date group selection badge: one-tap select/deselect all photos of that day.
  - Photo thumbnail badges: Video duration badge (`▶ 0:34`), Motion Photo badge, Favorite star badge.

### 2. 🔍 Multi-Selection Mode
- Long-press any photo or tap a date-group circle to trigger Google Photos selection mode.
- Contextual selection bar: selection count, Share, Favorite, Move to Trash, Add to Album, Archive, and Move to Locked Folder.

### 3. 🔍 Full-Screen Photo Detail & Lightbox
- **Interactive Viewer**: Pinch-to-zoom and double-tap zoom with `InteractiveViewer`.
- **Top Bar**: Cast, Motion Photo playback, animated Favorite star, EXIF info, and overflow menu.
- **Bottom Actions**:
  - **Share**: Google Photos native sharing sheet with recent contacts and direct link generator.
  - **Edit**: Photo editor sheet with dynamic enhancement filters (*Enhance, Warm, Cool, Vivid, Mono*), crop presets (*1:1, 16:9, Rotate 90°*), and brightness/contrast sliders.
  - **Lens**: Simulated Google Lens visual scanner with animated subject detection bounding box, visual match cards, and search modes.
  - **Delete**: Move to Trash with confirmation dialog.
- **EXIF Metadata Bottom Sheet**:
  - Date & time, location map preview, camera sensor metadata (e.g. *Pixel 9 Pro • f/1.68 • 1/320s • 24mm • ISO 45*), file dimensions, resolution, cloud backup status, and recognized face tags.

### 4. 📖 Memories Tab
- Featured recap banner with high-resolution imagery and gradient backdrop.
- Grid of past trips & highlights.
- **Story Viewer Screen**:
  - Segmented progress bar for multi-photo story segments.
  - Auto-advancing timer (5 seconds per slide).
  - Tap left/right to navigate, long-press to pause.
  - Swipe down to dismiss.

### 5. 🗂️ Collections Tab (Library)
- **Quick Utilities**:
  - **Favorites**: Filtered view of starred photos.
  - **Trash**: Soft-delete trash bin with 60-day warning banner, Restore, and Empty Trash workflows.
  - **Archive**: Photos hidden from the main timeline.
  - **Locked Folder**: Protected with a 4-digit PIN lock (`1234`), keeping sensitive photos isolated from the main library.
- **Albums**:
  - Create new custom albums.
  - Add existing photos into albums.
  - Shared album badges with collaborator avatar indicators.
- **Photos on Device**:
  - Device folders (*Camera, Screenshots, WhatsApp Images, Downloads*) with cloud backup sync statuses.

### 6. 🔎 Search & Explore Tab
- Live search query filtering matching titles, locations, tags, and people.
- **People & Pets**: Face avatar row with direct person filtering (*Sophia, Alex, Liam, Elena, Noah*).
- **Places**: Visual destination cards (*Tokyo, California, Alps, New York*).
- **Categories & Things**: Quick search chips (*Mountains, Sunsets, Nature, City, Food, Beach*).

### 7. 👤 Google Account & Storage Bottom Sheet
- Displays Google Account profile (*Vishal Nakum* / *vishal7228918826@gmail.com*).
- Backup toggle (*Backup complete* vs *Backup paused*).
- Storage meter (*11.4 GB of 15 GB used*) with colored linear progress indicator.
- One-tap "Free up 1.2 GB" device cleaner option.

---

## 🏛️ Architecture & Project Structure

The project strictly follows the layered MVVM architecture:

```text
lib/
├── domain/
│   └── models/
│       ├── media_item.dart        # Core photo/video model with EXIF & adjustments
│       ├── memory_story.dart      # Story reel model
│       ├── album.dart             # Albums & device folders
│       └── user_account.dart      # Google account & backup state
├── data/
│   ├── datasources/
│   │   └── mock_media_data_source.dart  # Curated photography dataset
│   └── repositories/
│       └── media_repository.dart        # Single source of truth data store
├── ui/
│   ├── core/
│   │   ├── theme/
│   │   │   └── photos_theme.dart        # Light/Dark Google Photos Material 3 theme
│   │   └── widgets/
│   │       ├── google_photos_logo.dart  # Custom canvas pinwheel logo
│   │       ├── google_account_sheet.dart# Account & backup modal
│   │       ├── selection_action_bar.dart# Contextual multi-selection bar
│   │       ├── photo_thumbnail.dart     # Thumbnail with badges & selection
│   │       └── timeline_header.dart     # Sticky date header with group checkmark
│   ├── view_models/
│   │   └── photos_view_model.dart       # ChangeNotifier managing app state
│   └── features/
│       ├── home_scaffold.dart           # NavigationBar root container
│       ├── photos/                      # Feed, search bar & memories carousel
│       ├── detail/                      # Lightbox, EXIF, Lens, Editor
│       ├── memories/                    # Memories tab & Story Viewer
│       ├── collections/                 # Library, Trash, Favorites, Locked Folder
│       └── search/                      # Explore, faces, places & live filter
└── main.dart                            # Application entry point
```

---

## 🧪 Testing & Verification

Run the automated test suite:
```powershell
flutter test
```
All unit and widget tests pass:
- Smoke test verifying navigation destinations and the Google Photos logo.
- Multi-selection and favorite toggling.
- Trash, restore, and permanent deletion workflows.
- Locked Folder PIN authentication.
- Search and tag filtering.
- Album creation and backup storage management.

Run static analysis:
```powershell
flutter analyze
```
Result: **No issues found!**
