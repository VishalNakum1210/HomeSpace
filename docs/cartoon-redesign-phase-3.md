# Cartoon redesign — phase 3: album flows

## Layouts

- Album detail: rounded cover, title/description, actual memory count and shared
  status, member initials, a Members control, full-width tactile purple Add photos
  button, chronological grids and small contributor markers.
- Full-page Create/Edit album: cover preview and picker, title and description
  fields, and a bottom Save album button that stays above the keyboard.
- Photo picker: search, All/Favorites/Videos filters, selection count, blue checks
  and a fixed Add photos button. Selections survive search/filter changes and
  photos already in the album are excluded.
- Full-page members: album summary, member cards with role controls, owner-only
  Add family member action and accurate local sharing status.
- Permissions sheet: Viewer/Contributor option cards, Save permissions and
  confirmed member removal. The current owner has no role-change control.
- Shared purple album theme, existing Nunito, rounded cards and tactile buttons.
  Existing scalable artwork is reused; no new raster assets or dependencies.

## Behavior and compatibility

The existing owner/contributor/viewer rules still apply. Contributors add media
and remove their own additions; they cannot edit the album's metadata or members.
Membership changes apply only to the chosen album. There are no real invitations.

Cover selection stays in the editor's draft until Save. A new cover photo is
explicitly included in a new album. Existing albums can choose from their active
photo members. Canceling either picker or editor does not change saved metadata.

`createAlbum` and `updateAlbum` accept an optional cover ID. Metadata and cover
are validated and committed in one snapshot write. Failed saves leave all old
values intact and retain the UI draft for retry. Creation copies its photo list
before queuing. Invalid covers and unauthorized changes are rejected together.

Editing only a title/description does not replace a stored cover that is currently
in Trash. Restoring that photo still restores the original cover. Other stored
IDs, memberships, attributions, favorites and trash records remain unchanged.
The existing JSON schema is retained; no data migration or reset is needed.

Version: **0.4.2+6**.

## Verification

- Full suite: **68 tests passed**, including the previous 58 checks.
- Three new data checks cover explicit cover creation, immutable arguments,
  cover/ownership validation, atomic failed-save rollback and restart persistence.
- Seven new UI checks cover draft/save/retry flows, restoring a trashed cover,
  filter-preserved selections, permission drafts, narrow/landscape and large text,
  keyboard insets, labels, contrast and touch targets.
- Flutter analysis: no issues found. Git whitespace check passed.
- Eight actual widget renders reviewed at 390 × 844, exported at 2×. These are
  test-renderer previews, not physical-phone screenshots.

Reproduce previews:

```sh
flutter test test/cartoon_album_flows_test.dart --dart-define=HOMESPACE_CAPTURE=true
```

Preview files under `output/previews/cartoon-phase-3-`:

- `album-light.png` / `album-dark.png`
- `create-album.png` / `edit-album.png`
- `add-photos.png`
- `members-light.png` / `members-dark.png`
- `permissions.png`

## Android artifact and remaining work

The release-mode APK is archived at
`output/releases/homespace-cartoon-phase-3-android.apk`.
It retains development signing. This phase has not been installed on the physical
phone; that phone currently has phase 2, version 0.4.1.

Final build: 85 seconds; APK size: 54,441,380 bytes.
SHA-256: `59C871F13DE79CD7CA283A290FB8CC4224DE51761D2E5278834A3A2E1F0D812F`.

Phase 4 remains: profile editing, Appearance, Trash, confirmation and recovery
layouts. Real server integration, upload/import, video playback and invitations
remain separate functional work. The reference's generated faces are represented
by actual local member initials, and photo/count data comes from the saved library.
