# Frontend phase 5: home server and upload queue

The four cartoon redesign phases are complete. This phase extends their visual
language to the connection and upload screens deferred in the original frontend
plan. It keeps Android-only scope, the original house, Nunito, raised buttons,
existing tab layouts and Smooth Clay navigation. No packages or assets were added.

## Home server

- Profile has a Home server row with live session status.
- A full-page address form supports HTTP/HTTPS, LAN hosts, IPv6, ports and reverse
  proxy paths. It rejects missing schemes, whitespace, invalid ports, credentials,
  query parameters and fragments. The form and adapter share validation.
- Disconnected, connecting, connected, offline and failed states have explicit
  messages and cancel/disconnect/retry actions. A connected address is read-only
  and stays readable. The connected state links to the sample upload queue.
- Canceling or superseding a pending connection prevents a late result from
  replacing the current status. Disposal also invalidates pending attempts.
- Keyboard insets, scrollable content and reduced-motion loading are supported.

## Upload queue

- Profile has an Upload queue row; the page also opens from Home server.
- A summary shows completed item counts. All/Active/Finished filters retain queue
  history. Completed and canceled items are finished; failed items stay active.
- Active cards show local photo thumbnails/titles, phase and labeled sample
  progress. Unavailable or trashed photos use a placeholder.
- Per-item pause/resume/retry, Pause all, Resume all and Retry failed update the
  queue immediately. Finished views hide active-item batch controls.
- Cancellation requires confirmation and preserves library photos and albums.
- Empty and no-active-item states use the original house artwork. Cards and
  wrapped controls adapt to large text and narrow/landscape screens.

## Data boundaries

These pages use the existing connection/upload interfaces and demo repositories.
They make no requests, send no files, collect no login credentials and import no
device media. Fixture progress only changes through explicit fixture controls;
there is no timer pretending to upload files. Offline and failed connection
outcomes can be exercised through the existing scenario fixtures.

Connection addresses and queue changes last for the app session and are reset on
restart or scenario reset. Library/profile persistence keeps the existing schema.
No saved photos, favorites, albums, memberships or Trash records are migrated or
reset by these pages. Real server authorization and transfers remain future work.

Version: **0.5.0+8**.

## Verification

- Full regression suite: **84 tests passed**, including the previous 75 checks.
- Two new adapter checks cover LAN/IPv6/port validation, rejecting secret/malformed
  URLs, disposal and overlapping connection attempts.
- Seven new UI checks cover Profile routing, connected status updates, validation,
  failure/offline retry, pending cancellation, queue filters/actions/history,
  canceled confirmation, batch actions, unavailable media, dark/empty states,
  saved-data preservation, large text, keyboard insets, landscape, Android touch
  targets, screen-reader labels and text contrast.
- Flutter analysis: no issues found. Git whitespace check passed.
- Eleven actual Flutter widget renders reviewed at 390 x 844, exported at 2x.
  These are test-renderer previews, not physical-phone screenshots.

Reproduce previews:

```sh
flutter test test/connection_upload_flows_test.dart --dart-define=HOMESPACE_CAPTURE=true
```

Preview prefix: `output/previews/frontend-phase-5-`.

- `server-disconnected.png`, `server-connecting.png`, `server-connected.png`
- `server-offline.png`, `server-failed.png`, `server-dark.png`
- `queue-light.png`, `queue-dark.png`, `queue-finished.png`, `queue-empty.png`
- `queue-cancel.png`

## Android artifact and next phase

APK: `output/releases/homespace-frontend-phase-5-android.apk`.
It uses development signing and has not been installed on the physical phone.

Build succeeded in 103.7 seconds. APK size: 54,720,152 bytes. Package:
`com.homespace.homespace`, version name `0.5.0`, version code `8`.
SHA-256: `1BD07DE7A5BF0BE487D602897886F2EF62C70D04A3B73CFF5031B0AD174FDBBC`.

The next frontend phase is Android launcher/splash branding and release-preparation
checks. Production signing/distribution needs the owner's signing configuration.
Server authentication, actual uploads/import, playback and real invitations are
separate functional work.
