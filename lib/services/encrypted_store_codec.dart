import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Shared AES-256-GCM envelope format used by every encrypted local store
/// (authentication log, operator repository, and future stores) so they
/// all frame records identically instead of duplicating nonce handling.
///
/// Envelope layout: `version(1 byte) | nonce(12 bytes) | ciphertext | tag(16 bytes)`.
/// A fresh random nonce is generated on every [encode] call and is never
/// reused with the same key. [decode] returns `null` on any authentication-
/// tag failure — that failure *is* the corruption/tamper/truncation check,
/// not a separate step.
class EncryptedStoreCodec {
  EncryptedStoreCodec._();

  static const int _version = 1;
  static const int _nonceLength = 12;
  static const int _tagLength = 16;

  static final AesGcm _algorithm = AesGcm.with256bits();

  static Future<Uint8List> encode(SecretKey key, List<int> plaintext) async {
    final nonce = _algorithm.newNonce();
    final secretBox = await _algorithm.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
    );

    final out = BytesBuilder(copy: false);
    out.addByte(_version);
    out.add(nonce);
    out.add(secretBox.cipherText);
    out.add(secretBox.mac.bytes);
    return out.toBytes();
  }

  /// Returns the decrypted plaintext, or `null` if [envelope] is too short,
  /// carries an unknown version byte, or fails GCM authentication.
  static Future<List<int>?> decode(SecretKey key, List<int> envelope) async {
    if (envelope.isEmpty || envelope[0] != _version) return null;

    const minLength = 1 + _nonceLength + _tagLength;
    if (envelope.length < minLength) return null;

    final nonce = envelope.sublist(1, 1 + _nonceLength);
    final tagStart = envelope.length - _tagLength;
    final cipherText = envelope.sublist(1 + _nonceLength, tagStart);
    final tag = envelope.sublist(tagStart);

    try {
      final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(tag));
      return await _algorithm.decrypt(secretBox, secretKey: key);
    } on SecretBoxAuthenticationError {
      return null;
    } catch (_) {
      return null;
    }
  }
}
