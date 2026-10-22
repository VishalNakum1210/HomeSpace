import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';
import '../design/space_symbols.dart';
import '../design/space_widgets.dart';

class HomeScope extends InheritedNotifier<HomeRepository> {
  const HomeScope({
    super.key,
    required HomeRepository repository,
    required super.child,
  }) : super(notifier: repository);
  static HomeRepository of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomeScope>()!.notifier!;
}

Future<bool> saveLocalChange(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } catch (error) {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Couldn’t save that change'),
          content: Text(
            error is LocalActionException
                ? error.message
                : 'Couldn’t save this change on your device. Please try again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
    return false;
  }
}

class ProfileAvatar extends StatelessWidget {
  final ProfileSettings profile;
  final double size;
  const ProfileAvatar({super.key, required this.profile, this.size = 40});
  @override
  Widget build(BuildContext context) {
    final color = switch (profile.avatarTone) {
      AvatarTone.orange => const Color(0xFF965000),
      AvatarTone.green => const Color(0xFF347000),
      AvatarTone.purple => const Color(0xFF7035B4),
      AvatarTone.blue => const Color(0xFF13618A),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.alphaBlend(
          color.withValues(alpha: .1),
          Theme.of(context).colorScheme.surfaceContainer,
        ),
        border: Border.all(
          color: color.withValues(alpha: .65),
          width: size > 50 ? 3 : 2,
        ),
      ),
      child: Center(
        child: Text(
          profile.initial,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w900,
            fontSize: size * .42,
            color: Theme.of(context).brightness == Brightness.dark
                ? Color.lerp(color, Colors.white, .6)
                : color,
          ),
        ),
      ),
    );
  }
}

class RepositoryBootPage extends StatelessWidget {
  final HomeRepository repository;
  const RepositoryBootPage({super.key, required this.repository});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SpaceHouse(size: 72),
                const SizedBox(height: 24),
                Text(
                  repository.bootError == null
                      ? 'Making yourself at home…'
                      : 'Let’s try that again',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                if (repository.bootError == null)
                  const CircularProgressIndicator(
                    semanticsLabel: 'Opening your saved library',
                  )
                else ...[
                  Text(
                    repository.bootError!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  SpaceButton(
                    label: 'Retry opening library',
                    icon: Icons.refresh_rounded,
                    onPressed: () => repository.initialize(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ScenarioContent extends StatelessWidget {
  final HomeRepository repository;
  final Widget child;
  const ScenarioContent({
    super.key,
    required this.repository,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => switch (repository.scenario) {
    DemoScenario.loading => const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(semanticsLabel: 'Loading demo library'),
            SizedBox(height: 20),
            Text('Loading demo memories…', textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
    DemoScenario.failed => Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SpaceEmpty(
              icon: Icons.wifi_off_rounded,
              title: 'Couldn’t load this preview',
              message: 'This is a simulated error. Your saved local library is safe.',
            ),
            SpaceButton(
              label: 'Try again',
              icon: Icons.refresh_rounded,
              onPressed: () => repository.setScenario(DemoScenario.populated),
            ),
          ],
        ),
      ),
    ),
    _ => child,
  };
}

String libraryStatus(HomeRepository repository) {
  if (repository.recoveryNotice != null) return repository.recoveryNotice!;
  return switch (repository.scenario) {
    DemoScenario.offline => 'Offline demo · Showing saved local memories',
    DemoScenario.success => 'Demo library ready · Saved on this device',
    DemoScenario.empty => 'Empty preview · Your saved library is kept',
    _ => 'Sample library · Saved on this device',
  };
}
