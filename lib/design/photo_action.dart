import 'package:flutter/material.dart';

/// Shared labeled controls for photo selection and the full-screen viewer.
class PhotoAction extends StatelessWidget {
  final String label;
  final String tooltip;
  final IconData icon;
  final Color tone;
  final VoidCallback? onPressed;
  final bool filled;
  final bool? selected;
  const PhotoAction({
    super.key,
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.tone = const Color(0xFFA560F5),
    this.filled = false,
    this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = !filled
        ? (selected == true ? const Color(0xFFFFA8BC) : const Color(0xFFF2F3F5))
        : dark
        ? Color.lerp(tone, Colors.white, .65)!
        : Color.lerp(tone, const Color(0xFF171B32), .65)!;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      selected: selected,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: ExcludeSemantics(
          child: Material(
            color: filled
                ? tone.withValues(alpha: dark ? .18 : .11)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 10,
                  ),
                  child: Opacity(
                    opacity: onPressed == null ? .45 : 1,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: ink, size: 24),
                        const SizedBox(height: 5),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
