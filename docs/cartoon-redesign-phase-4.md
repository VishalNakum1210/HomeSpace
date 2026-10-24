# Cartoon redesign — phase 4: settings and recovery

## Layouts

- Full-page Edit profile: avatar preview, name input, four color choices and a
  bottom Save changes button above the Android keyboard.
- Full-page Appearance: Light/Dark/System cards with miniature previews, blue
  checked outlines, the original house illustration and a bottom Done button.
  The page and Android system-bar icons preview the draft brightness immediately.
- Trash: centered count, three-column photo grid, purple Restore and raised red
  Delete selection actions below the grid, followed by Empty Trash. Dates remain
  available to screen readers. Large text uses stacked actions.
- Rounded confirmation dialogs: original house, explicit message, tactile Cancel
  and confirm buttons, and red destructive actions. Narrow/large-text dialogs
  scroll and stack their controls.
- Empty, loading and recovery screens: scalable garden/photo-frame artwork using
  the existing logo, readable messages and appropriate retry/explore actions.
- Photos now displays saved-library recovery notices as well as offline and
  success banners. Simulated retries return to the saved library.

The main pages, logo, Nunito, Smooth Clay dock and default button style are kept.
Motion/accessibility information and About remain available as existing sheets.
No new packages or raster assets were added.

## Behavior and compatibility

Profile edits and appearance changes stay in drafts until Save/Done. Back cancels
without writing. Failed saves retain the draft, keep the previous saved values and
allow retry. System appearance tracks device brightness before and after saving.

Trash restoration preserves favorites and album membership. Permanent deletion
requires confirmation; canceling leaves records intact. Trash has no automatic
expiry. Boot errors keep saved files and offer retry without resetting the library.
Demo empty/offline/error states do not overwrite stored snapshots.

Version: **0.4.3+7**. The JSON schema and existing local library are preserved.

## Verification

- Full suite: **75 tests passed**, including the previous 68 checks.
- Seven new UI checks cover theme preview/cancel/restart persistence, System
  brightness changes, profile drafts and failed-save retry, Trash restoration and
  confirmed deletion, recovered/offline/empty/failed/boot states, large text,
  landscape, keyboard insets, accessibility labels, contrast and touch targets.
- Flutter analysis: no issues found. Git whitespace check passed.
- Twelve actual widget renders reviewed at 390 × 844, exported at 2×. These are
  test-renderer previews, not physical-phone screenshots.

Reproduce previews:

```sh
flutter test test/cartoon_settings_flows_test.dart --dart-define=HOMESPACE_CAPTURE=true
```

Preview files under `output/previews/cartoon-phase-4-`:

- `edit-profile.png`
- `appearance-light.png` / `appearance-dark.png`
- `trash-light.png` / `trash-dark.png` / `trash-empty.png`
- `delete-confirmation.png`
- `empty-library.png` / `offline-library.png` / `recovered-library.png`
- `failed-preview.png` / `recovery-error.png`

## Android artifact and remaining work

The release-mode APK is archived at
`output/releases/homespace-cartoon-phase-4-android.apk`.
It retains development signing. This phase has not been installed on the physical
phone; the latest installation is phase 3, version 0.4.2.

Final build: 174.7 seconds; APK size: 54,457,400 bytes.
SHA-256: `9B87378F155BF97CF0ABB9C0091EF020EE7DAAEA048F1BDABBD1DD322167AC84`.

All four cartoon redesign phases are complete. Real server integration,
authentication, upload/import, video playback, real invitations and production
release signing remain separate functional work. Photo/count/member data comes
from the saved local library; generated reference photographs are not separately
available source assets.
