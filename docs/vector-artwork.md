# Vector artwork and restored dock — 0.7.1+12

The low-resolution reference crops looked pixelated on the phone. All active
decorative artwork now uses twelve genuine SVG assets under
`assets/illustrations/vector/`, rendered by the shared `SpaceArtwork` widget
with `flutter_svg`. There are no embedded bitmap images, external resources,
filters or fonts in these SVGs.

The house/garden scenes, collection sticker, profile/greeting houses, empty and
delete illustrations, appearance thumbnails and three sample-member portraits
have been redrawn with vector paths and shapes. The approved cartoon composition
is preserved in a cleaner vector style; this is a redraw, not an exact tracing
of the generated reference. Library photographs remain real raster photos.
Custom/renamed profiles retain initials and saved avatar colors.

The previous Smooth Clay `SpaceNavigation` from commit `555cdb4` is restored:
soft capsule shading, the original clay page symbols and a shaded blue **circle**
behind the active page. Its 216 × 64 size, 48px targets, labels, reduced-motion
handling and tab-switch animation remain. Focused Photos search/selection still
hides the dock and preserves the existing Android Back behavior.

Page layouts, existing application logo, Nunito, button styling, photo data and
storage schema are retained. The previous PNG crops remain source material but
are excluded from the current asset bundle and are not referenced by UI code.

## Review and verification

- All twelve SVGs decode through the actual Flutter renderer. The decoder check
  also rejects embedded `<image>` elements and base64 data.
- Reviewed light/dark page renders, album-member portraits, appearance previews,
  confirmation and empty/recovery artwork. Photo-frame contents render as vector
  groups so they display correctly in the Flutter SVG compiler.
- Existing capture fixtures preload the SVG assets and real sample photos.
- Main and settings contact sheets: `output/previews/vector-main.png` and
  `output/previews/vector-settings.png`.
- All sixteen screens: `output/previews/vector-16-screen.png`.

Static analysis is clean and the full suite passes **88 tests**, including all
SVG decodes, persistence, role checks, large text/landscape, keyboard insets,
reduced motion and Android Back handling. Git whitespace checks pass.

Android release build and lint succeeded. Lint reports **0 errors, 1 existing
warning** for `enableOnBackInvokedCallback` on API <33, with existing fallback
Back handling retained. The toolchain also reports dependency/Gradle deprecations.

APK: `output/releases/homespace-android-0.7.1+12-preview.apk`, development signed,
package `com.homespace.homespace`, version `0.7.1` / code `12`, Android minimum
and target APIs `24` / `36`. APK signature verification passed. All twelve SVGs
were checked byte-for-byte against their packaged assets, and no old reference
PNG crop is present in the APK. The adjacent JSON records size, SHA-256 and
the current source revision/uncommitted-changes flag.

No phone installation or Git push was performed during this artwork update;
the prior installed version is 0.7.0+11. Screenshots are render fixtures, not a
new physical-device performance measurement.
