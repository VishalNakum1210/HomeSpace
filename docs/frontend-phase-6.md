# Frontend phase 6: native branding and release preparation

Version: **0.6.0+9**. The existing app ID and stored-library schema are retained.

## Implemented

- Replaced Flutter launcher placeholders with the existing green smiling house
  and orange roof. Legacy rounded-square and circular PNGs cover mdpi through
  xxxhdpi. Android 8+ adaptive icons use native vector layers; Android 13+ includes
  a monochrome house with transparent eyes and smile for themed launchers.
- Added branded launch resources for Android 7-11 and the Android 12+ system
  splash, with native light/dark backgrounds matching the app canvas. The OS
  controls the transition; no delay, extra Activity or second splash page is added.
- Added a repeatable Flutter asset exporter and a pixel-based launcher safe-area
  check. App pages, navigation, typography, buttons and in-app logo are unchanged.
- Added explicit owner-signing configuration and an example properties file.
  Missing/incomplete production signing fails rather than using a development
  certificate. Preview builds retain their existing signing/update path.
- Added a Windows build script that runs analysis/tests and native lint, creates the Android APK
  and archives it with a version/revision/size/hash/signing record. Production mode
  also creates an App Bundle. It installs and publishes nothing.
- Documented build modes, credential handling, artwork regeneration and device
  validation in [Android release preparation](android-release.md).

## Validation

- Flutter analysis: no issues found.
- Full regression suite: **84 tests passed**. No library migration or reset.
- Explicit branding export: passed. All five legacy densities and both shapes
  were generated; the visible foreground pixels fit the 66dp safe circle.
- Final Android release lint: **no issues found**. API-specific navigation-bar
  settings are qualified to Android 8.1+; the obsolete v21 resource was removed.
  The two narrow, documented SDK/specification exceptions are in the release guide.
- PowerShell script syntax and preview packaging/metadata were checked. Both
  the script and Gradle rejected production mode without signing configuration.
  Java Properties correctly loaded the SDK-generated Windows directory values.
- Final APK signature verified with `apksigner`; its certificate matches the
  phase-five development preview. Package/version/minimum/target SDK verified
  with `aapt`: `com.homespace.homespace`, `0.6.0`, build `9`, API 24 / API 36.
- Git whitespace check passed. The native resource cache was refreshed after
  removing the obsolete resource variant; the final build and lint both passed.

Final APK: `output/releases/homespace-android-0.6.0+9-preview.apk`.
Final APK build: 97.0 seconds. Size: **54,762,596 bytes**.
SHA-256: `C9391FBB5572BD419DAE1A0F163B547302CE029C44523111F4A606DF799C8975`.
The accompanying `.json` records the build's revision, dirty flag and signing mode.

The export previews under `output/previews/android-phase-6-` are Flutter renders
of the existing artwork and placement, not physical Android launcher/splash
screenshots. Native vectors and resources are checked by Android packaging/lint.

No physical phone was detected in this phase. Production keys were not supplied,
so no owner-signed production APK/App Bundle or store release is claimed. Native
launch follows Android's device theme before the app loads its saved Appearance.

## Remaining work

Physical-device cold/warm startup, frame timing, OEM launcher masks and themed
icons still require device validation. Production signing and distribution need
the owner's established signing configuration. Server authentication, actual
uploads/import, video playback and real sharing remain separate functional work.
There is no additional automatic frontend phase after this release-preparation
scope; the next functional phase needs a concrete server/API or media-integration
choice.
