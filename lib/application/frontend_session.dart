import 'package:flutter/material.dart';

/// Navigation state for the local frontend preview, not account authentication.
/// Credentials are never retained or written to disk.
class FrontendSession extends ChangeNotifier {
  bool _open = false;
  bool get isOpen => _open;
  void enterPreview() {
    _open = true;
    notifyListeners();
  }

  void logout() {
    _open = false;
    notifyListeners();
  }
}

class FrontendSessionScope extends InheritedNotifier<FrontendSession> {
  const FrontendSessionScope({
    super.key,
    required FrontendSession? session,
    required super.child,
  }) : super(notifier: session);

  static FrontendSession? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<FrontendSessionScope>()
      ?.notifier;
}
