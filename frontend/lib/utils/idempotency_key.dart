import 'dart:math';

final Random _random = Random.secure();

/// A fresh `Idempotency-Key`: 128 random bits as 32 hex characters, inside
/// the server's 1–128 characters of `[A-Za-z0-9_-]`.
String newIdempotencyKey() => [
  for (var i = 0; i < 16; i++)
    _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
].join();
