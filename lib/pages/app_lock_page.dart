import 'package:flutter/material.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../domain/pin_security.dart';
import '../domain/repositories.dart';

class AppLockPage extends StatefulWidget {
  final HomeRepository repository;
  const AppLockPage({super.key, required this.repository});

  @override
  State<AppLockPage> createState() => _AppLockPageState();
}

class _AppLockPageState extends State<AppLockPage> {
  late bool _enabled;
  late bool _hasPin;

  @override
  void initState() {
    super.initState();
    _enabled = widget.repository.profile.appLockEnabled;
    final stored = widget.repository.profile.appLockPin;
    _hasPin = stored != null && stored.isNotEmpty;
  }

  Future<bool> _verifyCurrentPin({String title = 'Verify Current PIN'}) async {
    final storedPin = widget.repository.profile.appLockPin;
    if (storedPin == null || storedPin.isEmpty) return true;
    final verified = await showDialog<bool>(
      context: context,
      builder: (_) => _VerifyPinDialog(
        title: title,
        storedPin: storedPin,
      ),
    );
    return verified == true;
  }

  Future<void> _promptSetPin({bool isChanging = false}) async {
    if (isChanging && _hasPin) {
      final ok = await _verifyCurrentPin(title: 'Verify Current PIN');
      if (!ok || !mounted) return;
    }

    final newPin = await showDialog<String>(
      context: context,
      builder: (_) => _SetPinDialog(isChanging: isChanging),
    );
    if (newPin == null || !mounted) return;

    await widget.repository.setAppLock(enabled: true, pin: newPin);
    if (!mounted) return;
    setState(() {
      _enabled = true;
      _hasPin = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('App Lock PIN configured successfully.'),
      ),
    );
  }

  Future<void> _handleToggle(bool val) async {
    if (val) {
      if (!_hasPin) {
        await _promptSetPin();
      } else {
        await widget.repository.setAppLock(
          enabled: true,
          pin: widget.repository.profile.appLockPin,
        );
        if (mounted) setState(() => _enabled = true);
      }
    } else {
      if (_hasPin) {
        final ok = await _verifyCurrentPin(title: 'Verify PIN to Disable');
        if (!ok || !mounted) return;
      }
      await widget.repository.setAppLock(
        enabled: false,
        pin: widget.repository.profile.appLockPin,
      );
      if (mounted) setState(() => _enabled = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = SpaceStyle.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Lock & Privacy'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SpaceCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A73E8).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.security_rounded, color: Color(0xFF1A73E8)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PIN Security',
                            style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Protect your personal memories with a 4-digit PIN',
                            style: text.bodySmall?.copyWith(color: style.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                SwitchListTile(
                  key: const ValueKey('app-lock-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Lock app on open', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(_enabled ? 'App is locked when opened' : 'App opens immediately'),
                  value: _enabled,
                  onChanged: _handleToggle,
                ),
                if (_enabled) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey('change-pin-btn'),
                    icon: const Icon(Icons.key_rounded, size: 18),
                    label: const Text('Change 4-Digit PIN'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _promptSetPin(isChanging: true),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'When App Lock is turned on, HomeSpace prompts for your PIN whenever the app is launched or resumed from the background.',
              style: text.bodySmall?.copyWith(color: style.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _SetPinDialog extends StatefulWidget {
  final bool isChanging;
  const _SetPinDialog({required this.isChanging});

  @override
  State<_SetPinDialog> createState() => _SetPinDialogState();
}

class _SetPinDialogState extends State<_SetPinDialog> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.lock_rounded, color: Color(0xFF1A73E8)),
          const SizedBox(width: 8),
          Text(
            widget.isChanging ? 'Change 4-Digit PIN' : 'Set 4-Digit PIN',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('pin-input-field'),
            controller: _pinController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Enter 4-digit PIN',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('pin-confirm-input-field'),
            controller: _confirmController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Confirm 4-digit PIN',
              border: const OutlineInputBorder(),
              errorText: _errorText,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('save-pin-btn'),
          onPressed: () {
            final p = _pinController.text.trim();
            final c = _confirmController.text.trim();
            if (p.length != 4 || int.tryParse(p) == null) {
              setState(() => _errorText = 'PIN must be exactly 4 digits');
              return;
            }
            if (p != c) {
              setState(() => _errorText = 'PINs do not match');
              return;
            }
            Navigator.pop(context, p);
          },
          child: const Text('Save PIN'),
        ),
      ],
    );
  }
}

class _VerifyPinDialog extends StatefulWidget {
  final String title;
  final String storedPin;
  const _VerifyPinDialog({required this.title, required this.storedPin});

  @override
  State<_VerifyPinDialog> createState() => _VerifyPinDialogState();
}

class _VerifyPinDialogState extends State<_VerifyPinDialog> {
  final _pinController = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
      content: TextField(
        key: const ValueKey('verify-current-pin-field'),
        controller: _pinController,
        keyboardType: TextInputType.number,
        maxLength: 4,
        obscureText: true,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Current 4-digit PIN',
          border: const OutlineInputBorder(),
          errorText: _errorText,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('verify-pin-submit-btn'),
          onPressed: () {
            final entered = _pinController.text.trim();
            if (!PinSecurity.verifyPin(entered, widget.storedPin)) {
              setState(() => _errorText = 'Incorrect PIN');
              return;
            }
            Navigator.pop(context, true);
          },
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
