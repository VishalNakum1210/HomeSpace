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
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? [const Color(0xFF303C4D), const Color(0xFF202938)]
                : [Colors.white, const Color(0xFFF5F2F0)],
          ),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(
            color: Colors.white.withValues(alpha: dark ? .12 : .9),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF263348).withValues(alpha: dark ? .3 : .13),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: dark ? .04 : .8),
              blurRadius: 8,
              offset: const Offset(-2, -3),
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
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF9EDFFF), Color(0xFF3898FF)],
                        ),
                        border: Border.all(color: const Color(0xFFB5E6FF)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2589ED)
                                .withValues(alpha: .22),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
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
                                        child: ClayNavigationSymbol(page),
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
