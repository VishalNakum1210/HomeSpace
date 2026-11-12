import 'package:flutter/material.dart';

class FrontendSession extends ChangeNotifier {
  bool _open = false;
  Uri? _serverUri;
  String? _authToken;
  String? _userId;
  String? _userEmail;

  bool get isOpen => _open;
  Uri? get serverUri => _serverUri;
  String? get authToken => _authToken;
  String? get userId => _userId;
  String? get userEmail => _userEmail;

  void enterPreview() {
    _open = true;
    notifyListeners();
  }

  void setAuthenticated({
    required Uri serverUri,
    required String token,
    required String userId,
    required String email,
  }) {
    _serverUri = serverUri;
    _authToken = token;
    _userId = userId;
    _userEmail = email;
    _open = true;
    notifyListeners();
  }

  void logout() {
    _open = false;
    _authToken = null;
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
