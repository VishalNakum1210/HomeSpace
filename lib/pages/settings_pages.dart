import 'package:flutter/material.dart';

import '../design/vector_artwork.dart';

import 'package:flutter/services.dart';

import '../application/home_scope.dart';
import '../design/cartoon_artwork.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../domain/models.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});
  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final form = GlobalKey<FormState>();
  TextEditingController? name;
  AvatarTone? tone;
  bool busy = false;
  @override
  void dispose() {
    name?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: spaceTheme(Theme.of(context).brightness, SpacePage.profile),
    child: Builder(
      builder: (context) {
        final repository = HomeScope.of(context);
        final profile = repository.profile;
        name ??= TextEditingController(text: profile.name);
        tone ??= profile.avatarTone;
        final style = SpaceStyle.of(context);
        final text = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(title: const Text('Edit profile'), centerTitle: true),
          body: Form(
            key: form,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: SizedBox(
                      width: 112,
                      height: 112,
                      child: Stack(
                        children: [
                          ProfileAvatar(
                            profile: profile.copyWith(avatarTone: tone),
                            size: 112,
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: IconButton.filled(
                              key: const ValueKey('profile-picture'),
                              tooltip: 'Choose avatar',
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFF1677E8),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: busy
                                  ? null
                                  : () => showSpaceSheet<void>(
                                      context,
                                      StatefulBuilder(
                                        builder: (sheetContext, updateSheet) => Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Choose avatar',
                                              style: text.titleLarge,
                                            ),
                                            const SizedBox(height: 18),
                                            Wrap(
                                              spacing: 12,
                                              runSpacing: 12,
                                              children: [
                                                for (final option
                                                    in AvatarTone.values)
                                                  Semantics(
                                                    button: true,
                                                    selected: tone == option,
                                                    label:
                                                        '${option.name} avatar',
                                                    child: InkWell(
                                                      key: ValueKey(
                                                        'avatar-${option.name}',
                                                      ),
                                                      customBorder:
                                                          const CircleBorder(),
                                                      onTap: busy
                                                          ? null
                                                          : () {
                                                              setState(
                                                                () => tone =
                                                                    option,
                                                              );
                                                              updateSheet(
                                                                () {},
                                                              );
                                                            },
                                                      child: ExcludeSemantics(
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets.all(
                                                                4,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            shape:
                                                                BoxShape.circle,
                                                            border: Border.all(
                                                              color:
                                                                  tone == option
                                                                  ? style
                                                                        .accentInk
                                                                  : Colors
                                                                        .transparent,
                                                              width: 2,
                                                            ),
                                                          ),
                                                          child: ProfileAvatar(
                                                            profile: profile
                                                                .copyWith(
                                                                  avatarTone:
                                                                      option,
                                                                ),
                                                            size: 44,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 16),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(sheetContext),
                                              child: const Text('Done'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                              icon: const Icon(
                                Icons.photo_camera_rounded,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text('Name', style: text.labelLarge),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const ValueKey('profile-name'),
                    controller: name,
                    enabled: !busy,
                    maxLength: 60,
                    buildCounter: (
                      context, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => null,
                    decoration: const InputDecoration(hintText: 'Your name'),
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter your name.'
                        : null,
                  ),
                  const SizedBox(height: 28),
                  SpaceButton(
                    key: const ValueKey('save-profile'),
                    label: busy ? 'Saving…' : 'Save changes',
                    onPressed: busy || repository.pendingWrites > 0
                        ? null
                        : () async {
                            if (!form.currentState!.validate()) return;
                            FocusScope.of(context).unfocus();
                            setState(() => busy = true);
                            final saved = await saveLocalChange(
                              context,
                              () => repository.updateProfile(name!.text, tone!),
                            );
                            if (!mounted) return;
                            setState(() => busy = false);
                            if (saved && context.mounted) {
                              popSpaceRouteIfCurrent(context);
                            }
                          },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class AppearancePage extends StatefulWidget {
  const AppearancePage({super.key});
  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  Appearance? draft;
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final repository = HomeScope.of(context);
    draft ??= repository.profile.appearance;
    final brightness = switch (draft!) {
      Appearance.light => Brightness.light,
      Appearance.dark => Brightness.dark,
      Appearance.system => MediaQuery.platformBrightnessOf(context),
    };
    return Theme(
      data: spaceTheme(brightness, SpacePage.profile),
      child: Builder(
        builder: (context) {
          final text = Theme.of(context).textTheme;
          final style = SpaceStyle.of(context);
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value:
                (brightness == Brightness.dark
                        ? SystemUiOverlayStyle.light
                        : SystemUiOverlayStyle.dark)
                    .copyWith(
                      statusBarColor: Colors.transparent,
                      systemNavigationBarColor: Theme.of(context)
                          .scaffoldBackgroundColor,
                      systemNavigationBarIconBrightness:
                          brightness == Brightness.dark
                          ? Brightness.light
                          : Brightness.dark,
                      systemNavigationBarContrastEnforced: false,
                    ),
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Appearance'),
                centerTitle: true,
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Choose how HomeSpace looks.', style: text.bodyLarge),
                    const SizedBox(height: 20),
                    for (final option in [
                      Appearance.light,
                      Appearance.dark,
                      Appearance.system,
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Semantics(
                          checked: draft == option,
                          inMutuallyExclusiveGroup: true,
                          button: true,
                          child: Material(
                            color: draft == option
                                ? const Color(0xFF1677E8).withValues(alpha: .08)
                                : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainer,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                              side: BorderSide(
                                color: draft == option
                                    ? const Color(0xFF1677E8)
                                    : style.border,
                                width: draft == option ? 2 : 1,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              key: ValueKey('theme-${option.name}'),
                              onTap: busy
                                  ? null
                                  : () => setState(() => draft = option),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Icon(
                                      draft == option
                                          ? Icons.radio_button_checked_rounded
                                          : Icons.radio_button_off_rounded,
                                      color: draft == option
                                          ? const Color(0xFF1677E8)
                                          : style.muted,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(switch (option) {
                                            Appearance.light => 'Light',
                                            Appearance.dark => 'Dark',
                                            Appearance.system => 'System',
                                          }, style: text.titleMedium),
                                          const SizedBox(height: 4),
                                          Text(switch (option) {
                                            Appearance.light =>
                                              'A clean and bright look.',
                                            Appearance.dark =>
                                              'A softer look for low light.',
                                            Appearance.system =>
                                              'Match your device settings.',
                                          }, style: text.bodyMedium),
                                        ],
                                      ),
                                    ),
                                    if (MediaQuery.textScalerOf(context)
                                            .scale(14) <=
                                        20) ...[
                                      const SizedBox(width: 12),
                                      ExcludeSemantics(
                                        child: SpaceArtwork(
                                          'theme-${option.name}',
                                          width: 64,
                                          height: 46,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const SizedBox(
                          width: 110,
                          height: 94,
                          child: HouseGreeting(),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: SpaceButton(
                            key: const ValueKey('save-appearance'),
                            label: busy ? 'Saving…' : 'Done',
                            onPressed: busy || repository.pendingWrites > 0
                                ? null
                                : () async {
                                    if (draft ==
                                        repository.profile.appearance) {
                                      Navigator.pop(context);
                                      return;
                                    }
                                    setState(() => busy = true);
                                    final saved = await saveLocalChange(
                                      context,
                                      () => repository.setAppearance(draft!),
                                    );
                                    if (!mounted) return;
                                    setState(() => busy = false);
                                    if (saved && context.mounted) {
                                      popSpaceRouteIfCurrent(context);
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
