# Frontend phase 7: Android device validation and navigation polish

Scope chosen by the user: Android testing and frontend polish. No server,
import/upload or new layout work. Final patch version: **0.6.1+10**.

## Phone validation

On 2026-10-26, the connected Redmi Note 11 (2201117TI) was running Android 13,
API 33, at 1080 x 2400, density 440 and font scale 1.0. No device display, theme,
animation or debugging-security settings were changed. Xiaomi blocks injected
taps, so no automated tap/gesture workaround was attempted.

The installed app was 0.4.2+6. It was updated with `adb install -r` to the verified
0.6.0+9 preview without uninstalling or clearing data. Before/after screenshots
show the same blue avatar, favorite markers, stored dates and first group of
five photos; the original first-install timestamp was retained.

The user reported no clipping, freezes or awkward behavior after the requested
Photos scroll/viewer swipe/zoom, Collections/album, Appearance preview and Trash
checks. This is a manual report on 0.6.0, distinct from automated test evidence.
The captured session screenshot shows the scrolled Photos page. The app process
log captured after the check contained no `FATAL EXCEPTION`, `Unhandled Exception`,
`FlutterError` or `OutOfMemoryError` match. OEM diagnostic warnings are not treated
as proof of application failure or as a complete crash history.

Three process-cold launches (`am force-stop`, then `am start -W`) reported
TotalTime **1584, 1578 and 1530 ms** for 0.6.0. These are ActivityManager display
measurements from a small local sample, with OS/file caches retained. They are
not Flutter build/raster timings or evidence of scrolling frame rate. A repeated
intent to the already foreground activity was delivered without starting another
activity; it is not reported as a warm-start benchmark.

A single pre-update 0.4.2 launch reported 726 ms. The versions were not compared
under controlled install/profile/cache conditions; these observations do not
establish a startup improvement or a quantified regression.

Local evidence: `output/qa-phase-7/` (ignored screenshots and diagnostic logs).

## Navigation fix

Two regression tests reproduced a hidden-tab issue: after searching or selecting
photos, switching to Collections/Profile and pressing Android Back returned to
Photos but also cleared its search or selection. Its PopScope was receiving the
Back attempt while the Photos tab was inactive.

The app now supplies the Photos tab's active state. Its Back handler participates
only while visible. Back from another primary tab returns to Photos with the
query/selection intact; a subsequent Back on Photos clears that transient mode.
Both tests exercise Collections and Profile and verify that stored data is not
changed. Existing layout, artwork, Nunito, buttons and navigation styling are kept.

The manual session also exposed Android's disabled-back-callback warning. The
manifest now enables `android:enableOnBackInvokedCallback`, following
[Flutter's Android Back guidance](https://docs.flutter.dev/platform-integration/android/predictive-back).
Existing PopScope handling and custom route animations are retained. Gesture
animation behavior across other OEMs/Android versions still needs device checks.

## Final verification and artifact

- Two new regression tests failed before the fix and passed afterward. Both
  exercise Collections and Profile, preserve the query/selection on the first
  Back, clear it on the next Back, and leave the stored snapshot unchanged.
- Full release pipeline: **86 tests passed**, analysis clean and Android release
  lint passed with zero errors and one expected `UnusedAttribute` warning: the
  Back-callback flag applies on API 33+ and is ignored on older supported Android
  versions, which retain existing Back handling. The warning is not suppressed.
  The APK build took 115.2 seconds. Git whitespace check passed.
- APK signature verified; the development certificate matches 0.6.0. The packaged
  manifest contains the enabled Back-callback flag. App ID remains
  `com.homespace.homespace`; minimum/target Android APIs remain 24/36.
- Installed **0.6.1+10** on the connected phone with `adb install -r`, retaining the
  original first-install timestamp and without clearing app data. Launch succeeded.
  Its first post-update ActivityManager TotalTime was 3377 ms; this single fresh
  update launch is not a controlled startup comparison with the earlier samples.
- The user confirmed the final search/Collections/Back/Back behavior on 0.6.1.
  A later screenshot captured continued Photos search use, with HomeSpace still
  foreground. The final process log contained no match for the listed fatal/
  unhandled error patterns or the earlier disabled-Back-callback warning.

APK: `output/releases/homespace-android-0.6.1+10-preview.apk`.
Size: **54,762,616 bytes**.
SHA-256: `FBEB2987670D2D48E4A3C932558C1E3689ADB5B1AABCBDFCB3E1A8B9F2485089`.
The adjacent JSON records the build revision, dirty flag and signing mode.

Gesture animations on other Android versions/OEMs, themed-launcher masks and
Flutter frame-timing profiling remain separate device-validation work; no claim
of production performance certification is made from this limited phone check.

Production signing and distribution still require owner configuration. Real
server requests, invitations, imports and video playback remain outside this
frontend validation phase.
