import 'package:flutter/material.dart';

import 'vector_artwork.dart';

/// Scalable house and photo-frame illustration for empty/recovery states.
class HouseStateArt extends StatelessWidget {
  final IconData icon;
  const HouseStateArt({super.key, this.icon = Icons.photo_outlined});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 238,
      height: 126,
      child: Stack(
        children: [
          Positioned.fill(
            child: SpaceArtwork('empty-garden', fit: BoxFit.contain),
          ),
          if (icon != Icons.photo_outlined &&
              icon != Icons.photo_library_outlined)
            Positioned(
              right: 28,
              top: 36,
              child: Icon(icon, color: const Color(0xFF72BDE8), size: 28),
            ),
        ],
      ),
    ),
  );
}

class MemoryStatusBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final bool warning;
  const MemoryStatusBanner({
    super.key,
    required this.message,
    this.onRetry,
    this.warning = false,
  });
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warning
            ? (dark ? const Color(0xFF3E3020) : const Color(0xFFFFF3DF))
            : dark
            ? const Color(0xFF243844)
            : const Color(0xFFEAF5FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            warning ? Icons.wifi_off_rounded : Icons.info_outline_rounded,
            color: warning
                ? const Color(0xFFFF9600)
                : dark
                ? const Color(0xFFA5D8FF)
                : const Color(0xFF245C86),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: warning
                    ? Theme.of(context).colorScheme.onSurface
                    : dark
                    ? const Color(0xFFDCEBFF)
                    : const Color(0xFF245C86),
              ),
            ),
          ),
          if (onRetry != null)
            warning
                ? FilledButton(
                    onPressed: onRetry,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF9600),
                      foregroundColor: const Color(0xFF171B32),
                    ),
                    child: const Text('Retry'),
                  )
                : TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
