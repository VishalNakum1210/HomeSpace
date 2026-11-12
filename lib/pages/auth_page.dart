import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/frontend_session.dart';
import '../design/space_symbols.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../design/system_ui.dart';

class AuthPage extends StatefulWidget {
  final FrontendSession session;
  const AuthPage({super.key, required this.session});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
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

  Future<void> submit() async {
    if (submitting) return;
    if (!form.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
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
  }

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
                          ScrollViewKeyboardDismissBehavior.onDrag,
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
                                    color: Color(0xFF77798E),
                                  ),
                                ),
                                SizedBox(height: register ? 22 : 34),
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
                                  ),
                                  SizedBox(height: register ? 12 : 18),
                                ],
                                _field(
                                  'Email',
                                  'Enter your email',
                                  email,
                                  Icons.mail_outline_rounded,
                                  emailField: true,
                                  autofill: AutofillHints.email,
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
                                        color: Color(0xFF77798E),
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
                                            'Password recovery will be available when accounts are connected to your home server. No reset email has been sent.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              child: const Text('OK'),
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
                                  label: register ? 'Create account' : 'Log in',
                                  backgroundColor: const Color(0xFF49A91D),
                                  foregroundColor: Colors.white,
                                  onPressed: submit,
                                ),
                                SizedBox(height: register ? 8 : 28),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      register
                                          ? 'Already have an account?'
                                          : 'New to HomeSpace?',
                                      style: const TextStyle(
                                        color: Color(0xFF77798E),
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
                                ),
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
            color: Color(0xFF77798E),
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
