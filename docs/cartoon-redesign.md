# Cartoon redesign implementation

The approved reference is the 16-screen HomeSpace design sheet from this chat.
Keep the smiling green house with orange roof, Nunito, tactile solid buttons,
green/purple/orange page accents, and icon-only floating dock with a blue circle.

## Phases

1. **Main pages and visual foundation — complete.** Photos, Collections and Profile; reusable
   branded header; illustrated photo banner; pastel album cards; shared spacing;
   light/dark and larger-text layouts. Keep current repositories and stored data.
2. **Photo flows — complete.** Search/selection, full-screen viewer, details and action bars
   (reference screens 02–04). Preserve zoom, paging and selection behavior.
3. **Album flows — complete.** Album detail, create/edit, media picker, members and permissions
   (06–10). Apply existing owner/contributor/viewer rules.
4. **Settings and recovery — complete.** Edit profile, Appearance, Trash, confirmations and
   empty/offline states (12–16); Android verification and release APK.

## Fixed implementation values

- 20dp horizontal page inset; spacing based on 8dp.
- Nunito, existing weights and font files.
- Minimum 48dp touch targets, larger-text support and Android safe areas.
- Existing SpaceButton: 18dp corners, 54dp minimum height, 4dp lower ledge.
- 22dp cards; compact 216 × 64dp dock; 48dp circular blue selected background.
- Page accents: #58CC02, #A560F5, #FF9600. Canvas: #FFFEFC.
- Button press/release 80/160ms, tab movement 220ms; respect reduced motion.

## Assets and fidelity

The reference is a flattened AI-generated picture, not an SVG design file.
Archive it with the preview artifacts. Retain the existing code-drawn logo and
Nunito; recreate the photo-header artwork as a dedicated transparent PNG and
the small album/profile decorations as scalable Flutter artwork. Existing saved
media, names, counts and memberships remain real application data rather than
the invented values in the picture. Original sample media is retained; the
reference's additional generated family photographs are not separate originals.

Reference role descriptions are visual examples: contributor permissions in the
application continue to follow the repository's implemented rules.

Phase 1 does not replace secondary flow layouts or add a server, real invitations,
uploads, device-media import, or playback. Those are separate functional work.
