import 'repositories.dart';

/// Shared by the form and connection adapter; credentials are never accepted.
Uri parseServerAddress(String value) {
  final input = value.trim();
  final address = Uri.tryParse(input);
  if (address == null ||
      !['http', 'https'].contains(address.scheme) ||
      address.host.isEmpty ||
      RegExp(r'\s').hasMatch(input)) {
    throw const LocalActionException(
      'Enter an HTTP or HTTPS address, such as http://192.168.1.20:8080.',
    );
  }
  if (address.userInfo.isNotEmpty || address.hasQuery || address.hasFragment) {
    throw const LocalActionException(
      'Use a server address without credentials, query parameters or fragments.',
    );
  }
  if (address.port < 1 || address.port > 65535) {
    throw const LocalActionException('Use a port between 1 and 65535.');
  }
  return address;
}
