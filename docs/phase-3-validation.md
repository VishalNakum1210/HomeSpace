# Phase 3 validation — Android photo and album flows

## Automated results

- Flutter static analysis: clean, no issues.
- Full suite: 53 tests passed in 47 seconds, including all 33 previous checks.
- Seven new repository checks cover atomic favorites/Trash/deletion, failed batch writes, copied selection arguments, contributor attribution/removal rules, owner-only editing/covers/deletion, and restart compatibility.
- Thirteen new UI checks cover swipe/zoom/paging, stable filtered sequences, details, Trash confirmation and Undo after closing the viewer, selection actions, member roles/removal/addition, album editing and deletion, save-error recovery, restore/permanent-delete persistence, and navigation while feedback is visible.
- New screens also pass checks at 320x700 and 740x360 with double-size text. Viewer/member controls pass Android tap-target, labeling, and text-contrast guidelines.
- Reduced-motion route transitions, double-tap zoom, and immediate paging pass. The check caught a zero-duration scroll assertion, which was fixed by using a direct page change.
- Source formatting and Git whitespace checks completed.

## Android build and smoke check

- Successful release-mode APK build; this build took 258.9 seconds.
- Installed and verified package version 0.3.0, build 3.
- Android 13 / API 33 Google APIs x86_64 emulator, Pixel 6 profile, 540x1200 at 210 dpi (roughly 411dp wide), two CPU cores, 1024 MiB guest RAM, software graphics.
- Exercised photo swipe and zoom, move to Trash and Undo, collection navigation, album pages, member-role change, appearance selection, and the Trash page.
- Selected Dark, changed Sam from viewer to contributor in Family weekends, and moved media-01 to Trash. After force-stop/relaunch in a new process, the dark theme, member role, and trashed photo were retained. The album cover also fell back to an available photo while its original cover was trashed.
- Checked light and dark system bars and inspected ten unedited screenshots of the final APK.
- No AndroidRuntime or Flutter error entries were returned for the checked final app process.
- The temporary emulator was shut down after verification. No physical phone was connected for this phase, so the existing phone installation was not updated.

The emulator showed Gboard and System UI startup ANR dialogs. Closing those emulator components allowed normal HomeSpace interaction and capture to continue. App/system animation settings were left unchanged. Emulator launch timings are not representative of phone performance; release-quality performance and physical-device checks remain outstanding.

## Preview artifact

- File: output/releases/homespace-phase-3-android.apk
- Size: 53,188,276 bytes (50.7 MiB).
- Package: com.homespace.homespace
- App version: 0.3.0+3
- SHA-256: 2361CF6DA6EB9DA9F54EC77B32C9033A2B82940E5AA38DAC3B895F7260D5AAF2

This preview uses development signing. APKs, screenshots, and logs are local ignored artifacts; the following links resolve in the workspace rather than on GitHub.

## Actual Android screenshots

| Flow | Evidence |
| --- | --- |
| Photos | [Light](../output/previews/phase-3-photos-light.png), [Dark after restart](../output/previews/phase-3-photos-dark-after-restart.png) |
| Collections | [Light](../output/previews/phase-3-collections-light.png) |
| Photo viewer | [Photo](../output/previews/phase-3-viewer.png), [Next photo zoomed](../output/previews/phase-3-viewer-zoom.png) |
| Album details | [Light](../output/previews/phase-3-album-light.png), [Dark](../output/previews/phase-3-album-dark.png) |
| Members | [Original roles](../output/previews/phase-3-members-light.png), [Changed role after restart](../output/previews/phase-3-members-dark-after-restart.png) |
| Trash | [Saved item in Dark](../output/previews/phase-3-trash-dark.png) |

The library uses bundled sample photos. Membership changes are local simulations; no invitation, upload, or server request occurred. Video playback, import, connection/authentication, uploads, server integration, and production packaging remain in later phases.
