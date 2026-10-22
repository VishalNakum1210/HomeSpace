import 'package:flutter/material.dart';

import 'space_symbols.dart';
import 'space_theme.dart';

class SpaceNavigation extends StatelessWidget {
  final SpacePage selected;
  final ValueChanged<SpacePage> onSelected;
  const SpaceNavigation({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      key: const ValueKey('space-navigation'),
      width: 216,
      height: 64,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: SpaceStyle.of(context).border, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? .25 : .10),
              blurRadius: 22,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slot = constraints.maxWidth / 3;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: spaceMotion(context),
                    curve: Curves.easeOutCubic,
                    left: slot * selected.index + (slot - 48) / 2,
                    top: 0,
                    width: 48,
                    height: 48,
                    child: DecoratedBox(
                      key: const ValueKey('active-tab-circle'),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: SpaceStyle.of(context).navigationBlue,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (final page in SpacePage.values)
                        Expanded(
                          child: Semantics(
                            label: page.label,
                            selected: page == selected,
                            button: true,
                            child: Tooltip(
                              message: page.label,
                              excludeFromSemantics: true,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  key: ValueKey('tab-${page.name}'),
                                  customBorder: const CircleBorder(),
                                  onTap: () => onSelected(page),
                                  child: SizedBox(
                                    height: 48,
                                    child: Center(
                                      child: AnimatedScale(
                                        scale: page == selected ? 1.06 : 1,
                                        duration: spaceMotion(context, 180),
                                        curve: Curves.easeOutCubic,
                                        child: SpaceSymbol(page, size: 29),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
