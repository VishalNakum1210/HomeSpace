import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/home_scope.dart';
import '../design/space_theme.dart';
import '../domain/models.dart';

Future<T?> openSpacePage<T>(
  BuildContext context,
  Widget page,
) => Navigator.of(context).push<T>(
  PageRouteBuilder<T>(
    pageBuilder: (_, _, _) => Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final dark = theme.brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: theme.scaffoldBackgroundColor,
                systemNavigationBarIconBrightness: dark
                    ? Brightness.light
                    : Brightness.dark,
                systemNavigationBarContrastEnforced: false,
              ),
          child: page,
        );
      },
    ),
    transitionDuration: spaceMotion(context, 240),
    reverseTransitionDuration: spaceMotion(context, 200),
    transitionsBuilder: (_, animation, _, child) {
      final eased = animation.drive(CurveTween(curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: eased,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, .035),
            end: Offset.zero,
          ).animate(eased),
          child: child,
        ),
      );
    },
  ),
);

int libraryColumns(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < 340 || MediaQuery.textScalerOf(context).scale(16) > 25) return 2;
  return width > 650 ? 5 : 3;
}

class MediaThumbnail extends StatelessWidget {
  final MediaItem media;
  const MediaThumbnail({super.key, required this.media});
  @override
  Widget build(BuildContext context) => media.kind == MediaKind.photo
      ? Image.asset(
          media.asset,
          fit: BoxFit.cover,
          cacheWidth: 600,
          errorBuilder: (_, _, _) =>
              const Center(child: Icon(Icons.broken_image_outlined)),
        )
      : const Center(child: Icon(Icons.movie_outlined, size: 40));
}

class MemoryTile extends StatelessWidget {
  final MediaItem media;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool? selected;
  final bool favorite;
  final String? subtitle;
  const MemoryTile({
    super.key,
    required this.media,
    required this.onTap,
    this.onLongPress,
    this.selected,
    this.favorite = false,
    this.subtitle,
  });
  @override
  Widget build(BuildContext context) {
    final style = SpaceStyle.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${media.title}${favorite ? ', favorite' : ''}${subtitle == null ? '' : ', $subtitle'}',
      child: Material(
        color: style.accentSoft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected == true ? style.accentInk : Colors.transparent,
            width: 3,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: ExcludeSemantics(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MediaThumbnail(media: media),
                if (selected != null || favorite)
                  Positioned(
                    right: 7,
                    top: 7,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: selected == true
                            ? style.accentInk
                            : const Color(0xAA101519),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Icon(
                          selected == null
                              ? Icons.favorite_rounded
                              : selected!
                              ? Icons.check_rounded
                              : Icons.circle_outlined,
                          color: Colors.white,
                          size: 19,
                        ),
                      ),
                    ),
                  ),
                if (subtitle != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ColoredBox(
                      color: const Color(0xCC101519),
                      child: Padding(
                        padding: const EdgeInsets.all(7),
                        child: Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SelectionActions extends StatelessWidget implements PreferredSizeWidget {
  final List<Widget> children;
  const SelectionActions({super.key, required this.children});
  @override
  Size get preferredSize => const Size.fromHeight(68);
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 68,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          for (final child in children)
            Padding(padding: const EdgeInsets.only(right: 8), child: child),
        ],
      ),
    ),
  );
}

Future<bool> confirmLibraryAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('confirm-action'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirm),
          ),
        ],
      ),
    ) ??
    false;

Future<bool> trashMemories(BuildContext context, List<String> ids) async {
  final repository = HomeScope.of(context);
  final actionContext = Navigator.of(context).context;
  final confirmed = await confirmLibraryAction(
    context,
    title:
        'Move ${ids.length == 1 ? 'memory' : '${ids.length} memories'} to Trash?',
    message: 'They will disappear from your library and albums. You can restore them from Trash in Profile.',
    confirm: 'Move to Trash',
  );
  if (!confirmed || !context.mounted) return false;
  final saved = await saveLocalChange(
    context,
    () => repository.moveManyToTrash(ids),
  );
  if (saved && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        margin: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          96 + MediaQuery.paddingOf(context).bottom,
        ),
        content: Text(
          '${ids.length} ${ids.length == 1 ? 'memory' : 'memories'} moved to Trash',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (actionContext.mounted) {
              saveLocalChange(actionContext, () => repository.restoreMany(ids));
            }
          },
        ),
      ),
    );
  }
  return saved;
}

Future<bool> deleteTrashedMemories(
  BuildContext context,
  List<String> ids,
) async {
  final repository = HomeScope.of(context);
  final confirmed = await confirmLibraryAction(
    context,
    title:
        'Delete ${ids.length == 1 ? 'memory' : '${ids.length} memories'} forever?',
    message: 'This removes them from this local library, including album entries and favorites. This can’t be undone.',
    confirm: 'Delete forever',
  );
  if (!confirmed || !context.mounted) return false;
  return saveLocalChange(context, () => repository.deleteManyPermanently(ids));
}
