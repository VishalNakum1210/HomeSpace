import 'package:flutter/material.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../domain/repositories.dart';

class AppLockPage extends StatefulWidget {
  final HomeRepository repository;
  const AppLockPage({super.key, required this.repository});

  @override
  State<AppLockPage> createState() => _AppLockPageState();
}

class _AppLockPageState extends State<AppLockPage> {
  late bool _enabled;
  String? _pin;

  @override
  void initState() {
    super.initState();
    _enabled = widget.repository.profile.appLockEnabled;
    _pin = widget.repository.profile.appLockPin;
  }

  Future<void> _promptSetPin({bool isChanging = false}) async {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.lock_rounded, color: Color(0xFF1A73E8)),
              const SizedBox(width: 8),
              Text(
                isChanging ? 'Change 4-Digit PIN' : 'Set 4-Digit PIN',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('pin-input-field'),
                controller: pinController,
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
                controller: confirmController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Confirm 4-digit PIN',
                  border: const OutlineInputBorder(),
                  errorText: errorText,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('save-pin-btn'),
              onPressed: () async {
                final p = pinController.text.trim();
                final c = confirmController.text.trim();
                if (p.length != 4 || int.tryParse(p) == null) {
                  setDialogState(() => errorText = 'PIN must be exactly 4 digits');
                  return;
                }
                if (p != c) {
                  setDialogState(() => errorText = 'PINs do not match');
                  return;
                }
                Navigator.pop(dialogCtx);
                await widget.repository.setAppLock(enabled: true, pin: p);
                if (mounted) {
                  setState(() {
                    _enabled = true;
                    _pin = p;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      behavior: SnackBarBehavior.floating,
                      content: Text('App Lock PIN configured successfully.'),
                    ),
                  );
                }
              },
              child: const Text('Save PIN'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleToggle(bool val) async {
    if (val) {
      if (_pin == null || _pin!.isEmpty) {
        await _promptSetPin();
      } else {
        await widget.repository.setAppLock(enabled: true, pin: _pin);
        setState(() => _enabled = true);
      }
    } else {
      await widget.repository.setAppLock(enabled: false, pin: _pin);
      setState(() => _enabled = false);
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
