import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Pure-Dart cryptographic helper for salted iterated PIN hashing.
class PinSecurity {
  static const String _prefix = 'v1\$';
  static const int _iterations = 4096;

  static bool isHashed(String? stored) =>
      stored != null && stored.startsWith(_prefix);

  /// Produces a salted iterated SHA-256 hash (`v1$<saltHex>$<digestHex>`).
  static String hashPin(String pin) {
    final rng = Random.secure();
    final saltBytes = List<int>.generate(16, (_) => rng.nextInt(256));
    final saltHex = _bytesToHex(saltBytes);
    final digestHex = _deriveHex(pin, saltHex);
    return '$_prefix$saltHex\$$digestHex';
  }

  /// Verifies [candidatePin] against a stored salted hash (or legacy 4-digit PIN).
  static bool verifyPin(String candidatePin, String? storedPin) {
    if (candidatePin.isEmpty || storedPin == null || storedPin.isEmpty) {
      return false;
    }
    if (storedPin.startsWith(_prefix)) {
      final parts = storedPin.split(r'$');
      if (parts.length != 3 || parts[1].isEmpty || parts[2].isEmpty) {
        return false;
      }
      final expectedHex = parts[2];
      final actualHex = _deriveHex(candidatePin, parts[1]);
      return _constantTimeEquals(actualHex, expectedHex);
    }
    // Legacy migration support for pre-hash stored PINs.
    return _constantTimeEquals(candidatePin, storedPin);
  }

  static String _deriveHex(String pin, String saltHex) {
    Uint8List state = Uint8List.fromList(utf8.encode('$saltHex:$pin'));
    final saltBytes = utf8.encode(saltHex);
    for (var i = 0; i < _iterations; i++) {
      final input = Uint8List(state.length + saltBytes.length);
      input.setAll(0, state);
      input.setAll(state.length, saltBytes);
      state = _sha256(input);
    }
    return _bytesToHex(state);
  }

  static bool _constantTimeEquals(String a, String b) {
    final bytesA = utf8.encode(a);
    final bytesB = utf8.encode(b);
    if (bytesA.length != bytesB.length) return false;
    var diff = 0;
    for (var i = 0; i < bytesA.length; i++) {
      diff |= bytesA[i] ^ bytesB[i];
    }
    return diff == 0;
  }

  static String _bytesToHex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
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

  static Uint8List _sha256(Uint8List data) {
    final bitLen = data.length * 8;
    final padLen = ((56 - (data.length + 1) % 64) + 64) % 64;
    final padded = Uint8List(data.length + 1 + padLen + 8);
    padded.setAll(0, data);
    padded[data.length] = 0x80;
    final bd = ByteData.sublistView(padded);
    bd.setUint32(padded.length - 8, (bitLen ~/ 0x100000000) & 0xffffffff, Endian.big);
    bd.setUint32(padded.length - 4, bitLen & 0xffffffff, Endian.big);

    var h0 = 0x6a09e667;
    var h1 = 0xbb67ae85;
    var h2 = 0x3c6ef372;
    var h3 = 0xa54ff53a;
    var h4 = 0x510e527f;
    var h5 = 0x9b05688c;
    var h6 = 0x1f83d9ab;
    var h7 = 0x5be0cd19;

    final w = Uint32List(64);
    for (var offset = 0; offset < padded.length; offset += 64) {
      for (var i = 0; i < 16; i++) {
        w[i] = bd.getUint32(offset + i * 4, Endian.big);
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

    final out = Uint8List(32);
    final outBd = ByteData.sublistView(out);
    outBd.setUint32(0, h0, Endian.big);
    outBd.setUint32(4, h1, Endian.big);
    outBd.setUint32(8, h2, Endian.big);
    outBd.setUint32(12, h3, Endian.big);
    outBd.setUint32(16, h4, Endian.big);
    outBd.setUint32(20, h5, Endian.big);
    outBd.setUint32(24, h6, Endian.big);
    outBd.setUint32(28, h7, Endian.big);
    return out;
  }

  static int _rotr(int x, int n) => ((x >>> n) | (x << (32 - n))) & 0xffffffff;
}
