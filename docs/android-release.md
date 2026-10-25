# Android builds and signing

The app ID remains `com.homespace.homespace`. Versions come from `pubspec.yaml`.
The repository contains no production key, password or signing identity.

## Preview build

Run `flutter pub get` once after cloning, then on Windows:

```powershell
./scripts/build_android.ps1 -FlutterSdk C:/flutter
```

The script runs analysis, the full Flutter regression suite, a release-mode
APK build and Android release lint. It archives the APK and a JSON record with the version, Git revision,
uncommitted-change flag, signing mode, file size and SHA-256 under
`output/releases/`. A failed step stops packaging. The previous environment
setting is restored even after failure. No files are installed or published.

Preview builds explicitly use the existing development certificate so they can
update an installed preview without resetting its local library. Their artifact
names end in `-preview`; release mode is not production signing.

The Flutter SDK can also be supplied through `FLUTTER_ROOT`, or located from
`flutter` on PATH. The script requires an initialized Windows Flutter SDK and
Android SDK. Gradle lint also needs a compatible JDK through `JAVA_HOME` or `java`
on PATH. Generated artifacts are ignored by Git.

## Owner-signed production build

1. Keep the owner's upload keystore outside the repository.
2. Copy `android/key.properties.example` to the ignored `android/key.properties`.
   Set `storeFile`, `storePassword`, `keyAlias` and `keyPassword`. Use forward
   slashes and an escaped drive colon for Windows paths, as in the example;
   relative store paths resolve from `android/`.
3. Run:

```powershell
./scripts/build_android.ps1 -FlutterSdk C:/flutter -Production
```

Production mode additionally builds and archives an Android App Bundle. Gradle
requires a complete signing configuration and an existing keystore, then uses
that upload identity. Invalid or missing signing information fails the build;
production never falls back to the development certificate. The script does not
generate, rotate or upload keys, nor publish to a store.

For manual builds, `HOMESPACE_PRODUCTION=true` selects production signing. When
the environment setting is absent, Gradle also accepts `-Phomespace.production=true`.
Only the literal settings `true` and `false` are accepted. For preview builds leave
both unset or use `false`. The packaging script sets the environment explicitly,
so a global Gradle property cannot silently change the selected signing mode.

Preserve the established signing identity for updates to any distributed app.
An owner-signed artifact with a different identity is not an in-place update to
the development-signed preview. Signing/distribution and any transition of
existing installations need the owner's release configuration.

The configuration follows Flutter's [Android signing guide](https://docs.flutter.dev/deployment/android#sign-the-app).

## Native artwork

Regenerate the Android assets after changing the house artwork:

```sh
flutter test tool/export_android_branding.dart
```

Legacy PNGs are rendered from `SpaceHouse` at all five Android densities, in
rounded-square and circular variants. The exporter also writes the equivalent
native vector geometry, adaptive icons and Android 13 monochrome layer. If the
Flutter house geometry changes, update the vector paths in the exporter to match.
The exporter checks that the rendered foreground fits the 66dp safe circle.

Adaptive icons use 108dp layers in API 26 resources, including the monochrome
element used by Android 13+ and ignored by earlier Android versions.
The implementation follows [Android's adaptive-icon specifications](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive).

Android 7-11 launch backgrounds center the house on the app canvas. Android 12+
uses the system splash icon resource with a 288dp canvas and artwork inside the
192dp safe circle, following the [Android splash specifications](https://developer.android.com/develop/ui/views/launch/splash-screen).
No extra Activity, Flutter splash route, timer or forced startup delay is added.
The OS controls its launch transition. Native backgrounds follow device light/
dark appearance; the app applies its saved Appearance setting after local data
loads. Native launch resources cannot read Flutter's in-memory theme setting.

The Android lint configuration excludes `PropertyEscape` only for Flutter's
generated, ignored `android/local.properties`: the SDK writes Windows paths with
doubled backslashes and literal drive colons, which Java Properties parses
correctly. App resources and signing configuration keep the check enabled. The
288dp system splash drawable has a local `VectorRaster` exception because that
canvas is required by the splash specification and the app's minimum API needs
no vector-to-bitmap compatibility rasterization. No general lint baseline is used.

## Release validation still requiring a device or owner configuration

Verify cold/warm launch, OEM launcher masks, themed icons, safe areas, large text,
reduced motion and scrolling/frame timing on the intended Android devices. Test
updates with the intended signing identity and an existing saved library. APK
compilation and widget previews alone do not establish physical-device startup
or rendering performance. Server integration and real family-data transfers
remain outside the current frontend demo.
