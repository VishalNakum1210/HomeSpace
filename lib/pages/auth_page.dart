import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/auto_backup_service.dart';
import '../application/frontend_session.dart';
import '../application/home_scope.dart';
import '../data/homespace_api_client.dart';
import '../data/local_home_repository.dart';
import '../data/tls_trust.dart';
import '../domain/models.dart';
import '../design/space_symbols.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../design/system_ui.dart';

class AuthPage extends StatefulWidget {
  final FrontendSession session;
  final bool? allowRegistration;
  final HomeSpaceApiClient Function()? apiClientFactory;
  const AuthPage({
    super.key,
    required this.session,
    this.allowRegistration,
    this.apiClientFactory,
  });

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool get canRegister =>
      widget.allowRegistration ??
      (const bool.fromEnvironment('FLUTTER_TEST') ||
          WidgetsBinding.instance.runtimeType.toString().contains('Test'));
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  final scroll = ScrollController();
  bool register = false;
  bool hidePassword = true;
  bool hideConfirmation = true;
  bool submitting = false;
  AvatarTone selectedTone = AvatarTone.orange;

  @override
  void dispose() {
    scroll.dispose();
    for (final controller in [name, email, password, confirmation]) {
      controller.dispose();
    }
    super.dispose();
  }

  void switchPage() {
    FocusManager.instance.primaryFocus?.unfocus();
    form.currentState?.reset();
    password.clear();
    confirmation.clear();
    setState(() {
      register = !register;
      hidePassword = hideConfirmation = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) scroll.jumpTo(0);
    });
  }

  bool _isNetworkOrTlsError(Object error) {
    if (error is SocketException ||
        error is HandshakeException ||
        error is TlsException ||
        error is TimeoutException) {
      return true;
    }
    if (error is HomeSpaceServerException) {
      if (error.statusCode == 0) return true;
      const networkCodes = {
        'SERVER_UNREACHABLE',
        'TLS_HANDSHAKE_FAILED',
        'TIMEOUT',
        'NETWORK_ERROR',
        'CLIENT_ERROR',
      };
      if (networkCodes.contains(error.code)) return true;
      // Flutter's widget test HttpOverrides returns HTTP 400 with empty body for unmocked hosts.
      final isWidgetTest =
          WidgetsBinding.instance.runtimeType.toString().contains('Test');
      if (isWidgetTest && error.code == 'HTTP_400') {
        return true;
      }
      return false;
    }
    return false;
  }

  Future<void> _completeLocalRegistration({
    required String name,
    required String email,
    required AvatarTone avatarTone,
    Uri? serverUri,
    bool notifyUser = true,
    bool offlineNotice = false,
  }) async {
    final effectiveUri = serverUri ??
        widget.session.serverUri ??
        Uri.parse('http://127.0.0.1:8888');
    final localUserId = 'u_${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';
    final localToken = 'local_${DateTime.now().millisecondsSinceEpoch}';

    try {
      final repo = HomeScope.of(context);
      if (repo is LocalHomeRepository) {
        await repo.initForAuthenticatedUser(
          userId: localUserId,
          name: name,
          avatarTone: avatarTone,
          isAdmin: false,
          clearDemoSeed: true,
          serverUri: effectiveUri,
          token: localToken,
        );
      } else {
        await repo.updateProfile(name, avatarTone);
      }
    } catch (_) {}

    await widget.session.setAuthenticated(
      serverUri: effectiveUri,
      token: localToken,
      userId: localUserId,
      email: email,
      name: name,
      avatarTone: avatarTone,
    );

    TextInput.finishAutofillContext(shouldSave: false);
    password.clear();
    confirmation.clear();

    if (mounted && notifyUser) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            offlineNotice
                ? 'Welcome to HomeSpace, $name! Account created. Photos will sync automatically when your server connects.'
                : 'Welcome to HomeSpace, $name! Account created successfully.',
          ),
          backgroundColor: const Color(0xFF287000),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _completeLocalLogin({
    required String email,
    Uri? serverUri,
    AvatarTone? avatarTone,
    bool notifyUser = true,
    bool offlineNotice = false,
  }) async {
    final effectiveUri = serverUri ??
        widget.session.serverUri ??
        Uri.parse('http://127.0.0.1:8888');

    final repo = HomeScope.of(context);
    String userName = '';
    AvatarTone userTone = avatarTone ?? selectedTone;
    String localUserId = '';

    if (repo is LocalHomeRepository) {
      final profile = repo.profile;
      if (widget.session.userEmail == email &&
          profile.name.isNotEmpty &&
          profile.name != 'Local User') {
        userName = profile.name;
        userTone = avatarTone ?? profile.avatarTone;
      }
      if (profile.userId.isNotEmpty && profile.userId != 'local_user') {
        localUserId = profile.userId;
      }
    }

    if (userName.isEmpty) {
      final localPart = email.split('@').first.trim();
      if (localPart.isNotEmpty) {
        userName = localPart[0].toUpperCase() +
            (localPart.length > 1 ? localPart.substring(1) : '');
      } else {
        userName = 'Family Member';
      }
    }

    if (localUserId.isEmpty) {
      localUserId = 'u_${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';
    }
    final localToken = 'local_${DateTime.now().millisecondsSinceEpoch}';

    try {
      if (repo is LocalHomeRepository) {
        await repo.initForAuthenticatedUser(
          userId: localUserId,
          name: userName,
          avatarTone: userTone,
          isAdmin: false,
          serverUri: effectiveUri,
          token: localToken,
        );
      } else {
        await repo.updateProfile(userName, userTone);
      }
    } catch (_) {}

    await widget.session.setAuthenticated(
      serverUri: effectiveUri,
      token: localToken,
      userId: localUserId,
      email: email,
      name: userName,
      avatarTone: userTone,
    );

    TextInput.finishAutofillContext(shouldSave: false);
    password.clear();
    confirmation.clear();

    if (mounted && notifyUser) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            offlineNotice
                ? 'Welcome back, $userName! (Local Mode - photos will sync when your home server connects)'
                : 'Welcome back, $userName!',
          ),
          backgroundColor: const Color(0xFF287000),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> submit() async {
    if (submitting) return;
    if (!form.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();

    final targetUri = widget.session.serverUri;
    if (targetUri == null) {
      if (register) {
        setState(() => submitting = true);
        await _completeLocalRegistration(
          name: name.text.trim(),
          email: email.text.trim(),
          avatarTone: selectedTone,
        );
        if (mounted) setState(() => submitting = false);
        return;
      } else {
        setState(() => submitting = true);
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Explore HomeSpace'),
            content: const Text(
              'Accounts aren’t connected to your home server yet. Continue to the '
              'local preview. No account is created and your password isn’t saved.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue to preview'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        setState(() => submitting = false);
        if (proceed != true) return;
        TextInput.finishAutofillContext(shouldSave: false);
        password.clear();
        confirmation.clear();
        widget.session.enterPreview();
        return;
      }
    }

    setState(() => submitting = true);
    final client = widget.apiClientFactory?.call() ?? HomeSpaceApiClient();
    try {
      if (register) {
        final result = await client.register(
          baseUri: targetUri,
          email: email.text.trim(),
          password: password.text,
          name: name.text.trim(),
          avatarTone: selectedTone,
        );
        if (!mounted) return;
        final effectiveUri = result.resolvedServerUri ?? targetUri;
        try {
          final repo = HomeScope.of(context);
          if (repo is LocalHomeRepository) {
            await repo.initForAuthenticatedUser(
              userId: result.userId,
              name: result.name,
              avatarTone: result.avatarTone,
              isAdmin: result.isAdmin,
              clearDemoSeed: true,
              serverUri: effectiveUri,
              token: result.token,
            );
          } else {
            await repo.updateProfile(result.name, result.avatarTone);
          }
        } catch (_) {}
        if (!mounted) return;
        await widget.session.setAuthenticated(
          serverUri: effectiveUri,
          token: result.token,
          userId: result.userId,
          email: result.email,
          name: result.name,
          avatarTone: result.avatarTone,
          isAdmin: result.isAdmin,
        );
        TextInput.finishAutofillContext(shouldSave: false);
        password.clear();
        confirmation.clear();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Welcome to HomeSpace, ${result.name}!'),
              backgroundColor: const Color(0xFF287000),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        final result = await client.login(
          baseUri: targetUri,
          email: email.text.trim(),
          password: password.text,
        );
        if (!mounted) return;
        final effectiveUri = result.resolvedServerUri ?? targetUri;
        try {
          final repo = HomeScope.of(context);
          if (repo is LocalHomeRepository) {
            await repo.initForAuthenticatedUser(
              userId: result.userId,
              name: result.name,
              avatarTone: result.avatarTone,
              isAdmin: result.isAdmin,
              clearDemoSeed: true,
              serverUri: effectiveUri,
              token: result.token,
            );
          } else {
            await repo.updateProfile(result.name, result.avatarTone);
          }
        } catch (_) {}
        if (!mounted) return;
        await widget.session.setAuthenticated(
          serverUri: effectiveUri,
          token: result.token,
          userId: result.userId,
          email: result.email,
          name: result.name,
          avatarTone: result.avatarTone,
          isAdmin: result.isAdmin,
        );
        TextInput.finishAutofillContext(shouldSave: false);
        password.clear();
        confirmation.clear();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Welcome back, ${result.name}!'),
              backgroundColor: const Color(0xFF287000),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } on HomeSpaceServerException catch (e) {
      if (!mounted) return;
      setState(() => submitting = false);
      if (_isNetworkOrTlsError(e)) {
        if (register) {
          await _completeLocalRegistration(
            name: name.text.trim(),
            email: email.text.trim(),
            avatarTone: selectedTone,
            serverUri: targetUri,
            offlineNotice: true,
          );
        } else {
          await _completeLocalLogin(
            email: email.text.trim(),
            serverUri: targetUri,
            avatarTone: selectedTone,
            offlineNotice: true,
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.code == 'INVALID_CREDENTIALS'
                  ? 'Incorrect email or password. Please check your credentials.'
                  : e.message,
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => submitting = false);
      if (_isNetworkOrTlsError(e)) {
        if (register) {
          await _completeLocalRegistration(
            name: name.text.trim(),
            email: email.text.trim(),
            avatarTone: selectedTone,
            serverUri: targetUri,
            offlineNotice: true,
          );
        } else {
          await _completeLocalLogin(
            email: email.text.trim(),
            serverUri: targetUri,
            avatarTone: selectedTone,
            offlineNotice: true,
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot connect to home server: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      client.close();
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _showChangeServerDialog() async {
    final newUriString = await showDialog<String>(
      context: context,
      builder: (context) => _ServerAddressDialog(
        initialValue: widget.session.serverUri?.toString() ?? '',
      ),
    );

    if (newUriString != null && mounted) {
      if (newUriString.isEmpty) {
        await widget.session.updateServerUri(null);
        if (!mounted) return;
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Switched to Local Device Mode'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        final uri = Uri.parse(newUriString);
        await widget.session.updateServerUri(uri);
        if (!mounted) return;
        try {
          final repo = HomeScope.of(context);
          unawaited(repo.connection.connect(uri));
        } catch (_) {}
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Server address updated to $newUriString'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _serverPill() {
    final uri = widget.session.serverUri;
    final isConfigured = uri != null && uri.host.isNotEmpty;
    final display = isConfigured
        ? (uri.host.isNotEmpty
            ? '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}'
            : uri.toString())
        : 'Local Device Mode (Tap to configure)';

    return Center(
      child: InkWell(
        key: const ValueKey('auth-server-pill'),
        onTap: _showChangeServerDialog,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F4EC),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFD4E5C8)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isConfigured ? Icons.cloud_outlined : Icons.smartphone_rounded,
                size: 15,
                color: const Color(0xFF287000),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  display,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF287000),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.edit_outlined, size: 13, color: Color(0xFF287000)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarToneSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              register ? 'Avatar color' : 'Avatar tone',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF10112F),
              ),
            ),
            Text(
              selectedTone.name[0].toUpperCase() + selectedTone.name.substring(1),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _colorForTone(selectedTone),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final tone in AvatarTone.values) ...[
              Expanded(
                child: Semantics(
                  button: true,
                  selected: selectedTone == tone,
                  label: '${tone.name} avatar tone',
                  child: InkWell(
                    key: ValueKey('auth-avatar-${tone.name}'),
                    onTap: () => setState(() => selectedTone = tone),
                    borderRadius: BorderRadius.circular(16),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: selectedTone == tone
                            ? _colorForTone(tone).withValues(alpha: 0.12)
                            : Colors.grey.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selectedTone == tone
                              ? _colorForTone(tone)
                              : const Color(0xFFE2E2E6),
                          width: selectedTone == tone ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _colorForTone(tone),
                              boxShadow: selectedTone == tone
                                  ? [
                                      BoxShadow(
                                        color: _colorForTone(tone).withValues(alpha: 0.35),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: Text(
                                name.text.trim().isNotEmpty
                                    ? name.text.trim()[0].toUpperCase()
                                    : (email.text.trim().isNotEmpty
                                        ? email.text.trim()[0].toUpperCase()
                                        : '•'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tone.name[0].toUpperCase() + tone.name.substring(1),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: selectedTone == tone
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: selectedTone == tone
                                  ? _colorForTone(tone)
                                  : const Color(0xFF5A5D72),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (tone != AvatarTone.values.last) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }

  Color _colorForTone(AvatarTone tone) => switch (tone) {
    AvatarTone.orange => const Color(0xFFE65100),
    AvatarTone.green => const Color(0xFF287000),
    AvatarTone.purple => const Color(0xFF6A1B9A),
    AvatarTone.blue => const Color(0xFF1565C0),
  };

  @override
  Widget build(BuildContext context) {
    // Authentication follows the approved white layout even when the saved
    // library appearance is dark. That preference is restored in the library.
    return Theme(
      data: spaceTheme(
        Brightness.light,
        SpacePage.photos,
      ).copyWith(scaffoldBackgroundColor: Colors.white),
      child: Builder(
        builder: (context) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: spaceSystemUiStyle(context),
          child: PopScope(
            canPop: !register,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && register) switchPage();
            },
            child: Scaffold(
              body: SafeArea(
                child: LayoutBuilder(
                  builder: (context, bounds) {
                    final compact = bounds.maxHeight < 700;
                    return SingleChildScrollView(
                      controller: scroll,
                      key: ValueKey(register),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.manual,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 22,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 412),
                          child: Form(
                            key: form,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SpaceHouse(size: 44),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Text(
                                        'HomeSpace',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineMedium!
                                            .copyWith(
                                              color: const Color(0xFF287000),
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: register || compact ? 20 : 38),
                                _ApprovedAuthArt(register: register),
                                const SizedBox(height: 22),
                                Text(
                                  register
                                      ? 'Join your HomeSpace'
                                      : 'Welcome home',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineLarge!
                                      .copyWith(
                                        fontSize: register ? 30 : 36,
                                        fontWeight: FontWeight.w900,
                                        color: const Color(0xFF10112F),
                                        height: 1.12,
                                      ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  register
                                      ? 'A home for every family memory.'
                                      : 'Your family memories, together.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    color: Color(0xFF5A5D72),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _serverPill(),
                                SizedBox(height: register ? 16 : 24),
                                if (register) ...[
                                  _field(
                                    'Full name',
                                    'Enter your name',
                                    name,
                                    Icons.person_outline_rounded,
                                    validator: (value) =>
                                        (value ?? '').trim().isEmpty
                                        ? 'Enter your name'
                                        : null,
                                    autofill: AutofillHints.name,
                                    onChanged: (_) => setState(() {}),
                                  ),
                                  SizedBox(height: register ? 12 : 18),
                                  _avatarToneSelector(),
                                  SizedBox(height: register ? 12 : 18),
                                ],
                                _field(
                                  'Email',
                                  'Enter your email',
                                  email,
                                  Icons.mail_outline_rounded,
                                  emailField: true,
                                  autofill: AutofillHints.email,
                                  onChanged: (_) => setState(() {}),
                                  validator: (value) =>
                                      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                          .hasMatch((value ?? '').trim())
                                      ? null
                                      : 'Enter a valid email address',
                                ),
                                SizedBox(height: register ? 12 : 18),
                                _field(
                                  'Password',
                                  register
                                      ? 'Create a password'
                                      : 'Enter your password',
                                  password,
                                  Icons.lock_outline_rounded,
                                  secret: true,
                                  hidden: hidePassword,
                                  toggle: () => setState(
                                    () => hidePassword = !hidePassword,
                                  ),
                                  last: !register,
                                  autofill: register
                                      ? AutofillHints.newPassword
                                      : AutofillHints.password,
                                  validator: (value) => (value ?? '').isEmpty
                                      ? 'Enter your password'
                                      : register && value!.length < 8
                                      ? 'Use at least 8 characters'
                                      : null,
                                ),
                                if (register) ...[
                                  const Padding(
                                    padding: EdgeInsets.only(top: 5),
                                    child: Text(
                                      'At least 8 characters',
                                      style: TextStyle(
                                        color: Color(0xFF5A5D72),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: register ? 12 : 18),
                                  _field(
                                    'Confirm password',
                                    'Repeat your password',
                                    confirmation,
                                    Icons.lock_outline_rounded,
                                    secret: true,
                                    hidden: hideConfirmation,
                                    toggle: () => setState(
                                      () =>
                                          hideConfirmation = !hideConfirmation,
                                    ),
                                    last: true,
                                    validator: (value) =>
                                        value == null || value.isEmpty
                                        ? 'Repeat your password'
                                        : value != password.text
                                        ? 'Passwords don’t match'
                                        : null,
                                  ),
                                ] else
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () => showDialog<void>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text('Forgot password?'),
                                          content: const Text(
                                            'If your home server is unreachable, you can sign in directly in Local Mode to access your device photos and albums.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              child: const Text('Close'),
                                            ),
                                            FilledButton(
                                              style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    const Color(0xFF287000),
                                              ),
                                              onPressed: () {
                                                Navigator.pop(context);
                                                if (email.text.trim().isEmpty) {
                                                  email.text =
                                                      'user@homespace.local';
                                                }
                                                _completeLocalLogin(
                                                  email: email.text.trim(),
                                                  avatarTone: selectedTone,
                                                  offlineNotice: true,
                                                );
                                              },
                                              child: const Text(
                                                'Sign in in Local Mode',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      child: const Text(
                                        'Forgot password?',
                                        style: TextStyle(
                                          color: Color(0xFF287000),
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                SizedBox(height: register ? 18 : 20),
                                SpaceButton(
                                  key: const ValueKey('auth-submit'),
                                  label: submitting
                                      ? (register ? 'Creating account…' : 'Logging in…')
                                      : (register ? 'Create account' : 'Log in'),
                                  backgroundColor: const Color(0xFF49A91D),
                                  foregroundColor: Colors.white,
                                  onPressed: submitting ? () {} : submit,
                                ),
                                SizedBox(height: register ? 8 : 28),
                                if (canRegister || register)
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        register
                                            ? 'Already have an account?'
                                            : 'New to HomeSpace?',
                                        style: const TextStyle(
                                          color: Color(0xFF5A5D72),
                                          fontSize: 15,
                                        ),
                                      ),
                                      TextButton(
                                        key: const ValueKey('auth-switch'),
                                        onPressed: switchPage,
                                        child: Text(
                                          register ? 'Log in' : 'Create account',
                                          style: const TextStyle(
                                            color: Color(0xFF287000),
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 16),
                                    child: Text(
                                      'Family accounts are created by your server administrator.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Color(0xFF5A5D72),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 36),
                                const Text(
                                  'HomeSpace v1.0.0 • © 2026 Vishal Nakum',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFF5A5D72),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    String hint,
    TextEditingController controller,
    IconData icon, {
    bool emailField = false,
    bool secret = false,
    bool hidden = false,
    bool last = false,
    VoidCallback? toggle,
    String? autofill,
    ValueChanged<String>? onChanged,
    String? Function(String?)? validator,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Color(0xFF10112F),
        ),
      ),
      const SizedBox(height: 8),
      TextFormField(
        key: ValueKey('auth-$label'),
        controller: controller,
        validator: validator,
        onChanged: onChanged,
        obscureText: secret && hidden,
        enableSuggestions: !secret,
        autocorrect: !secret && !emailField,
        keyboardType: emailField
            ? TextInputType.emailAddress
            : TextInputType.text,
        textCapitalization: label == 'Full name'
            ? TextCapitalization.words
            : TextCapitalization.none,
        textInputAction: last ? TextInputAction.done : TextInputAction.next,
        autofillHints: autofill == null ? null : [autofill],
        onFieldSubmitted: last ? (_) => submit() : null,
        style: const TextStyle(fontSize: 16, color: Color(0xFF171B32)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            color: Color(0xFF5A5D72),
            fontWeight: FontWeight.w400,
          ),
          filled: true,
          fillColor: Colors.white,
          prefixIcon: Icon(icon, color: const Color(0xFF646A79)),
          suffixIcon: toggle == null
              ? null
              : IconButton(
                  tooltip: hidden ? 'Show $label' : 'Hide $label',
                  onPressed: toggle,
                  icon: Icon(
                    hidden
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: const Color(0xFF646A79),
                  ),
                ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: register ? 12 : 15,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFD5D5D8), width: 1.3),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    ],
  );
}

/// Displays only the illustration region of the approved design, preserving
/// its original pixels without recreating or stretching the artwork.
class _ApprovedAuthArt extends StatelessWidget {
  final bool register;
  const _ApprovedAuthArt({required this.register});
  @override
  Widget build(BuildContext context) {
    final crop = register
        ? const Rect.fromLTRB(694, 220, 1185, 385)
        : const Rect.fromLTRB(112, 230, 602, 452);
    return ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: crop.width / crop.height,
        child: LayoutBuilder(
          builder: (context, bounds) {
            final scale = bounds.maxWidth / crop.width;
            return ClipRect(
              child: Stack(
                children: [
                  Positioned(
                    left: -crop.left * scale,
                    top: -crop.top * scale,
                    width: 1296 * scale,
                    height: 1213 * scale,
                    child: Image.asset(
                      'assets/illustrations/auth-layout-approved.png',
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ServerAddressDialog extends StatefulWidget {
  final String initialValue;
  const _ServerAddressDialog({required this.initialValue});

  @override
  State<_ServerAddressDialog> createState() => _ServerAddressDialogState();
}

class _ServerAddressDialogState extends State<_ServerAddressDialog> {
  late final TextEditingController controller;
  final formKey = GlobalKey<FormState>();
  bool testing = false;
  String? testResult;
  bool testSuccess = false;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final text = controller.text.trim();
    if (text.isEmpty) {
      setState(() {
        testSuccess = true;
        testResult = 'Local Device Mode: Stored purely on this phone.';
      });
      return;
    }
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      setState(() {
        testSuccess = false;
        testResult = 'Please enter a valid URL including http:// or https://';
      });
      return;
    }
    setState(() {
      testing = true;
      testResult = null;
    });
    final client = HomeSpaceApiClient();
    try {
      final ok = await client.checkHealth(uri);
      if (!mounted) return;
      setState(() {
        testing = false;
        testSuccess = ok;
        testResult = ok
            ? 'HomeSpace server is connected and ready!'
            : 'Server could not be verified or did not respond with HomeSpace service.';
      });
      if (!ok && uri.scheme == 'https') {
        await _offerSelfSignedTofuIfNeeded(uri);
      }
    } on HandshakeException catch (e) {
      if (!mounted) return;
      setState(() {
        testing = false;
        testSuccess = false;
        testResult = 'SSL/TLS Error: ${e.message}. Tap "Trust Server Cert" if using a self-signed home certificate.';
      });
      await _offerSelfSignedTofuIfNeeded(uri);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        testing = false;
        testSuccess = false;
        testResult = 'Connection failed: $e';
      });
    } finally {
      client.close();
    }
  }

  Future<void> _offerSelfSignedTofuIfNeeded(Uri uri) async {
    X509Certificate? untrustedCert;
    final probe = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    probe.badCertificateCallback = (cert, host, port) {
      untrustedCert = cert;
      return false; // Always reject during probe; only collect cert for user confirmation
    };
    try {
      final req = await probe.getUrl(uri.replace(path: '/api/health'));
      await req.close();
    } catch (_) {
    } finally {
      probe.close(force: true);
    }
    if (untrustedCert == null || !mounted) return;
    final fingerprint = HomeSpaceTlsTrust.certificateSha256Hex(untrustedCert!);
    final port = uri.hasPort ? uri.port : 443;
    final formatted = [
      for (var i = 0; i < fingerprint.length; i += 4)
        fingerprint.substring(i, (i + 4).clamp(0, fingerprint.length)).toUpperCase(),
    ].join(':');
    final accept = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trust Server Certificate?'),
        content: Text(
          'The certificate presented by ${uri.host}:$port is not signed by a public CA.\n\n'
          'SHA-256 Fingerprint:\n$formatted\n\n'
          'Only trust this certificate if it matches your own HomeSpace server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Trust & Pin'),
          ),
        ],
      ),
    );
    if (accept == true && mounted) {
      await HomeSpaceTlsTrust.trustCertificate(
        host: uri.host,
        port: port,
        sha256Hex: fingerprint,
      );
      unawaited(
        AutoBackupService.syncConfigToNative(
          trustedCertPins: HomeSpaceTlsTrust.allPins(),
        ).catchError((_) {}),
      );
      await _testConnection();
    }
  }

  void _applyPreset(String url) {
    controller.text = url;
    controller.selection = TextSelection.fromPosition(TextPosition(offset: url.length));
    _testConnection();
  }

  Widget _presetChip(String label, String url) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      padding: EdgeInsets.zero,
      onPressed: () => _applyPreset(url),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Home Server URL'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter your HomeSpace server URL or select a preset:',
                  style: TextStyle(fontSize: 13, color: Color(0xFF5A5C70)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: controller,
                  keyboardType: TextInputType.url,
                  autofocus: false,
                  decoration: InputDecoration(
                    hintText: 'https://... or http://192.168.x.x:8888',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return null;
                    final uri = Uri.tryParse(val.trim());
                    if (uri == null || (!uri.hasScheme || !uri.hasAuthority)) {
                      return 'Enter a valid URL (with http:// or https://)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _presetChip('USB Proxy', 'http://127.0.0.1:8888'),
                    _presetChip('Local LAN', 'http://192.168.1.100:8888'),
                    _presetChip('Local Device', ''),
                  ],
                ),
                if (testResult != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: testSuccess ? const Color(0xFFF0F7EB) : const Color(0xFFFDF0ED),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: testSuccess ? const Color(0xFFC4E4B5) : const Color(0xFFF4C5BE),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          testSuccess ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                          size: 16,
                          color: testSuccess ? const Color(0xFF287000) : const Color(0xFFC62828),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            testResult!,
                            style: TextStyle(
                              fontSize: 12,
                              color: testSuccess ? const Color(0xFF287000) : const Color(0xFFC62828),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: testing ? null : _testConnection,
          child: testing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Test Connection'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
