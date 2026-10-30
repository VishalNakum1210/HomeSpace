# HomeSpace artwork

## Current vector artwork

`vector/` contains twelve standalone, editable SVG illustrations redrawn for
HomeSpace 0.7.1. They use paths, shapes, fills and transforms, with no embedded
bitmap data, external images or web fonts. Flutter renders them through
`SpaceArtwork` and `flutter_svg`.

- `home-garden.svg`: house mascot, leaves and illustrated photo frames.
- `album-sticker.svg`: stacked landscape picture and purple album.
- `greeting-house.svg`, `profile-house.svg`: house decorations.
- `empty-garden.svg`, `delete-house.svg`: empty/recovery and confirmation art.
- `theme-light.svg`, `theme-dark.svg`, `theme-system.svg`: appearance previews.
- `maya.svg`, `alex.svg`, `sam.svg`: cartoon sample-member portraits.

These redraw the approved cartoon composition with smooth vector geometry.
They are not a pixel-exact tracing of the flattened reference sheet. Labels
remain native Flutter text. Illustrations are decorative and excluded from
screen-reader semantics; adjoining labels supply context.

The sample portraits apply only to unchanged demo identities. Renamed/custom
profiles retain initials and their saved avatar-tone controls. The application
logo remains the existing native Flutter artwork in `space_symbols.dart`.
The restored Smooth Clay dock is also drawn natively, with its previous shaded
page icons, soft capsule and circular blue selection.

## Earlier raster sources

`reference/` preserves the low-resolution PNG crops from the approved generated
1024 × 1536, 16-screen sheet. Those crops are no longer bundled or used by the
application. The original sheet remains a local ignored artifact at
`output/design-reference/cartoon-16-screen-reference.png`, originally generated
as `exec-67a67b0d-c10f-4a08-9645-03441e293962.png`.

`memory-garden.png` is the earlier 2135 × 736 transparent image-generation
illustration retained as source material. It is not used by the current UI.
Actual library photos remain raster photographs; their sources are recorded in
`assets/photos/SOURCES.md`.
