# Phase 3 — photos, albums, and Trash

## Implemented

- Full-screen photo viewer, opened from the filtered library or an album. Its paging sequence stays stable while favorites change.
- Swipe paging, previous/next controls, pinch zoom up to 4x, animated double-tap/button zoom, and a reset control. Paging gestures pause while zoomed so a pan does not switch photos.
- Tap-to-hide controls, safe areas, a dark neutral photo canvas, and details with timestamp, category, album membership, and contributor attribution.
- Long-press or explicit photo selection, select all visible, batch favorite/unfavorite, multi-album assignment, and move to Trash. Back exits selection before leaving the page.
- Trash confirmation and an Undo action that remains usable after the viewer closes. Feedback sits above the floating navigation.
- Complete album pages with cover, description, role guidance, attributed photo grid, a multi-photo picker, and viewer navigation.
- Owners edit name/description, choose a cover, remove photos, and delete an album while keeping its media in the library and other albums.
- Contributors add photos and remove their own additions. Viewers browse. Controls reflect these rules, and repository operations enforce them.
- Member sheet for browsing roles, with owner controls to change a role, remove a member, or add an existing sample family member. Roles stay independent for each album. The owner remains fixed.
- Profile entry for Trash, trashed-photo viewing, single/batch restore, batch permanent deletion, and Empty Trash. Permanent deletion requires an explicit confirmation.
- Trash has no automatic expiration in this preview. Restore retains favorites and album membership; permanent deletion cleans references and cover choices.
- Batch operations save one validated snapshot, so a save failure changes none of the selected items. Failure dialogs retain the selection for retry.
- Screen-reader names, 48dp controls, double-size text/landscape layouts, and reduced motion. Reduced-motion paging uses a direct page change rather than a zero-duration scroll animation.
- Android system-bar colors and icon contrast on nested pages and the photo viewer.

## Data compatibility

Version 0.3.0+3 retains snapshot schema 1 and existing media/album IDs. It does not reset the saved library or replace user albums with new fixtures. No runtime dependencies or sample assets were added.

Library and album contracts now expose atomic batch actions, metadata editing, cover selection, and album deletion. Individual-item methods delegate to the batch implementations where appropriate. All changes still pass schema/reference validation and the existing serialized file-save queue.

## Local sharing preview

Membership changes persist on this device. No invitation, notification, network request, or external sharing occurs. Client roles are presentation and local-demo rules; the future server must enforce authorization independently.

## Remaining phases

Video playback and fixtures, device-media import, connection/authentication screens, upload management, real home-server integration, final launcher/splash assets, production signing, and release-quality performance checks remain ahead. The current library contains bundled sample photos.
