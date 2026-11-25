import 'dart:io';

Future<void> main(List<String> args) async {
  final rawTarget = args.isNotEmpty
      ? args.first
      : Platform.environment['HOMESPACE_TARGET_URL'];
  if (rawTarget == null || rawTarget.trim().isEmpty) {
    stderr.writeln(
      'Usage: dart run scripts/test_proxy.dart <target-base-url> '
      '(or set HOMESPACE_TARGET_URL)',
    );
    exitCode = 64;
    return;
  }
  final baseTargetUri = Uri.parse(rawTarget.trim());
  final client = HttpClient();
  if (Platform.environment['HOMESPACE_ALLOW_INSECURE_PROXY'] == '1') {
    client.badCertificateCallback = (c, h, p) => true;
  }
  client.connectionTimeout = const Duration(seconds: 15);

  final port = int.tryParse(Platform.environment['PROXY_PORT'] ?? '') ?? 8888;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('HTTP PROXY LISTENING ON PORT $port -> $baseTargetUri');

  server.listen((req) async {
    try {
      final targetUri = baseTargetUri.resolveUri(
        Uri(
          path: req.uri.path,
          query: req.uri.hasQuery ? req.uri.query : null,
        ),
      );
      final targetReq = await client.openUrl(req.method, targetUri);

      req.headers.forEach((name, values) {
        if (name.toLowerCase() != 'host') {
          for (final v in values) {
            targetReq.headers.add(name, v);
          }
        }
      });
      targetReq.headers.set('host', baseTargetUri.authority);
      targetReq.headers.set('accept-encoding', 'identity');

      await targetReq.addStream(req);
      final targetResp = await targetReq.close();

      req.response.statusCode = targetResp.statusCode;
      targetResp.headers.forEach((name, values) {
        for (final v in values) {
          req.response.headers.add(name, v);
        }
      });

      await req.response.addStream(targetResp);
      await req.response.close();
    } catch (e) {
      // Ignore proxy forward errors
      try {
        req.response.statusCode = 502;
        req.response.write('Proxy error: $e');
        await req.response.close();
      } catch (_) {}
    }
  });
}
