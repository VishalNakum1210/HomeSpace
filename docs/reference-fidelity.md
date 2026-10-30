# Approved layout alignment — 0.7.0+11

Artwork and navigation in this historical build are superseded by
[the vector artwork and restored dock in 0.7.1](vector-artwork.md).

The 16-screen approved cartoon concept was compared with the implementation,
then its identified layout differences were corrected together. This remains
an Android frontend with persistent local sample data.

## Screen changes

| Screens | Alignment |
| --- | --- |
| Photos | Native headline/copy over the original garden composition; icon filters and compact brand header. |
| Search/selection | Results and Select all share a row; dock hides; selection count, actions and Clear sit at the bottom. |
| Viewer/details | Compact date/time header, overflow paging/zoom, four bottom actions; details use album covers and contributor portraits. |
| Collections | Pastel cards, overlaid portrait clusters, cover favorite and functional card menus; illustrated header and icon filters. |
| Shared album | Cover under back/menu, compact member row, Add photos and contributor portraits on photos. |
| Create/edit and picker | Cover camera, reference field hierarchy, description counter, Screenshots filter and bottom Save/Add controls. |
| Members/permissions | Portrait rows, role controls, purple Add member; contact subtitle, role cards, Save, removal in overflow. |
| Profile/edit | Compact portrait/house card and four settings rows; avatar camera opens tone options; Save follows Name. |
| Appearance | Reference preview thumbnails; house left and Done right immediately below the cards. |
| Trash/delete | Stable Trash title, purple Restore, brighter red Delete, original house warning illustration and blue-grey Cancel. |
| Empty/recovery | Brand header, original garden, title/copy, blue Add photos and orange status/Retry banner. |
| Navigation | Solid capsule, flat page symbols and a soft blue active circle. |

The existing application logo, Nunito font and tactile button shape/motion are
preserved. Home server and Upload queue are accessible through Profile → About.
Paging, zoom, album selection and member removal remain available in menus.
Android Back behavior still preserves Photos search/selection when returning
from another tab, then clears that mode on the next Back.

## Assets and truthful content

The only approved source available is a flattened 1024 × 1536 sheet. Crops in
`assets/illustrations/reference/` reuse its actual illustrations and sample
portraits; these are raster assets, not original SVGs. Native Flutter widgets
recreate the UI around them. The source limits sharpness at larger sizes, so
this is not a claim of pixel-perfect high-resolution reproduction.

Actual library photos, names, counts, dates and roles remain data-driven. Photo
details decode the bundled image for its actual byte size and dimensions.
Demo member addresses use reserved `example.com` addresses and send nothing;
renamed/custom identities retain initials and have no fabricated contact.
Added by shows existing album attribution, without an invented upload timestamp.
The picker remains a local-library picker, and empty-library Add photos explains
the sample experience rather than claiming that device import is implemented.

No storage schema change, reset, real network integration, invitation, upload or
video playback was introduced. Existing long descriptions are retained even
though new short descriptions use the reference's 200-character counter.

## Visual review

The render fixtures export all 16 reference states plus dark, recovery and
failure states at 390 × 844 logical pixels. Artwork is preloaded for captures.
Locally generated contact sheets (ignored artifacts):

- `output/previews/reference-aligned-main.png`
- `output/previews/reference-aligned-photo.png`
- `output/previews/reference-aligned-album.png`
- `output/previews/reference-aligned-settings.png`
- `output/previews/reference-aligned-16-screen.png` (all 16 in one image)

Large-text tests include 320 × 700 and 740 × 360 with doubled text, keyboard
insets, minimum touch targets, destructive cancellation, failed saves/retry,
role restrictions, persistence, reduced motion and cross-tab Back handling.
The viewer header now expands in landscape at larger text sizes.

## Validation

- Flutter analysis: no issues.
- Full suite: **87 tests passed**, including a new check that displayed photo
  size and dimensions match the bundled file. Interaction tests follow the
  relocated controls through their menus rather than requiring obsolete UI.
- Fresh captures reviewed in light and dark themes. Final main-page recapture
  passed after removing the profile-house crop's pale background.
- Android release APK build succeeded. Release lint: **0 errors, 1 existing
  `UnusedAttribute` warning** for `enableOnBackInvokedCallback` on API <33;
  existing fallback Back behavior is preserved. Dependency/Gradle deprecation
  warnings were also emitted by the toolchain.
- Git whitespace check passed.

APK: `output/releases/homespace-android-0.7.0+11-preview.apk`. Its adjacent JSON
records the current source revision, uncommitted-changes flag, development
signing and artifact hash. The final asset-only cleanup was repackaged after
the full pipeline; Dart code and native configuration were unchanged.

The archived APK signature verifies, with package `com.homespace.homespace`,
version name/code `0.7.0`/`11` and Android minimum/target APIs `24`/`36`. The
packaged profile artwork was checked byte-for-byte against the final source.
APK size: **54,860,839 bytes**. SHA-256:
`D239C3071E5EADAE4C777B211F4C9E05A14025B7A235775FE8D0E74DAC3741AB`.

This turn does not install on the phone or push Git changes. Render fixtures
and interaction tests do not certify physical-device frame timing or replace
a new phone review of these visual changes.
