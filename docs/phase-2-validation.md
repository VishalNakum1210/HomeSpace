# Phase 2 validation — local persistence on Android

## Results

- Flutter static analysis: clean, no issues.
- Full test suite: 33 tests passed. Coverage includes the nine design checks, real-file persistence/recovery, future-schema preservation, serialized writes, role rules, multi-album membership, demo repositories, and UI save/restart behavior.
- Appearance/system-brightness test: passed again after explicitly selecting Android navigation icon brightness for light and dark themes.
- Android release-mode APK: built successfully; final incremental build took 46.8 seconds.
- Installed version 0.2.0 (build 2) on the connected Redmi Note 11 running Android 13, at its normal 1080x2400 resolution.
- The user selected Dark manually. After a force-stop and cold launch, the app ran in a new process and restored Dark. The launch-wait command reported 886 ms; this is a single observation, not a performance benchmark.
- Installed the final APK with the navigation contrast adjustment using an in-place update. Dark remained selected after this update and relaunch.
- Inspected actual before/restart/update screenshots. No AndroidRuntime or Flutter error entries were returned for the checked app processes.
- Phone system settings and saved app data were kept. Xiaomi blocks injected taps, so the appearance-selection step was manual; the restart, installation, version check, screenshots, and log inspection used ADB.

## Preview artifact

- File: output/releases/homespace-phase-2-android.apk
- Size: 52,056,244 bytes (49.6 MiB).
- Package: com.homespace.homespace
- App version: 0.2.0+2
- SHA-256: 828DEF854D4BAD14AAAE64BD0C1B54125136F0C9C9A30AF8B7994F6E84323571

This is a development-signed frontend preview built in release mode. Final branding, production signing, and release-quality performance checks remain in later phases. APKs, logs, and screenshots are local ignored artifacts, so these relative artifact links work in the workspace rather than on GitHub.

## Actual phone screenshots

- [Dark Collections before restart](../output/previews/phase-2-phone-before-restart.png).
- [Dark Photos after full process restart](../output/previews/phase-2-phone-after-restart.png).
- [Dark Photos after installing the final APK](../output/previews/phase-2-phone-after-update.png).

These are unedited ADB screencaps. The screenshots span two builds: the final image includes the explicit navigation icon brightness adjustment.

## Scope and limits

Local profile, appearance, favorites, album membership, roles, and trash metadata have real persistence. File tests cover backup/pending recovery, damaged bytes, unsupported schema versions, failed writes, and subsequent successful saves. UI tests recreate the app with stored state and verify save-error dialogs above modal sheets.

The library still uses bundled sample media. Phone verification specifically confirmed theme persistence across process restart and APK update; the automated tests cover the other local state. Full media viewing, member management, Trash, connection, and upload screens remain in later phases. Connection and upload repositories are explicit simulations, and no server, authentication, upload, or external sharing is implemented.
