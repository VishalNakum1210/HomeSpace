import 'dart:io';

Future<void> main() async {
  final client = HttpClient();
  client.badCertificateCallback = (c, h, p) => true;
  client.connectionTimeout = const Duration(seconds: 15);

  final server = await HttpServer.bind(InternetAddress.anyIPv4, 8888);
  print('HTTP PROXY LISTENING ON PORT 8888');

  server.listen((req) async {
    try {
      final targetUri = Uri.parse(
        'https://vishal-hp-laptop-15s-fr5xxx.tailda4c64.ts.net:8443${req.uri.path}${req.uri.hasQuery ? '?${req.uri.query}' : ''}',
      );
      final targetReq = await client.openUrl(req.method, targetUri);
      
      req.headers.forEach((name, values) {
        if (name.toLowerCase() != 'host') {
          for (final v in values) {
            targetReq.headers.add(name, v);
          }
        }
      });
      targetReq.headers.set('host', 'vishal-hp-laptop-15s-fr5xxx.tailda4c64.ts.net');
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
