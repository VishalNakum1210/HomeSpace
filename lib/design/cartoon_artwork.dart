import 'package:flutter/material.dart';

import 'vector_artwork.dart';

/// Decorative artwork is excluded from semantics; adjacent text carries meaning.
class MemoryGarden extends StatelessWidget {
  const MemoryGarden({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: 128,
      width: double.infinity,
      child: SpaceArtwork('home-garden', fit: BoxFit.fill),
    ),
  );
}

class AlbumSticker extends StatelessWidget {
  const AlbumSticker({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SpaceArtwork(
      'album-sticker',
      width: 98,
      height: 70,
      fit: BoxFit.contain,
    ),
  );
}

class HouseGreeting extends StatelessWidget {
  final bool profile;
  const HouseGreeting({super.key, this.profile = false});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SpaceArtwork(
      profile ? 'profile-house' : 'greeting-house',
      width: 92,
      height: 82,
      fit: BoxFit.contain,
    ),
  );
}
