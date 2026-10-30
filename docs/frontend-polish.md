# Gesture and control-flow review — 0.7.2+13

This review keeps the current layouts, SVG illustrations, Nunito, logo and
Smooth Clay dock. It addresses interaction and routing in the Android frontend;
the home-server and upload experiences remain explicit local simulations.

## Reproduced and fixed

### Pinch-to-zoom without an unlocking tap

A first finger moving horizontally could let PageView win the gesture before
the second finger arrived. The pinch then stayed at 1x. A longer swipe also
exposed a second image with a different gesture recognizer.

One viewport now coordinates the whole pointer sequence. At 1x, single-finger
horizontal drags drive the page controller and retain normal drag/snap behavior.
A second finger cancels paging, restores the original page and immediately
pinches that image. At zoom, one finger pans; releasing/replacing fingers does
not require a tap. A pinch remains a photo gesture until all fingers lift, even
if it ends at 1x. The next single-finger drag can then change photos.

Double-tap and accessible menu zoom/paging remain available. Paging buttons
reset the current transform before moving, and canceled drags are cleaned up.
Five actual multi-pointer tests cover small drift, a long swipe exposing the
next page, one-finger continuation, cancellation and the next pan/pinch/swipe.
The original drift and long-swipe cases failed before the coordinator fix.

### Async saves during Back/dismissal

A popped route remains mounted while its reverse animation runs. Checking only
`context.mounted` allowed a save completing during that animation to pop the
album/Members screen underneath. A failed save could also display a dialog on
an unrelated screen after Back.

Save completions now check that their route is still current before closing it
or displaying a save error. The shared guard covers profile/appearance,
album creation/editing/picking, member controls and viewer restore/delete flows.
Three delayed-write tests reproduced these failures and now pass. Saving while
leaving still completes the requested write; failure leaves saved data intact.

### Old bulk actions clearing new selections

Leaving a selection during a pending write, then selecting another photo,
allowed the old completion to clear the new selection. A regression test
reproduced this. Photos, albums and Trash now associate completion callbacks
with the selection revision that started the action. Back, toggling an item and
Select all invalidate earlier selection completions.

## Application-wide review

The full suite exercises Photos filters/search/selection, viewer paging and
details, Collections, album creation/edit/cover picking, photo picking, member
roles, Profile/Appearance, Trash, recovery and the simulated connection/queue.
It includes canceled actions, failed saves/retry, persisted-state recreation,
large text, narrow/landscape layouts, keyboard insets, touch targets and reduced
motion. Cross-tab Android Back behavior remains covered.

Additional redirect checks cover creating/canceling an album from selected
photos and the details → album → details → same viewer → library Back sequence.
No data reset or storage-schema change is included.

## Validation and delivery

- Full suite: **99 tests passed**, including eleven new gesture, routing and
  stale-selection checks.
- Flutter analysis: **no issues**. Git whitespace check passes.
- Refreshed all sixteen screen captures and reviewed their composition. Local
  contact sheet: `output/previews/frontend-polish-16-screen.png`.

- Android release build succeeded (226.3 seconds). Release lint succeeded with
  **0 errors and 1 existing `UnusedAttribute` warning** for the API 33+
  Back-callback flag on older supported Android versions. Toolchain/Gradle
  deprecation warnings remain; no configuration migration was needed here.
- APK signature verifies. Package: `com.homespace.homespace`, version/code
  `0.7.2` / `13`, Android minimum/target APIs `24` / `36`.
- APK: `output/releases/homespace-android-0.7.2+13-preview.apk`, **56,296,403
  bytes**, SHA-256
  `FFCEE63FAFAADB17F8C8DA1828F3354531844670D5EF485C6F1CAF8A24C83352`.
  Adjacent JSON records the code revision and development signing mode.
- Installed with `adb install -r` on the connected Xiaomi, retaining the
  first-install record and saved data. Launch succeeded; the app remained
  foreground and its process log had no match for the checked fatal/unhandled
  Flutter error patterns. The phone screenshot retains the saved blue avatar
  and existing dated library: `output/phone/frontend-polish-startup.png`.
- Physical pinch/pan feedback was requested from the user because this phone
  blocks automated touch injection. Automated multi-pointer checks passed;
  manual gesture confirmation was still pending when this note was recorded.
- Source fixes, existing layout improvements and SVGs were committed and pushed
  to `origin/main` as `4b0b182`. This document's delivery notes are a follow-up.

Render previews and APKs remain ignored artifacts.
Automated checks establish the tested behavior, not a universal “10/10” score
or a physical-device frame-timing certification. Real server/authentication,
device import, uploads/synchronization, invitations and video playback remain
separate integration work.
