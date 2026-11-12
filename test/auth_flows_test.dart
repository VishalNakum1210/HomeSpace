import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/app.dart';
import 'package:homespace/application/frontend_session.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';

Finder key(String value) => find.byKey(ValueKey(value));

Future<FrontendSession> start(
  WidgetTester tester, {
  Size size = const Size(412, 892),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repository = LocalHomeRepository(store: MemorySnapshotStore());
  final session = FrontendSession();
  addTearDown(repository.dispose);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('auth-frame'),
      child: HomeSpaceApp(repository: repository, session: session),
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('HOMESPACE_CAPTURE')) return;
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/illustrations/auth-layout-approved.png'),
      tester.element(find.byType(Scaffold).first),
    ),
  );
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    key('auth-frame'),
  );
  void repaint(RenderObject object) {
    object.markNeedsPaint();
    object.visitChildren(repaint);
  }

  repaint(boundary);
  await tester.pump();
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('output/previews/auth-$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Nunito',
    )..addFont(rootBundle.load('assets/fonts/Nunito-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'Approved layouts, validation, visibility, registration Back and credential clearing',
    (tester) async {
      final session = await start(tester);
      await capture(tester, 'login');
      expect(key('space-navigation'), findsNothing);
      await tester.tap(key('auth-submit'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(session.isOpen, isFalse);
      await tester.tap(key('auth-switch'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('HomeSpace')).dy, greaterThan(0));
      await capture(tester, 'registration');
      await tester.enterText(key('auth-Full name'), 'Maya');
      await tester.enterText(key('auth-Email'), 'maya@example.com');
      await tester.enterText(key('auth-Password'), 'password1');
      await tester.enterText(key('auth-Confirm password'), 'different');
      await tester.ensureVisible(key('auth-submit'));
      await tester.tap(key('auth-submit'));
      await tester.pumpAndSettle();
      expect(find.text('Passwords don’t match'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Show Password'));
      await tester.tap(find.byTooltip('Show Password'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(key('auth-Password')).controller!.text,
        'password1',
      );
      final editable = find.descendant(
        of: key('auth-Password'),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(editable).obscureText, isFalse);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Welcome home'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(key('auth-Password')).controller!.text,
        isEmpty,
      );
      expect(session.isOpen, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Login preview and logout return to fresh login preserving library',
    (tester) async {
      final session = await start(tester);
      await tester.enterText(key('auth-Email'), 'maya@example.com');
      await tester.enterText(key('auth-Password'), 'password1');
      await tester.tap(key('auth-submit'));
      await tester.pumpAndSettle();
      expect(find.text('Explore HomeSpace'), findsOneWidget);
      await tester.tap(find.text('Continue to preview'));
      await tester.pumpAndSettle();
      expect(session.isOpen, isTrue);
      expect(find.text('Your happy place'), findsOneWidget);
      await tester.tap(key('tab-profile'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(key('logout'));
      await tester.tap(key('logout'));
      await tester.pumpAndSettle();
      expect(session.isOpen, isFalse);
      expect(find.text('Welcome home'), findsOneWidget);
      expect(key('space-navigation'), findsNothing);
      expect(
        tester.widget<TextFormField>(key('auth-Email')).controller!.text,
        isEmpty,
      );
      session.enterPreview();
      await tester.pumpAndSettle();
      expect(find.text('Your happy place'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Small screen, large text and keyboard keep registration scrollable',
    (tester) async {
      await start(tester, size: const Size(320, 568));
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.ensureVisible(key('auth-switch'));
      await tester.tap(key('auth-switch'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.ensureVisible(key('auth-Confirm password'));
      await tester.enterText(key('auth-Confirm password'), 'sample');
      await tester.ensureVisible(key('auth-submit'));
      expect(key('auth-submit').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
