import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BleCryptoException implements Exception {
  final String reason;
  const BleCryptoException(this.reason);

  @override
  String toString() => 'BleCryptoException: $reason';
}

/// AES-128-GCM encryption

class BleCrypto {
  BleCrypto._();

  // "TUSKER_RRC_DEV_1"
  static const List<int> _keyBytes = [
    0x54,
    0x55,
    0x53,
    0x4B,
    0x45,
    0x52,
    0x5F,
    0x52,
    0x52,
    0x43,
    0x5F,
    0x44,
    0x45,
    0x56,
    0x5F,
    0x31,
  ];

  static const String _kSessionCounter = 'ble_crypto_session_counter';

  static final _algorithm = AesGcm.with128bits();

  static final _secretKey = SecretKey(_keyBytes);

  // --------------------------------------------------------------------------
  // Session State
  // --------------------------------------------------------------------------

  static Uint8List? _sessionId;

  static int _packetCounter = 0;

  static int _inboundCounter = 0;

  static Uint8List? _plcSessionId;

  static bool get sessionActive => _sessionId != null;

  // --------------------------------------------------------------------------
  // Session Lifecycle
  // --------------------------------------------------------------------------

  static Future<void> beginSession() async {
    _packetCounter = 0;
    _inboundCounter = 0;
    _plcSessionId = null;
    _sessionId = null;

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_kSessionCounter) ?? 0;
    final next = stored + 1;

    await prefs.setInt(_kSessionCounter, next);
    _sessionId = _encodeUint48(next);
  }

  static void endSession() {
    _sessionId = null;
    _packetCounter = 0;
    _inboundCounter = 0; // reset replay-protection window
    _plcSessionId = null;
  }

  // --------------------------------------------------------------------------
  // Encryption
  // --------------------------------------------------------------------------

  static Future<List<int>> encrypt(List<int> plaintext) async {
    final nonce = _buildNonce();

    final secretBox = await _algorithm.encrypt(
      plaintext,
      secretKey: _secretKey,
      nonce: nonce,
    );

    final rawLen =
        nonce.length + secretBox.cipherText.length + secretBox.mac.bytes.length;
    final raw = Uint8List(rawLen);
    var offset = 0;
    for (final b in nonce) {
      raw[offset++] = b;
    }
    for (final b in secretBox.cipherText) {
      raw[offset++] = b;
    }
    for (final b in secretBox.mac.bytes) {
      raw[offset++] = b;
    }

    return raw.toList();
  }

  // ── Decryption ──

  /// Bytes  0..5   →  PLC nonce prefix
  /// Bytes  6..11  →  Packet counter
  /// Bytes 12..N-17 → Ciphertext
  /// Bytes N-16..N  → GCM Auth Tag

  static Future<List<int>> decrypt(List<int> wireBytes) async {
    final session = _sessionId;
    if (session == null) {
      throw StateError(
        'BleCrypto.decrypt() called outside an active session. '
        'A session must be established via beginSession() before decrypting.',
      );
    }

    final Uint8List raw;
    if (_looksLikeHex(wireBytes)) {
      raw = _hexDecode(wireBytes);
    } else {
      raw = Uint8List.fromList(wireBytes);
    }

    //  Length check
    if (raw.length < 28) {
      throw const BleCryptoException(
        'Packet too short — minimum 28 bytes (12-byte nonce + 16-byte GCM tag).',
      );
    }

    final nonce = raw.sublist(0, 12);

    // verify the PLC's nonce prefix

    final currentPlcSession = _plcSessionId;
    if (currentPlcSession == null) {
      _plcSessionId = Uint8List.fromList(nonce.sublist(0, 6));
    } else {
      for (var i = 0; i < 6; i++) {
        if (nonce[i] != currentPlcSession[i]) {
          throw const BleCryptoException(
            'PLC nonce prefix changed mid-session — possible session hijack '
            'or nonce desynchronisation.',
          );
        }
      }
    }

    //  Decode inbound packet counter
    final inboundCount = _decodeUint48(nonce, 6);

    //  Replay protection:
    if (inboundCount <= _inboundCounter) {
      throw BleCryptoException(
        'Replay detected — inbound counter $inboundCount '
        'is not greater than last accepted $_inboundCounter.',
      );
    }

    // Separate ciphertext and GCM authentication tag.
    final cipherText = raw.sublist(12, raw.length - 16);
    final tagBytes = raw.sublist(raw.length - 16);
    final mac = Mac(tagBytes);

    // AES-GCM decrypt
    final List<int> plaintext;
    try {
      final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
      plaintext = await _algorithm.decrypt(secretBox, secretKey: _secretKey);
    } on SecretBoxAuthenticationError {
      throw const BleCryptoException(
        'GCM authentication tag verification failed — '
        'packet is corrupted, tampered, or uses an incorrect key.',
      );
    } catch (e) {
      throw BleCryptoException('AES-GCM decryption error: $e');
    }

    _inboundCounter = inboundCount;

    return plaintext;
  }

  // ── Internal helpers ──

  static Uint8List _buildNonce() {
    final session = _sessionId;
    if (session == null) {
      throw StateError(
        'BleCrypto.encrypt() called outside an active session. '
        'Call BleCrypto.beginSession() after receiving AUTH_OK.',
      );
    }

    _packetCounter += 1;
    final counter = _packetCounter;

    final nonce = Uint8List(12);

    nonce[0] = session[0];
    nonce[1] = session[1];
    nonce[2] = session[2];
    nonce[3] = session[3];
    nonce[4] = session[4];
    nonce[5] = session[5];

    nonce[6] = (counter >> 40) & 0xFF;
    nonce[7] = (counter >> 32) & 0xFF;
    nonce[8] = (counter >> 24) & 0xFF;
    nonce[9] = (counter >> 16) & 0xFF;
    nonce[10] = (counter >> 8) & 0xFF;
    nonce[11] = counter & 0xFF;

    return nonce;
  }

  static bool _looksLikeHex(List<int> bytes) {
    if (bytes.isEmpty || bytes.length.isOdd) return false;
    return bytes.every(
      (b) =>
          (b >= 0x30 && b <= 0x39) ||
          (b >= 0x41 && b <= 0x46) ||
          (b >= 0x61 && b <= 0x66),
    );
  }

  /// Decodes an ASCII hex byte sequence into raw binary.
  static Uint8List _hexDecode(List<int> hexBytes) {
    final text = String.fromCharCodes(hexBytes);
    final result = Uint8List(text.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(text.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  static int _decodeUint48(Uint8List bytes, int offset) {
    return (bytes[offset] & 0xFF) * 0x10000000000 +
        (bytes[offset + 1] & 0xFF) * 0x100000000 +
        (bytes[offset + 2] & 0xFF) * 0x1000000 +
        (bytes[offset + 3] & 0xFF) * 0x10000 +
        (bytes[offset + 4] & 0xFF) * 0x100 +
        (bytes[offset + 5] & 0xFF);
  }

  static Uint8List _encodeUint48(int value) {
    assert(value >= 0, 'Session counter must be non-negative');
    final bytes = Uint8List(6);
    bytes[0] = (value >> 40) & 0xFF;
    bytes[1] = (value >> 32) & 0xFF;
    bytes[2] = (value >> 24) & 0xFF;
    bytes[3] = (value >> 16) & 0xFF;
    bytes[4] = (value >> 8) & 0xFF;
    bytes[5] = value & 0xFF;
    return bytes;
  }
}
