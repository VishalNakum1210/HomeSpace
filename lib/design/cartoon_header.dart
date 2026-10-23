import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../application/home_scope.dart';
import 'space_symbols.dart';

class CartoonHeader extends StatelessWidget {
  final ProfileSettings profile;
  final VoidCallback? onProfile;
  final Widget? action;
  const CartoonHeader({
    super.key,
    required this.profile,
    this.onProfile,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 12),
    child: Row(
      children: [
        const SpaceHouse(size: 32),
        const SizedBox(width: 7),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'HomeSpace',
              maxLines: 1,
              style: Theme.of(context).textTheme.titleLarge!.copyWith(
                fontSize: 21,
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFFB8F393)
                    : const Color(0xFF347000),
              ),
            ),
          ),
        ),
        ?action,
        if (onProfile != null)
          IconButton(
            tooltip: 'Open profile',
            onPressed: onProfile,
            icon: ProfileAvatar(profile: profile, size: 34),
          ),
      ],
    ),
  );
}
