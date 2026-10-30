import 'package:flutter/material.dart';

import 'space_symbols.dart';
import 'space_theme.dart';
import 'state_artwork.dart';

class SpaceCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  final Color? borderColor;
  final EdgeInsetsGeometry padding;
  const SpaceCard({
    super.key,
    required this.child,
    this.color,
    this.borderColor,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Material(
      color: color ?? Theme.of(context).colorScheme.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: borderColor ?? SpaceStyle.of(context).border,
          width: 1.5,
        ),
      ),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class SpaceButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  const SpaceButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
  });
  @override
  State<SpaceButton> createState() => _SpaceButtonState();
}

class _SpaceButtonState extends State<SpaceButton> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    final style = SpaceStyle.of(context);
    final enabled = widget.onPressed != null;
    final foreground = enabled
        ? widget.foregroundColor ?? const Color(0xFF171B32)
        : style.muted;
    final background = widget.backgroundColor ?? style.accent;
    return Semantics(
      button: true,
      enabled: enabled,
      child: AnimatedContainer(
        duration: spaceMotion(context, pressed ? 80 : 160),
        transform: Matrix4.translationValues(0, pressed ? 3 : 0, 0),
        decoration: BoxDecoration(
          color: enabled ? background : style.border,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: enabled
                  ? widget.backgroundColor == null
                        ? style.edge
                        : Color.lerp(background, Colors.black, .2)!
                  : style.border,
              offset: Offset(0, pressed ? 1 : 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: widget.onPressed,
            onHighlightChanged: (value) => setState(() => pressed = value),
            borderRadius: BorderRadius.circular(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 54),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 13,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, color: foreground, size: 22),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
                      child: Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelLarge!
                            .copyWith(color: foreground),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SpaceFilter extends StatelessWidget {
  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;
  const SpaceFilter({
    super.key,
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = SpaceStyle.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: spaceMotion(context, 160),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: selected
              ? style.accentSoft
              : Theme.of(context).colorScheme.surfaceContainer,
          border: Border.all(
            color: selected ? style.accent : style.border,
            width: 1.5,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      ExcludeSemantics(
                        child: Icon(
                          icon,
                          size: 18,
                          color: selected ? style.accentInk : style.muted,
                        ),
                      ),
                      const SizedBox(width: 7),
                    ],
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelLarge!.copyWith(
                        color: selected ? style.accentInk : style.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SpaceBadge extends StatelessWidget {
  final String label;
  final Color? color;
  const SpaceBadge(this.label, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final style = SpaceStyle.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color ?? style.accentSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium!
            .copyWith(color: style.accentInk, letterSpacing: .5),
      ),
    );
  }
}

class SpaceSection extends StatelessWidget {
  final String title;
  final String? detail;
  const SpaceSection(this.title, {super.key, this.detail});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (detail != null) ...[
          const SizedBox(width: 12),
          Text(detail!, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    ),
  );
}

class SpaceEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  const SpaceEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final style = SpaceStyle.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 48),
      child: Column(
        children: [
          HouseStateArt(icon: icon),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge!
                .copyWith(color: style.muted),
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}

class SpacePageHeading extends StatelessWidget {
  final SpacePage page;
  final String subtitle;
  const SpacePageHeading(this.page, {super.key, required this.subtitle});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 24),
    child: Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: SpaceStyle.of(context).accentSoft,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Center(child: SpaceSymbol(page, size: 30)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                page.label,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 3),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    ),
  );
}

double spaceBottomPadding(BuildContext context) =>
    110 + MediaQuery.paddingOf(context).bottom;

Future<T?> showSpaceSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            22,
            0,
            22,
            26 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: child,
        ),
      ),
    );
