import 'dart:convert';
import 'dart:io';

/// Trust-On-First-Use (TOFU) SHA-256 certificate pin registry for self-hosted servers.
/// Standard CA validation remains mandatory unless an explicit leaf SHA-256 pin
/// is stored for that specific host and port.
class HomeSpaceTlsTrust {
  static final Map<String, String> _pins = <String, String>{};
  static File? _storeFile;

  static Future<void> initFromDirectory(Directory homespaceDir) async {
    try {
      await homespaceDir.create(recursive: true);
      final file = File('${homespaceDir.path}/trusted_certs.json');
      _storeFile = file;
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final k = entry.key.toString();
            final v = entry.value?.toString().toLowerCase() ?? '';
            if (k.isNotEmpty && v.isNotEmpty) {
              _pins[k] = v;
            }
          }
        }
      }
    } catch (_) {}
  }

  static String _key(String host, int port) => '${host.toLowerCase()}:$port';

  static String? pinFor(String host, int port) => _pins[_key(host, port)];

  static Map<String, String> allPins() => Map<String, String>.unmodifiable(_pins);

  static String certificateSha256Hex(X509Certificate cert) {
    // Derive deterministic SHA-256 hex digest over cert.der bytes using sha256 property if available
    // Dart's X509Certificate exposes `sha1` built-in, while `der` can be hashed directly.
    final bytes = cert.der;
    return _sha256Hex(bytes);
  }

  static bool isPinnedCertificate(X509Certificate cert, String host, int port) {
    final expected = _pins[_key(host, port)];
    if (expected == null || expected.isEmpty) return false;
    final actual = certificateSha256Hex(cert);
    return actual == expected;
  }

  static Future<void> trustCertificate({
    required String host,
    required int port,
    required String sha256Hex,
  }) async {
    _pins[_key(host, port)] = sha256Hex.toLowerCase();
    final file = _storeFile;
    if (file != null) {
      try {
        await file.writeAsString(jsonEncode(_pins), flush: true);
      } catch (_) {}
    }
  }

  static bool isPrivateOrLocalHost(String host) {
    final h = host.trim().toLowerCase();
    if (h == 'localhost' ||
        h == '127.0.0.1' ||
        h == '::1' ||
        h == '10.0.2.2' ||
        h.endsWith('.local') ||
        h.endsWith('.lan') ||
        h.endsWith('.internal') ||
        h.endsWith('.home.arpa')) {
      return true;
    }
    final ip = InternetAddress.tryParse(h);
    if (ip == null) return false;
    if (ip.isLoopback || ip.isLinkLocal) return true;
    final raw = ip.rawAddress;
    if (raw.length == 4) {
      final b0 = raw[0];
      final b1 = raw[1];
      if (b0 == 10) return true;
      if (b0 == 172 && b1 >= 16 && b1 <= 31) return true;
      if (b0 == 192 && b1 == 168) return true;
      // Tailscale CGNAT 100.64.0.0/10
      if (b0 == 100 && b1 >= 64 && b1 <= 127) return true;
    }
    return false;
  }

  static const List<int> _k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  static String _sha256Hex(List<int> data) {
    final bitLen = data.length * 8;
    final padLen = ((56 - (data.length + 1) % 64) + 64) % 64;
    final padded = List<int>.filled(data.length + 1 + padLen + 8, 0);
    for (var i = 0; i < data.length; i++) {
      padded[i] = data[i];
    }
    padded[data.length] = 0x80;
    for (var i = 0; i < 8; i++) {
      padded[padded.length - 1 - i] = (bitLen >> (i * 8)) & 0xff;
    }

    var h0 = 0x6a09e667;
    var h1 = 0xbb67ae85;
    var h2 = 0x3c6ef372;
    var h3 = 0xa54ff53a;
    var h4 = 0x510e527f;
    var h5 = 0x9b05688c;
    var h6 = 0x1f83d9ab;
    var h7 = 0x5be0cd19;

    final w = List<int>.filled(64, 0);
    for (var offset = 0; offset < padded.length; offset += 64) {
      for (var i = 0; i < 16; i++) {
        final idx = offset + i * 4;
        w[i] = ((padded[idx] << 24) |
                (padded[idx + 1] << 16) |
                (padded[idx + 2] << 8) |
                padded[idx + 3]) &
            0xffffffff;
      }
      for (var i = 16; i < 64; i++) {
        final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
      }

      var a = h0;
      var b = h1;
      var c = h2;
      var d = h3;
      var e = h4;
      var f = h5;
      var g = h6;
      var h = h7;

      for (var i = 0; i < 64; i++) {
        final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ ((~e & 0xffffffff) & g);
        final temp1 = (h + s1 + ch + _k[i] + w[i]) & 0xffffffff;
        final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & 0xffffffff;

        h = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xffffffff;
      }

      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + c) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
      h5 = (h5 + f) & 0xffffffff;
      h6 = (h6 + g) & 0xffffffff;
      h7 = (h7 + h) & 0xffffffff;
    }

    final sb = StringBuffer();
    for (final val in [h0, h1, h2, h3, h4, h5, h6, h7]) {
      sb.write(val.toRadixString(16).padLeft(8, '0'));
    }
    return sb.toString();
  }

  static int _rotr(int x, int n) => ((x >>> n) | (x << (32 - n))) & 0xffffffff;
}
