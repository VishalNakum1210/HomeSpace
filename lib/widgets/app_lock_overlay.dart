import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/repositories.dart';

class AppLockOverlay extends StatefulWidget {
  final HomeRepository repository;
  final Widget child;

  const AppLockOverlay({
    super.key,
    required this.repository,
    required this.child,
  });

  @override
  State<AppLockOverlay> createState() => _AppLockOverlayState();
}

class _AppLockOverlayState extends State<AppLockOverlay> with WidgetsBindingObserver {
  bool _locked = false;
  String _enteredPin = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final p = widget.repository.profile;
    if (p.appLockEnabled && p.appLockPin != null && p.appLockPin!.isNotEmpty) {
      _locked = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      final p = widget.repository.profile;
      if (p.appLockEnabled && p.appLockPin != null && p.appLockPin!.isNotEmpty) {
        setState(() {
          _locked = true;
          _enteredPin = '';
          _error = null;
        });
      }
    }
  }

  void _onDigit(String digit) {
    if (_enteredPin.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() {
      _enteredPin += digit;
      _error = null;
    });

    if (_enteredPin.length == 4) {
      final expected = widget.repository.profile.appLockPin;
      if (_enteredPin == expected) {
        HapticFeedback.mediumImpact();
        setState(() {
          _locked = false;
          _enteredPin = '';
          _error = null;
        });
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          _error = 'Incorrect PIN. Try again.';
          _enteredPin = '';
        });
      }
    }
  }

  void _onBackspace() {
    if (_enteredPin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.repository.profile;
    final isLockActive = _locked && p.appLockEnabled && p.appLockPin != null && p.appLockPin!.isNotEmpty;

    return Stack(
      children: [
        widget.child,
        if (isLockActive)
          Positioned.fill(
            child: Material(
              key: const ValueKey('app-lock-screen'),
              color: Theme.of(context).scaffoldBackgroundColor,
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A73E8).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_rounded,
                        size: 36,
                        color: Color(0xFF1A73E8),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'HomeSpace is Locked',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter your 4-digit PIN to continue',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 32),
                    // 4 PIN Dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 0; i < 4; i++)
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 10),
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < _enteredPin.length
                                  ? const Color(0xFF1A73E8)
                                  : Colors.grey.withValues(alpha: 0.3),
                              border: Border.all(
                                color: const Color(0xFF1A73E8),
                                width: 1.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 24,
                      child: _error != null
                          ? Text(
                              _error!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    const Spacer(),
                    // Numeric Keypad
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: Column(
                        children: [
                          for (int r = 0; r < 3; r++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  for (int c = 1; c <= 3; c++)
                                    _KeypadButton(
                                      text: '${r * 3 + c}',
                                      onTap: () => _onDigit('${r * 3 + c}'),
                                    ),
                                ],
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                const SizedBox(width: 64, height: 64),
                                _KeypadButton(
                                  text: '0',
                                  onTap: () => _onDigit('0'),
                                ),
                                SizedBox(
                                  width: 64,
                                  height: 64,
                                  child: IconButton(
                                    key: const ValueKey('pin-backspace-btn'),
                                    icon: const Icon(Icons.backspace_outlined),
                                    onPressed: _onBackspace,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _KeypadButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _KeypadButton({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: OutlinedButton(
        key: ValueKey('pin-key-$text'),
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
        onPressed: onTap,
        child: Text(
          text,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
